# Windows 托盘最小化

2026-10-12 更新：全局设置在“开机启动”下增加“启动后运行”，可选“不运行”及后端当前任务方案。设置保存为 `HKCU\Software\OASX\StartupProfile`，默认不运行。新增方案重新进入设置页或点击刷新即可选择。每次打开 OASX 并连接后端后自动运行一次所选方案；恢复已有窗口不会再次触发。自动运行前通过 WebSocket 确认状态，已运行的方案跳过；方案被删除时跳过并提示重新选择。选择立即保存，下次启动生效。未执行真实 Windows 注销/重启测试。

`windows/runner/flutter_window.cpp` 实现原生托盘：最小化时隐藏窗口，左键恢复，右键显示窗口或退出，并处理 Explorer 重启时重建图标。

2026-10-10 更新：原生 `oasx.exe` 启动时先执行同目录的 `Ensure-OAS-Backend.ps1`，自动启动或复用 OAS 后端，并等待 `http://127.0.0.1:22288/home/test` 就绪后再显示界面。直接启动、开机快捷方式、重复打开已有窗口均经过此入口；重复打开也会补起已停止的后端。桌面菜单和日常任务脚本共用该启动器，通过互斥锁避免并发重复启动，日志写入安装根目录 `logs/oasx_backend_startup.log`。构建和部署时必须同时保留启动器文件；启动失败会显示错误提示。打开前端仍不自动运行任务配置。

本机验证：新程序从 System32 冷启动后自动启动后端并建立前端连接；保留前端、停止后端后重复打开，成功补起后端且前端仍为原 PID；已运行的后端会被复用。真实注销登录尚未验证。

2026-10-09 更新：右上角关闭按钮（包括 Alt+F4）改为收起到托盘，托盘右键“退出”直接销毁窗口，避免重新触发关闭转最小化逻辑。开机启动改为当前用户 Startup 目录的 `OASX.lnk`，显式设置目标和工作目录；已开启的旧 Run 项在启动后自动迁移并移除。原生入口同时固定工作目录并使用绝对 Flutter data 路径。已验证从 System32 启动、启动快捷方式启动，以及实际点击关闭按钮后进程保留、窗口隐藏。尚未进行真实注销登录/重启测试；以下 Run 注册方式为历史说明。

2026-10-08 原生版本已构建并替换本机安装版本。`oasx.exe --minimize` 启动到托盘；重复启动（包括 `--restore`）恢复已有窗口，不创建第二个实例。安装目录的 `native-tray.enabled` 标记使启动脚本跳过旧辅助程序。已实测静默启动、系统菜单最小化、重复启动恢复、关闭前端后后端仍监听；托盘鼠标菜单及 Explorer 重启恢复尚未直接操作验证。

Flutter 3.27.1 不认识 Visual Studio 18，完整构建需通过 CMake 显式选择 `Visual Studio 18 2026`，无需修改 Flutter SDK。中文目录需先映射 ASCII 路径（本机 `Q:`），并确保 `windows/flutter/ephemeral/generated_config.cmake` 中 Flutter 和项目路径也使用该映射。已验证命令：

```powershell
# 在 Q:\OASX-source 中执行，CMake 使用 VS Build Tools 安装目录内的版本。
cmake -S windows -B build/native-tray -G 'Visual Studio 18 2026' -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
cmake --build build/native-tray --config Release --target INSTALL --parallel 4
# Dart 文件修改后可显式重建 AOT；该输出与 CMake 默认 build/windows 路径不同。
..\.build-tools\flutter\bin\flutter.bat assemble --output=build/native-tray -dTargetPlatform=windows-x64 -dTargetFile=lib/main.dart -dBuildMode=release -dTrackWidgetCreation=false -dTreeShakeIcons=true release_bundle_windows-x64_assets
```

完整程序在 `build/native-tray/runner/Release`；显式 assemble 后还需将 `build/native-tray/windows/app.so` 和 `build/native-tray/flutter_assets` 复制到安装包的 `data` 下。

以下为旧辅助方案的历史记录，保留用于回退。

首页侧栏的“全局设置”提供“开机启动”和“最小化启动”。前者注册当前用户 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 中的 `OASX` 值，只打开前端；后者保存到 `HKCU\Software\OASX\StartMinimized`。设置保存后优先于旧入口的最小化参数；`--restore` 始终显式显示窗口。未保存设置时保留原参数行为。原生接口使用 `oasx/startup` MethodChannel，不需要管理员权限。

已验证原生接口底层的开关读写、登录启动项注册和移除，并保留原值；实测新进程在最小化偏好开启时隐藏、关闭时显示（覆盖旧 `--minimize` 参数）。设置页通过静态检查，完整 Release 构建成功。因窗口自动化工具报 `foreground window did not report a process id`，未完成设置页的直接点击验证，也未执行实际 Windows 注销登录测试。

已安装的旧版 OASX 使用 `OASX-tray.exe` 辅助程序提供最小化行为。`Start-OASX.ps1` 和 `Toggle-OASX.ps1` 自动启动该程序，已有窗口也可直接接入，无需重启 OASX。辅助程序只控制前端窗口，不停止后端或自动化任务；窗口关闭后最多 30 秒自动退出。重复启动不会创建多个托盘宿主。

在工作区根目录通过系统自带编译器重新构建辅助程序：

```powershell
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll '/win32icon:OASX-source\windows\runner\resources\app_icon.ico' '/out:OASX\OASX-tray.exe' 'OASX-source\windows\tray\OasxTray.cs'
```

直接运行旧版 `oasx.exe` 时，需同时运行旁边的 `OASX-tray.exe`；从启动菜单或日常任务入口打开则自动接入。`OASX-tray.exe --restore` 可恢复已经隐藏的窗口。日志写入工作区 `logs/oasx_tray.log`。

2026-10-06 验证：编译成功；现有窗口最小化后不可见且进程仍运行；恢复后窗口可见；重复恢复后托盘宿主仍只有一个。原生 C++ 实现尚未编译验证。

2026-10-08 验证：C# 辅助程序重新编译成功。Flutter 3.27.1 的 Windows 完整构建使用 Visual Studio 16 2019 生成器，未找到对应实例，因此原生 C++ 托盘仍未完成构建验证；本次界面更新使用独立 AOT 与资源构建。

2026-10-13 更新：右上角关闭按钮和 Alt+F4 直接退出 OASX 前端；最小化继续收起到托盘。关闭前端不停止后端调度器。
