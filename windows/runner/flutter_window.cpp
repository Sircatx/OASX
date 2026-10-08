#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
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
          PostMessage(hwnd, WM_CLOSE, 0, 0);
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
