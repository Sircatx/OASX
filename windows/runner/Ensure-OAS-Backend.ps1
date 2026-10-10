[CmdletBinding()]
param(
    [string]$OasRoot = '',
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
if (-not $OasRoot) { $OasRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'OnmyojiAutoScript' }
$python = Join-Path $OasRoot 'toolkit\python.exe'
$server = Join-Path $OasRoot 'server.py'
$logRoot = Join-Path (Split-Path -Parent $OasRoot) 'logs'
$logFile = Join-Path $logRoot 'oasx_backend_startup.log'
$mutex = New-Object Threading.Mutex($false, 'Local\OASX.BackendStartup')
$locked = $false
$exitCode = 0

function Write-BackendLog([string]$Message) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Add-Content -LiteralPath $logFile -Encoding UTF8 -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Test-BackendReady {
    try {
        $response = Invoke-RestMethod -Uri 'http://127.0.0.1:22288/home/test' -TimeoutSec 2
        return $response.message -eq 'test'
    }
    catch { return $false }
}

try {
    foreach ($path in @($python, $server)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
    }
    if (-not $ValidateOnly) {
        try { $locked = $mutex.WaitOne(65000) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Timed out waiting for another backend launcher.' }
        if (Test-BackendReady) {
            Write-BackendLog 'OAS backend is already ready; reusing it.'
        }
        else {
            # An existing server may still be loading. Do not spawn a second copy.
            $existing = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" |
                Where-Object { $_.ExecutablePath -in @($python, (Join-Path $OasRoot 'toolkit\pythonw.exe')) -and $_.CommandLine -match '\bserver\.py\b' })
            $started = $null
            if ($existing.Count -eq 0) {
                $info = New-Object Diagnostics.ProcessStartInfo
                $info.FileName = $python
                $info.Arguments = 'server.py'
                $info.WorkingDirectory = $OasRoot
                $info.UseShellExecute = $false
                $info.CreateNoWindow = $true
                $runtimePath = @('toolkit\alias', 'toolkit\command', 'toolkit', 'toolkit\Scripts', 'toolkit\Git\mingw64\bin', 'toolkit\Lib\site-packages\adbutils\binaries') |
                    ForEach-Object { Join-Path $OasRoot $_ }
                $info.EnvironmentVariables['PATH'] = ($runtimePath -join ';') + ';' + $env:Path
                $started = [Diagnostics.Process]::Start($info)
                Write-BackendLog "Started OAS backend (PID $($started.Id))."
            }
            else { Write-BackendLog "Waiting for existing OAS backend (PID $($existing.ProcessId -join ','))." }
            $deadline = (Get-Date).AddSeconds(60)
            while (-not (Test-BackendReady)) {
                if ($started -and $started.HasExited) { throw "OAS backend exited with code $($started.ExitCode)." }
                if ((Get-Date) -ge $deadline) { throw 'OAS backend HTTP readiness timed out on port 22288.' }
                Start-Sleep -Milliseconds 500
            }
            Write-BackendLog 'OAS backend HTTP API is ready on port 22288.'
        }
    }
}
catch {
    $exitCode = 1
    Write-BackendLog "ERROR: $($_.Exception.Message)"
    Write-Error $_ -ErrorAction Continue
}
finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
exit $exitCode
