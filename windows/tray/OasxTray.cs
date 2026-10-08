using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

// Compatibility tray host for installed OASX builds without native tray support.
internal sealed class OasxTray : ApplicationContext
{
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, IntPtr param);
    delegate bool EnumWindow(IntPtr window, IntPtr param);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int size);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wp, IntPtr lp);
    readonly NotifyIcon tray = new NotifyIcon();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
    readonly EventWaitHandle restoreEvent;
    readonly string exePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "oasx.exe");
    readonly string logPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "logs", "oasx_tray.log");
    IntPtr window;
    DateTime lastFound = DateTime.UtcNow;

    [STAThread]
    static void Main(string[] args)
    {
        bool owner;
        using (var mutex = new Mutex(true, @"Local\OASX.Tray", out owner))
        using (var restore = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\OASX.Tray.Restore"))
        {
            if (!owner) { if (Array.IndexOf(args, "--restore") >= 0) restore.Set(); return; }
            Application.EnableVisualStyles();
            Application.Run(new OasxTray(restore));
        }
    }

    OasxTray(EventWaitHandle restore)
    {
        restoreEvent = restore;
        tray.Text = "OASX";
        tray.Icon = Icon.ExtractAssociatedIcon(exePath) ?? SystemIcons.Application;
        tray.ContextMenuStrip = new ContextMenuStrip();
        tray.ContextMenuStrip.Items.Add("显示窗口", null, delegate { Restore(); });
        tray.ContextMenuStrip.Items.Add("退出 OASX", null, delegate {
            Restore();
            if (IsWindow(window)) PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero);
        });
        tray.MouseClick += delegate(object sender, MouseEventArgs e) {
            if (e.Button == MouseButtons.Left) Restore();
        };
        timer.Interval = 150;
        timer.Tick += delegate { Tick(); };
        timer.Start();
        Log("Tray host started.");
    }

    void Tick()
    {
        if (!IsWindow(window))
        {
            tray.Visible = false;
            window = IntPtr.Zero;
            EnumWindows(delegate(IntPtr candidate, IntPtr unused) {
                var name = new StringBuilder(128);
                GetClassName(candidate, name, name.Capacity);
                if (name.ToString() != "FLUTTER_RUNNER_WIN32_WINDOW") return true;
                uint pid;
                GetWindowThreadProcessId(candidate, out pid);
                try {
                    using (var process = Process.GetProcessById((int)pid)) {
                        if (!String.Equals(process.MainModule.FileName, exePath, StringComparison.OrdinalIgnoreCase)) return true;
                    }
                } catch (Exception) { return true; }
                window = candidate;
                return false;
            }, IntPtr.Zero);
        }
        if (window == IntPtr.Zero)
        {
            if ((DateTime.UtcNow - lastFound).TotalSeconds > 30) ExitThread();
            return;
        }
        lastFound = DateTime.UtcNow;
        if (restoreEvent.WaitOne(0)) Restore();
        if (IsIconic(window) && !tray.Visible)
        {
            // Register the icon before hiding, so a restore path always exists.
            tray.Visible = true;
            ShowWindow(window, 0);
            Log("Minimized to tray.");
        }
    }

    void Restore()
    {
        if (!IsWindow(window)) return;
        ShowWindow(window, 9);
        SetForegroundWindow(window);
        tray.Visible = false;
        Log("Restored from tray.");
    }

    void Log(string message)
    {
        try { File.AppendAllText(logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + message + Environment.NewLine); }
        catch (IOException) { }
    }

    protected override void ExitThreadCore()
    {
        timer.Stop();
        timer.Dispose();
        tray.Visible = false;
        tray.Dispose();
        base.ExitThreadCore();
    }
}
