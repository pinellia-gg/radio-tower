import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lib_common/log/Logger.dart';

enum WindowsMediaKeyCommand {
  playPause,
  play,
  pause,
  volumeUp,
  volumeDown,
  volumeMute,
}

class WindowsMediaKeyService {
  static const String _tag = "WindowsMediaKeyService";
  static const EventChannel _eventChannel = EventChannel(
    "radio_tower/windows_media_keys",
  );
  static const MethodChannel _methodChannel = MethodChannel(
    "radio_tower/windows_media_keys_control",
  );
  static final StreamController<WindowsMediaKeyCommand> _commandController =
      StreamController<WindowsMediaKeyCommand>.broadcast();
  static StreamSubscription<dynamic>? _nativeCommandSubscription;

  static Future<void> setGlobalMediaKeysEnabled(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    try {
      await _methodChannel.invokeMethod("setGlobalMediaKeysEnabled", enabled);
    } on PlatformException catch (e, stackTrace) {
      Logger.eLog(
        _tag,
        "设置 Windows 全局媒体键失败: ${e.message ?? e.code}\n$stackTrace",
      );
    }
  }

  static StreamSubscription<WindowsMediaKeyCommand>? listen(
    void Function(WindowsMediaKeyCommand command) onCommand,
  ) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return null;
    }

    _ensureNativeCommandListener();
    return _commandController.stream.listen(onCommand);
  }

  /// Sends a command raised by an in-app Windows integration, such as the
  /// tray menu or taskbar thumbnail toolbar, through the same path as a
  /// physical media key.
  static void dispatch(WindowsMediaKeyCommand command) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    _commandController.add(command);
  }

  static void _ensureNativeCommandListener() {
    if (_nativeCommandSubscription != null) {
      return;
    }

    _nativeCommandSubscription = _eventChannel
        .receiveBroadcastStream()
        .map(_parseCommand)
        .where((command) => command != null)
        .cast<WindowsMediaKeyCommand>()
        .listen(
          dispatch,
          onError: (Object error, StackTrace stackTrace) {
            Logger.eLog(_tag, "监听 Windows 媒体键失败: $error\n$stackTrace");
          },
        );
  }

  static WindowsMediaKeyCommand? _parseCommand(dynamic event) {
    if (event is! String) {
      return null;
    }

    switch (event) {
      case "playPause":
        return WindowsMediaKeyCommand.playPause;
      case "play":
        return WindowsMediaKeyCommand.play;
      case "pause":
        return WindowsMediaKeyCommand.pause;
      // case "volumeUp":
      //   return WindowsMediaKeyCommand.volumeUp;
      // case "volumeDown":
      //   return WindowsMediaKeyCommand.volumeDown;
      // case "volumeMute":
      //   return WindowsMediaKeyCommand.volumeMute;
      default:
        return null;
    }
  }
}
