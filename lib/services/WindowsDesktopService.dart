import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lib_common/log/Logger.dart';
import 'package:path/path.dart' as path;
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/player/WindowsMediaKeyService.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

/// Owns the Windows shell integrations. Playback commands are published to
/// [WindowsMediaKeyService] so the desktop shell never depends on a widget.
class WindowsDesktopService with TrayListener, WindowListener {
  WindowsDesktopService._();

  static const String _tag = 'WindowsDesktopService';
  static final WindowsDesktopService instance = WindowsDesktopService._();

  bool _initialized = false;
  bool _isExiting = false;
  AppLocalizations? _localizations;
  RadioStation? _station;
  String _taskbarTooltip = '';
  String _trayStatus = '';
  bool _isPlaying = false;
  bool _hasStation = false;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> initialize(AppLocalizations localizations) async {
    _localizations = localizations;
    if (!_isWindows) {
      return;
    }
    if (_initialized) {
      await updateLocalizations(localizations);
      return;
    }
    _initialized = true;
    _taskbarTooltip = localizations.appTitle;
    _trayStatus = localizations.noStationPlaying;

    try {
      trayManager.addListener(this);
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      await trayManager.setIcon('assets/images/radio_tower.ico');
      await trayManager.setToolTip(localizations.appTitle);
      await _setTrayMenu();
    } catch (error, stackTrace) {
      Logger.eLog(_tag, '初始化系统托盘失败', error: error, stackTrace: stackTrace);
    }

    await _configureTaskbarControls();
  }

  Future<void> updateLocalizations(AppLocalizations localizations) async {
    _localizations = localizations;
    if (!_isWindows || !_initialized) {
      return;
    }
    await updateNowPlaying(_station, isPlaying: _isPlaying);
  }

  AppLocalizations get _l10n => _localizations!;

  String _menuIconPath(String assetPath) => path.join(
    path.dirname(Platform.resolvedExecutable),
    'data',
    'flutter_assets',
    assetPath,
  );

  Future<void> _setTrayMenu() async {
    final playPauseItem = MenuItem(
      key: 'play_pause',
      label: _isPlaying ? _l10n.pausePlayback : _l10n.play,
      icon: _menuIconPath(
        _isPlaying
            ? 'assets/images/taskbar_pause.ico'
            : 'assets/images/taskbar_play.ico',
      ),
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          playPauseItem,
          MenuItem(key: 'show_window', label: _l10n.openApp),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: _l10n.exitApp),
        ],
      ),
      controls: TrayMenuControls(
        playPauseItem: playPauseItem,
        isPlaying: _isPlaying,
        hasStation: _hasStation,
        statusText: _trayStatus,
      ),
    );
  }

  Future<void> _configureTaskbarControls() async {
    if (!_isWindows || _isExiting) {
      return;
    }

    try {
      await _setTaskbarPlaybackButton();
      await WindowsTaskbar.setThumbnailTooltip(_taskbarTooltip);
    } catch (error, stackTrace) {
      Logger.eLog(_tag, '注册任务栏缩略图控制失败', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> updateNowPlaying(
    RadioStation? station, {
    required bool isPlaying,
  }) async {
    if (!_isWindows || !_initialized) {
      return;
    }

    _station = station;
    final stationName = station?.name.trim();
    final hasStation = stationName != null && stationName.isNotEmpty;
    _hasStation = hasStation;
    _isPlaying = hasStation && isPlaying;
    final displayName = hasStation ? _truncateStationName(stationName!) : null;
    final localizedStationName = displayName ?? '';
    final statusText =
        hasStation
            ? (isPlaying
                ? _l10n.playingStation(localizedStationName)
                : _l10n.pausedStation(localizedStationName))
            : _l10n.appTitle;
    _taskbarTooltip = statusText;
    _trayStatus = hasStation ? localizedStationName : _l10n.noStationPlaying;

    try {
      await trayManager.setToolTip(statusText);
      await _setTrayMenu();
      await _setTaskbarPlaybackButton();
      await WindowsTaskbar.setThumbnailTooltip(statusText);
    } catch (error, stackTrace) {
      Logger.wLog(
        _tag,
        '更新 Windows 播放状态显示失败',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onWindowMinimize() {
    unawaited(_hideToTray());
  }

  @override
  void onWindowClose() {
    if (!_isExiting) {
      unawaited(_hideToTray());
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show_window':
        unawaited(_showWindow());
        break;
      case 'play_pause':
        WindowsMediaKeyService.dispatch(_playbackCommand);
        break;
      case 'exit_app':
        unawaited(_exitApp());
        break;
    }
  }

  Future<void> _showWindow() async {
    if (!_isWindows) {
      return;
    }
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideToTray() async {
    if (!_isWindows || _isExiting) {
      return;
    }
    await windowManager.hide();
  }

  Future<void> _exitApp() async {
    _isExiting = true;
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.destroy();
  }

  String _truncateStationName(String stationName) {
    const maximumLength = 32;
    final characters = stationName.runes.toList();
    if (characters.length <= maximumLength) {
      return stationName;
    }
    return '${String.fromCharCodes(characters.take(maximumLength - 1))}…';
  }

  Future<void> _setTaskbarPlaybackButton() {
    final isPlaying = _isPlaying;
    return WindowsTaskbar.setThumbnailToolbar([
      ThumbnailToolbarButton(
        ThumbnailToolbarAssetIcon(
          isPlaying
              ? 'assets/images/taskbar_pause.ico'
              : 'assets/images/taskbar_play.ico',
        ),
        isPlaying ? _l10n.pausePlayback : _l10n.play,
        () => WindowsMediaKeyService.dispatch(_playbackCommand),
      ),
    ]);
  }

  WindowsMediaKeyCommand get _playbackCommand =>
      _isPlaying ? WindowsMediaKeyCommand.pause : WindowsMediaKeyCommand.play;
}
