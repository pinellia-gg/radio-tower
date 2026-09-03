import 'package:menu_base/menu_base.dart';

/// Describes the Windows-only playback section at the top of the tray menu.
///
/// The supplied [playPauseItem] remains part of the Dart menu so its click can
/// be mapped back through the regular tray callback. Windows renders it as one
/// state-aware icon button instead of a text row.
class TrayMenuControls {
  const TrayMenuControls({
    required this.playPauseItem,
    required this.isPlaying,
    required this.hasStation,
    required this.statusText,
  });

  final MenuItem playPauseItem;
  final bool isPlaying;
  final bool hasStation;
  final String statusText;

  Map<String, dynamic> toJson() => {
        'playPauseItemId': playPauseItem.id,
        'playPauseIcon': playPauseItem.icon,
        'isPlaying': isPlaying,
        'hasStation': hasStation,
        'statusText': statusText,
      }..removeWhere((key, value) => value == null);
}
