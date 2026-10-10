#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"
#include "startup_settings.h"
#include "backend_startup.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  wchar_t executable[32768];
  const DWORD executable_length = GetModuleFileNameW(nullptr, executable, ARRAYSIZE(executable));
  if (executable_length == 0 || executable_length >= ARRAYSIZE(executable)) return EXIT_FAILURE;
  std::wstring app_directory(executable, executable_length);
  app_directory = app_directory.substr(0, app_directory.find_last_of(L"\\/"));
  SetCurrentDirectoryW(app_directory.c_str());
  // This also runs on a second launch, so reopening OASX repairs a stopped backend.
  if (!EnsureOasBackend(app_directory)) {
    MessageBoxW(nullptr,
        L"OAS backend could not start. Check logs\\oasx_backend_startup.log in the installation root.",
        L"OASX startup failed", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  HANDLE instance_mutex = CreateMutexW(nullptr, FALSE, L"Local\\OASX.NativeTray");
  if (instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    // A second launch restores the existing window, including when hidden.
    for (int attempt = 0; attempt < 50; ++attempt) {
      HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"oasx");
      if (existing != nullptr) {
        PostMessageW(existing, RegisterWindowMessageW(L"OASX.RestoreWindow"), 0, 0);
        break;
      }
      Sleep(100);
    }
    CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Login launches do not inherit the installation directory as their working directory.
  flutter::DartProject project(app_directory + L"\\data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool explicit_restore = std::find(command_line_arguments.begin(),
      command_line_arguments.end(), "--restore") != command_line_arguments.end();
  const bool start_minimized = !explicit_restore && startup_settings::StartMinimized(show_command == SW_SHOWMINIMIZED ||
      show_command == SW_MINIMIZE ||
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--minimize") != command_line_arguments.end());
  if (start_minimized && std::find(command_line_arguments.begin(),
      command_line_arguments.end(), "--minimize") == command_line_arguments.end()) {
    command_line_arguments.push_back("--minimize");
  }
  if (!start_minimized) {
    command_line_arguments.erase(std::remove(command_line_arguments.begin(),
        command_line_arguments.end(), "--minimize"), command_line_arguments.end());
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartMinimized(start_minimized);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"oasx", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
