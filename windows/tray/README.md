# Windows 托盘最小化

`windows/runner/flutter_window.cpp` 实现原生托盘：最小化时隐藏窗口，左键恢复，右键显示窗口或退出，并处理 Explorer 重启时重建图标。

已安装的旧版 OASX 使用 `OASX-tray.exe` 辅助程序提供最小化行为。`Start-OASX.ps1` 和 `Toggle-OASX.ps1` 自动启动该程序，已有窗口也可直接接入，无需重启 OASX。辅助程序只控制前端窗口，不停止后端或自动化任务；窗口关闭后最多 30 秒自动退出。重复启动不会创建多个托盘宿主。

在工作区根目录通过系统自带编译器重新构建辅助程序：

```powershell
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll '/win32icon:OASX-source\windows\runner\resources\app_icon.ico' '/out:OASX\OASX-tray.exe' 'OASX-source\windows\tray\OasxTray.cs'
```

直接运行旧版 `oasx.exe` 时，需同时运行旁边的 `OASX-tray.exe`；从启动菜单或日常任务入口打开则自动接入。`OASX-tray.exe --restore` 可恢复已经隐藏的窗口。日志写入工作区 `logs/oasx_tray.log`。

2026-10-06 验证：编译成功；现有窗口最小化后不可见且进程仍运行；恢复后窗口可见；重复恢复后托盘宿主仍只有一个。原生 C++ 实现尚未编译验证。

2026-10-08 验证：C# 辅助程序重新编译成功。Flutter 3.27.1 的 Windows 完整构建使用 Visual Studio 16 2019 生成器，未找到对应实例，因此原生 C++ 托盘仍未完成构建验证；本次界面更新使用独立 AOT 与资源构建。
