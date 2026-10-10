#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "startup_settings.h"
#include <flutter/standard_method_codec.h>

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kShowWindowCommand = 1;
constexpr UINT kExitCommand = 2;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // Migrate an enabled legacy Run registration to a shortcut with a working directory.
  if (startup_settings::LaunchAtStartup()) startup_settings::SetLaunchAtStartup(true);
  startup_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "oasx/startup",
      &flutter::StandardMethodCodec::GetInstance());
  startup_channel_->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "getSettings") {
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("launchAtStartup"), flutter::EncodableValue(startup_settings::LaunchAtStartup())},
          {flutter::EncodableValue("startMinimized"), flutter::EncodableValue(startup_settings::StartMinimized())}}));
      return;
    }
    const auto* enabled = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
    if (!enabled) { result->Error("invalid_argument", "Expected a boolean"); return; }
    LSTATUS status;
    if (call.method_name() == "setLaunchAtStartup") {
      status = startup_settings::SetLaunchAtStartup(*enabled);
    } else if (call.method_name() == "setStartMinimized") {
      status = startup_settings::SetStartMinimized(*enabled);
    } else { result->NotImplemented(); return; }
    if (status != ERROR_SUCCESS) {
      result->Error("windows_error", "Unable to save startup setting", flutter::EncodableValue(static_cast<int>(status)));
    } else { result->Success(); }
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    if (start_minimized_) {
      HideToTray(GetHandle());
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  startup_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::HideToTray(HWND window) {
  if (!tray_visible_) {
    tray_icon_ = {};
    tray_icon_.cbSize = sizeof(tray_icon_);
    tray_icon_.hWnd = window;
    tray_icon_.uID = 1;
    tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    tray_icon_.uCallbackMessage = kTrayMessage;
    tray_icon_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                               MAKEINTRESOURCE(IDI_APP_ICON));
    lstrcpynW(tray_icon_.szTip, L"OASX", ARRAYSIZE(tray_icon_.szTip));
    if (!Shell_NotifyIconW(NIM_ADD, &tray_icon_)) {
      return false;
    }
    tray_visible_ = true;
  }
  ShowWindow(window, SW_HIDE);
  return true;
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_visible_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_visible_ = false;
  }
}

void FlutterWindow::RestoreFromTray(HWND window) {
  ShowWindow(window, restore_maximized_ ? SW_SHOWMAXIMIZED : SW_RESTORE);
  SetForegroundWindow(window);
  RemoveTrayIcon();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Handle tray messages before plugins can consume minimize notifications.
  if (message == WM_CLOSE ||
      (message == WM_SYSCOMMAND && (wparam & 0xfff0) == SC_CLOSE)) {
    restore_maximized_ = IsZoomed(hwnd) != FALSE;
    HideToTray(hwnd);
    return 0;
  }
  if (restore_message_ != 0 && message == restore_message_) {
    RestoreFromTray(hwnd);
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_ && tray_visible_) {
    tray_visible_ = false;
    if (!HideToTray(hwnd)) {
      RestoreFromTray(hwnd);
    }
    return 0;
  }
  if (message == WM_SYSCOMMAND && (wparam & 0xfff0) == SC_MINIMIZE) {
    restore_maximized_ = IsZoomed(hwnd) != FALSE;
    if (HideToTray(hwnd)) {
      return 0;
    }
  }
  if (message == WM_SIZE && wparam == SIZE_MINIMIZED) {
    WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
    if (GetWindowPlacement(hwnd, &placement)) {
      restore_maximized_ = (placement.flags & WPF_RESTORETOMAXIMIZED) != 0;
    }
    if (HideToTray(hwnd)) {
      return 0;
    }
  }
  if (message == kTrayMessage) {
    if (lparam == WM_LBUTTONUP) {
      RestoreFromTray(hwnd);
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      POINT cursor;
      GetCursorPos(&cursor);
      HMENU menu = CreatePopupMenu();
      if (menu) {
        AppendMenuW(menu, MF_STRING, kShowWindowCommand,
                    L"\u663e\u793a\u7a97\u53e3");
        AppendMenuW(menu, MF_STRING, kExitCommand, L"\u9000\u51fa");
        SetForegroundWindow(hwnd);
        const UINT command = TrackPopupMenu(
            menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
            cursor.x, cursor.y, 0, hwnd, nullptr);
        DestroyMenu(menu);
        PostMessage(hwnd, WM_NULL, 0, 0);
        if (command == kShowWindowCommand) {
          RestoreFromTray(hwnd);
        } else if (command == kExitCommand) {
          DestroyWindow(hwnd);
        }
      }
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
