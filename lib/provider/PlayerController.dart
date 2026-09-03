import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lib_common/log/Logger.dart';
import 'package:radio_tower/common/extensions/StringEx.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/manger/ConfigKeys.dart';
import 'package:radio_tower/manger/ConfigMgr.dart';
import 'package:radio_tower/player/MediaKitPlayer.dart';
import 'package:radio_tower/player/PlayInfo.dart';
import 'package:radio_tower/player/WindowsMediaKeyService.dart';

/// Application-wide playback state and commands.
///
/// Platform controls, playback history, notifications and widgets use this
/// controller instead of depending on the playback bar's lifecycle.
class PlayerController extends ChangeNotifier {
  PlayerController() {
    _mediaKitPlayer.stateNotifier.addListener(_onPlayerStateChanged);
    _mediaKitPlayer.errorNotifier.addListener(_onPlayerError);
    playInfoNotifier.addListener(_onPlayInfoChanged);
    _mediaKeySubscription = WindowsMediaKeyService.listen(_onMediaKeyCommand);
  }

  final MediaKitPlayer _mediaKitPlayer = MediaKitPlayer();
  final ValueNotifier<PlayInfo> playInfoNotifier = ValueNotifier(
    createEmptyPlayInfo(),
  );
  StreamSubscription<WindowsMediaKeyCommand>? _mediaKeySubscription;

  bool _initialized = false;
  bool _disposed = false;
  double _currentVolume = 100.0;
  double _lastAudibleVolume = 100.0;
  bool _isMuted = false;
  Future<void> _volumeOperation = Future<void>.value();

  RadioStation? get station => playInfoNotifier.value.radioStation;
  String get musicInfo => playInfoNotifier.value.musicInfo;
  bool get shouldPlay => playInfoNotifier.value.needPlay;
  PlayerState get playerState => _mediaKitPlayer.state;
  bool get isPlaying => _mediaKitPlayer.isPlaying;
  PlaybackError? get playbackError => _mediaKitPlayer.errorNotifier.value;
  double get currentVolume => _currentVolume;
  bool get isMuted => _isMuted;

  /// Must run after [ConfigMgr.init] so saved volume and the restored station
  /// are available before any page renders the playback state.
  void initialize(PlayInfo initialPlayInfo) {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    _restoreVolumeSettings();
    unawaited(_applyVolume());
    playInfoNotifier.value = initialPlayInfo;
  }

  void selectStation(RadioStation station, {String musicInfo = ''}) {
    if (_disposed) {
      return;
    }
    _setPlayInfo((radioStation: station, musicInfo: musicInfo, needPlay: true));
  }

  void requestPlayback(bool needPlay, {bool forceReload = false}) {
    if (_disposed) {
      return;
    }
    final currentPlayInfo = playInfoNotifier.value;
    final selectedStation = currentPlayInfo.radioStation;
    if (needPlay && selectedStation == null) {
      return;
    }

    final nextPlayInfo = (
      radioStation: selectedStation,
      musicInfo: currentPlayInfo.musicInfo,
      needPlay: needPlay,
    );
    if (currentPlayInfo != nextPlayInfo) {
      _setPlayInfo(nextPlayInfo);
      return;
    }

    unawaited(_applyPlaybackRequest(needPlay, forceReload: forceReload));
  }

  void togglePlayPause() {
    requestPlayback(!shouldPlay);
  }

  void setVolume(double volume, {bool? muted}) {
    if (_disposed) {
      return;
    }
    final nextVolume = volume.clamp(0.0, 100.0).toDouble();
    final nextMuted = muted ?? nextVolume == 0;
    final changed =
        nextVolume != _currentVolume ||
        nextMuted != _isMuted ||
        (nextVolume > 0 && nextVolume != _lastAudibleVolume);

    _currentVolume = nextVolume;
    _isMuted = nextMuted;
    if (nextVolume > 0) {
      _lastAudibleVolume = nextVolume;
    }

    unawaited(_applyVolume());
    _saveVolumeSettings();
    if (changed) {
      notifyListeners();
    }
  }

  void toggleMute() {
    if (_isMuted || _currentVolume == 0) {
      setVolume(_lastAudibleVolume, muted: false);
      return;
    }
    setVolume(_currentVolume, muted: true);
  }

  void _setPlayInfo(PlayInfo nextPlayInfo) {
    playInfoNotifier.value = nextPlayInfo;
  }

  void _onPlayInfoChanged() {
    if (_disposed) {
      return;
    }
    unawaited(_applyPlaybackRequest(shouldPlay));
    notifyListeners();
  }

  void _onPlayerStateChanged() {
    notifyListeners();
  }

  void _onPlayerError() {
    notifyListeners();
  }

  Future<void> _applyPlaybackRequest(
    bool needPlay, {
    bool forceReload = false,
  }) async {
    if (_disposed) {
      return;
    }
    try {
      if (needPlay) {
        await _mediaKitPlayer.playUrl(
          _resolveStationPlayUrl(station),
          forceReload: forceReload,
        );
        return;
      }
      await _mediaKitPlayer.stop();
    } catch (error, stackTrace) {
      if (!_disposed) {
        Logger.eLog(
          'PlayerController',
          '执行播放命令失败',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  String _resolveStationPlayUrl(RadioStation? radioStation) {
    final resolvedUrl = radioStation?.url_resolved.orEmpty() ?? '';
    if (resolvedUrl.isNotEmpty) {
      return resolvedUrl;
    }
    return radioStation?.url.orEmpty() ?? '';
  }

  Future<void> _applyVolume() {
    final targetVolume = _isMuted ? 0.0 : _currentVolume;
    _volumeOperation = _volumeOperation.then((_) async {
      if (_disposed) {
        return;
      }
      try {
        await _mediaKitPlayer.setVolume(targetVolume);
      } catch (error, stackTrace) {
        if (!_disposed) {
          Logger.eLog(
            'PlayerController',
            '设置音量失败',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    });
    return _volumeOperation;
  }

  void _restoreVolumeSettings() {
    final savedVolume =
        ConfigMgr()
            .getDoubleVal(ConfigKeys.KEY_PLAYER_VOLUME, _currentVolume)
            .clamp(0.0, 100.0)
            .toDouble();
    final savedLastAudibleVolume =
        ConfigMgr()
            .getDoubleVal(
              ConfigKeys.KEY_PLAYER_LAST_AUDIBLE_VOLUME,
              savedVolume > 0 ? savedVolume : _lastAudibleVolume,
            )
            .clamp(0.0, 100.0)
            .toDouble();

    _currentVolume = savedVolume;
    _isMuted = ConfigMgr().getBoolVal(ConfigKeys.KEY_PLAYER_MUTED, _isMuted);
    if (savedVolume > 0) {
      _lastAudibleVolume = savedVolume;
    } else if (savedLastAudibleVolume > 0) {
      _lastAudibleVolume = savedLastAudibleVolume;
    }
  }

  void _saveVolumeSettings() {
    ConfigMgr()
        .put(ConfigKeys.KEY_PLAYER_VOLUME, _currentVolume)
        .put(ConfigKeys.KEY_PLAYER_MUTED, _isMuted)
        .put(ConfigKeys.KEY_PLAYER_LAST_AUDIBLE_VOLUME, _lastAudibleVolume)
        .saveSync();
  }

  void _onMediaKeyCommand(WindowsMediaKeyCommand command) {
    if (_disposed) {
      return;
    }
    switch (command) {
      case WindowsMediaKeyCommand.playPause:
        togglePlayPause();
        break;
      case WindowsMediaKeyCommand.play:
        requestPlayback(true);
        break;
      case WindowsMediaKeyCommand.pause:
        requestPlayback(false);
        break;
      case WindowsMediaKeyCommand.volumeUp:
      case WindowsMediaKeyCommand.volumeDown:
      case WindowsMediaKeyCommand.volumeMute:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _mediaKeySubscription?.cancel();
    playInfoNotifier.removeListener(_onPlayInfoChanged);
    _mediaKitPlayer.stateNotifier.removeListener(_onPlayerStateChanged);
    _mediaKitPlayer.errorNotifier.removeListener(_onPlayerError);
    playInfoNotifier.dispose();
    _mediaKitPlayer.dispose();
    super.dispose();
  }
}
