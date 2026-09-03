#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void ConfigureMediaKeyEventChannel();
  void ConfigureMediaKeyControlChannel();
  void SetGlobalMediaKeysEnabled(bool enabled);
  void RegisterMediaHotKeys();
  void UnregisterMediaHotKeys();
  bool HandleAppCommand(LPARAM const lparam);
  void SendMediaKeyEvent(const char* action);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      media_key_event_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      media_key_control_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
      media_key_event_sink_;
  std::string last_media_key_action_;
  DWORD last_media_key_tick_ = 0;
  bool media_keys_enabled_ = false;
  bool media_hot_keys_registered_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
