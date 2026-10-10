#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <windows.h>
#include <shellapi.h>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();
  void SetStartMinimized(bool value) { start_minimized_ = value; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  bool HideToTray(HWND window);
  void RestoreFromTray(HWND window);
  void RemoveTrayIcon();
  NOTIFYICONDATAW tray_icon_{};
  bool tray_visible_ = false;
  bool restore_maximized_ = false;
  bool start_minimized_ = false;
  const UINT restore_message_ = RegisterWindowMessageW(L"OASX.RestoreWindow");
  const UINT taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> startup_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
