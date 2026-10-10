#ifndef RUNNER_BACKEND_STARTUP_H_
#define RUNNER_BACKEND_STARTUP_H_

#include <windows.h>
#include <string>
#include <vector>

// Use the same serialized, hidden launcher as the desktop and scheduled entries.
inline bool EnsureOasBackend(const std::wstring& app_directory) {
  wchar_t system_directory[MAX_PATH] = {};
  if (GetSystemDirectoryW(system_directory, ARRAYSIZE(system_directory)) == 0) {
    return false;
  }
  const std::wstring powershell = std::wstring(system_directory) +
      L"\\WindowsPowerShell\\v1.0\\powershell.exe";
  const std::wstring command = L"\"" + powershell +
      L"\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" +
      app_directory + L"\\Ensure-OAS-Backend.ps1\"";
  std::vector<wchar_t> buffer(command.begin(), command.end());
  buffer.push_back(L'\0');
  STARTUPINFOW startup = {};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process = {};
  if (!CreateProcessW(powershell.c_str(), buffer.data(), nullptr, nullptr,
      FALSE, CREATE_NO_WINDOW, nullptr, app_directory.c_str(), &startup, &process)) {
    return false;
  }
  CloseHandle(process.hThread);
  // Another entry may be starting the backend under the shared mutex.
  const DWORD wait = WaitForSingleObject(process.hProcess, 135000);
  DWORD exit_code = EXIT_FAILURE;
  if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &exit_code);
  if (wait == WAIT_TIMEOUT) TerminateProcess(process.hProcess, EXIT_FAILURE);
  CloseHandle(process.hProcess);
  return wait == WAIT_OBJECT_0 && exit_code == EXIT_SUCCESS;
}

#endif
