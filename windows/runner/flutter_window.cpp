#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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

  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "invpro/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setLoginWindowMode") {
          SetLoginWindowMode();
          result->Success();
          return;
        }
        if (call.method_name() == "setWorkspaceWindowMode") {
          bool lock_frame = false;
          if (const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments())) {
            const auto lock_it = arguments->find(flutter::EncodableValue("lockFrame"));
            if (lock_it != arguments->end()) {
              if (const auto* lock_value = std::get_if<bool>(&lock_it->second)) {
                lock_frame = *lock_value;
              }
            }
          }
          SetWorkspaceWindowMode(lock_frame);
          result->Success();
          return;
        }
        result->NotImplemented();
      });

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
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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

void FlutterWindow::SetLoginWindowMode() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style |= WS_THICKFRAME;
  style |= WS_MAXIMIZEBOX;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  ShowWindow(hwnd, SW_RESTORE);

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const int width = 520;
  const int height = 640;
  const RECT work_area = monitor_info.rcWork;
  const int x = work_area.left + ((work_area.right - work_area.left) - width) / 2;
  const int y = work_area.top + ((work_area.bottom - work_area.top) - height) / 2;

  SetWindowPos(hwnd, nullptr, x, y, width, height,
               SWP_NOZORDER | SWP_FRAMECHANGED);
}

void FlutterWindow::SetWorkspaceWindowMode(bool lock_frame) {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  if (lock_frame) {
    style &= ~WS_THICKFRAME;
    style &= ~WS_MAXIMIZEBOX;
  } else {
    style |= WS_THICKFRAME;
    style |= WS_MAXIMIZEBOX;
  }
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ShowWindow(hwnd, SW_MAXIMIZE);
}
