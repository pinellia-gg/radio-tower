#include "flutter_window.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <optional>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kMediaKeyEventChannel[] = "radio_tower/windows_media_keys";
constexpr char kMediaKeyControlChannel[] =
    "radio_tower/windows_media_keys_control";

constexpr int kHotKeyPlayPause = 0x5201;
// constexpr int kHotKeyVolumeMute = 0x5202;
// constexpr int kHotKeyVolumeDown = 0x5203;
// constexpr int kHotKeyVolumeUp = 0x5204;

constexpr UINT kHotKeyModifiers =
#ifdef MOD_NOREPEAT
    MOD_NOREPEAT;
#else
    0;
#endif

const char* ActionForHotKey(WPARAM const hot_key_id) {
  switch (hot_key_id) {
    case kHotKeyPlayPause:
      return "playPause";
    // case kHotKeyVolumeMute:
    //   return "volumeMute";
    // case kHotKeyVolumeDown:
    //   return "volumeDown";
    // case kHotKeyVolumeUp:
    //   return "volumeUp";
    default:
      return nullptr;
  }
}

const char* ActionForAppCommand(int const command) {
  switch (command) {
    case APPCOMMAND_MEDIA_PLAY_PAUSE:
      return "playPause";
    case APPCOMMAND_MEDIA_PLAY:
      return "play";
    case APPCOMMAND_MEDIA_PAUSE:
      return "pause";
    // case APPCOMMAND_VOLUME_MUTE:
    //   return "volumeMute";
    // case APPCOMMAND_VOLUME_DOWN:
    //   return "volumeDown";
    // case APPCOMMAND_VOLUME_UP:
    //   return "volumeUp";
    default:
      return nullptr;
  }
}

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
  ConfigureMediaKeyEventChannel();
  ConfigureMediaKeyControlChannel();
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
  UnregisterMediaHotKeys();
  media_key_event_sink_.reset();
  media_key_event_channel_.reset();
  media_key_control_channel_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_HOTKEY: {
      if (!media_keys_enabled_) {
        break;
      }
      const char* action = ActionForHotKey(wparam);
      if (action != nullptr) {
        SendMediaKeyEvent(action);
        return 0;
      }
      break;
    }
    case WM_APPCOMMAND:
      if (media_keys_enabled_ && HandleAppCommand(lparam)) {
        return TRUE;
      }
      break;
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

void FlutterWindow::ConfigureMediaKeyEventChannel() {
  media_key_event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaKeyEventChannel,
          &flutter::StandardMethodCodec::GetInstance());

  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                 events)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        media_key_event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
          -> std::unique_ptr<
              flutter::StreamHandlerError<flutter::EncodableValue>> {
        media_key_event_sink_.reset();
        return nullptr;
      });

  media_key_event_channel_->SetStreamHandler(std::move(handler));
}

void FlutterWindow::ConfigureMediaKeyControlChannel() {
  media_key_control_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kMediaKeyControlChannel,
          &flutter::StandardMethodCodec::GetInstance());

  media_key_control_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setGlobalMediaKeysEnabled") {
          result->NotImplemented();
          return;
        }

        const auto* enabled = std::get_if<bool>(call.arguments());
        if (enabled == nullptr) {
          result->Error("bad_args", "Expected a boolean enabled value.");
          return;
        }

        SetGlobalMediaKeysEnabled(*enabled);
        result->Success(flutter::EncodableValue(media_keys_enabled_));
      });
}

void FlutterWindow::SetGlobalMediaKeysEnabled(bool enabled) {
  media_keys_enabled_ = enabled;
  if (enabled) {
    RegisterMediaHotKeys();
  } else {
    UnregisterMediaHotKeys();
  }
}

void FlutterWindow::RegisterMediaHotKeys() {
  if (media_hot_keys_registered_) {
    return;
  }

  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    media_hot_keys_registered_ = false;
    return;
  }

  RegisterHotKey(hwnd, kHotKeyPlayPause, kHotKeyModifiers,
                 VK_MEDIA_PLAY_PAUSE);
  // RegisterHotKey(hwnd, kHotKeyVolumeMute, kHotKeyModifiers, VK_VOLUME_MUTE);
  // RegisterHotKey(hwnd, kHotKeyVolumeDown, kHotKeyModifiers, VK_VOLUME_DOWN);
  // RegisterHotKey(hwnd, kHotKeyVolumeUp, kHotKeyModifiers, VK_VOLUME_UP);
  media_hot_keys_registered_ = true;
}

void FlutterWindow::UnregisterMediaHotKeys() {
  if (!media_hot_keys_registered_) {
    return;
  }

  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    media_hot_keys_registered_ = false;
    return;
  }

  UnregisterHotKey(hwnd, kHotKeyPlayPause);
  // UnregisterHotKey(hwnd, kHotKeyVolumeMute);
  // UnregisterHotKey(hwnd, kHotKeyVolumeDown);
  // UnregisterHotKey(hwnd, kHotKeyVolumeUp);
  media_hot_keys_registered_ = false;
}

bool FlutterWindow::HandleAppCommand(LPARAM const lparam) {
  const char* action = ActionForAppCommand(GET_APPCOMMAND_LPARAM(lparam));
  if (action == nullptr) {
    return false;
  }

  SendMediaKeyEvent(action);
  return true;
}

void FlutterWindow::SendMediaKeyEvent(const char* action) {
  if (action == nullptr || media_key_event_sink_ == nullptr) {
    return;
  }

  DWORD const now = GetTickCount();
  if (last_media_key_action_ == action && now - last_media_key_tick_ < 120) {
    return;
  }

  last_media_key_action_ = action;
  last_media_key_tick_ = now;
  media_key_event_sink_->Success(flutter::EncodableValue(action));
}
