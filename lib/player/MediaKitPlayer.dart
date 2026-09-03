import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:lib_common/log/Logger.dart';

enum PlayerState { idle, playing, paused, stopped, error }

enum PlaybackErrorKind { noPlayableUrl, reconnecting }

class PlaybackError {
  const PlaybackError({required this.kind, required this.sequence});

  final PlaybackErrorKind kind;
  final int sequence;
}

class MediaKitPlayer {
  static const String _tag = "MediaKitPlayer";
  static const int _maxUnexpectedPauseRecoveries = 3;
  static const Duration _unexpectedPauseRecoveryDelay = Duration(seconds: 2);
  static const Duration _bufferingStallRecoveryDelay = Duration(seconds: 15);
  static const Duration _stablePlaybackResetDelay = Duration(seconds: 20);
  static const Duration _playbackProgressCheckInterval = Duration(seconds: 5);
  static const Duration _playbackProgressTimeout = Duration(seconds: 20);
  static const Duration _positionRollbackThreshold = Duration(seconds: 2);
  static const int _liveStreamBufferSize = 128 * 1024;

  final Player _player = Player(
    configuration: const PlayerConfiguration(
      // A live radio stream must stay close to its source. This caps the
      // demuxer cache at roughly 11 seconds for a 96 kbps stream.
      bufferSize: _liveStreamBufferSize,
    ),
  );
  String _curPlayUrl = "";
  bool _shouldKeepPlaying = false;
  bool _isReloadingMedia = false;
  bool _isBuffering = false;
  bool _isDisposed = false;
  int _playRequestId = 0;
  int _errorSequence = 0;
  int _unexpectedPauseRecoveries = 0;
  Duration? _lastPlaybackPosition;
  DateTime? _lastPlaybackProgressTime;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late final Future<void> _liveStreamConfiguration;
  Timer? _unexpectedPauseRecoveryTimer;
  Timer? _bufferingStallRecoveryTimer;
  Timer? _playbackProgressWatchdogTimer;
  Timer? _stablePlaybackResetTimer;

  final ValueNotifier<PlayerState> stateNotifier = ValueNotifier<PlayerState>(
    PlayerState.idle,
  );
  final ValueNotifier<PlaybackError?> errorNotifier =
      ValueNotifier<PlaybackError?>(null);

  PlayerState get state => stateNotifier.value;

  bool get isPlaying => state == PlayerState.playing;

  MediaKitPlayer() {
    _liveStreamConfiguration = _configureForLiveStreams();
    _initListeners();
  }

  Future<void> _configureForLiveStreams() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    // media_kit exposes the native player as PlatformPlayer. Its Windows
    // implementation supports these libmpv properties, but they are not part
    // of PlatformPlayer's common interface.
    final nativePlayer = _player.platform as dynamic;
    final properties = <String, String>{
      // Do not replay old packets when a live stream is disconnected. libmpv
      // will report the failure or stall, and our recovery flow will reopen
      // the original stream URL instead.
      'cache': 'no',
      'cache-on-disk': 'no',
    };

    for (final entry in properties.entries) {
      try {
        await nativePlayer.setProperty(entry.key, entry.value);
      } catch (error, stackTrace) {
        Logger.wLog(
          _tag,
          '设置直播缓存参数失败: ${entry.key}=${entry.value}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  void _initListeners() {
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        Logger.dLog(_tag, "播放状态变化: playing=$playing");
        if (playing) {
          stateNotifier.value = PlayerState.playing;
          _clearPlaybackError();
          _cancelUnexpectedPauseRecovery();
          _scheduleStablePlaybackReset();
          _startPlaybackProgressWatchdog();
        } else {
          _stopPlaybackProgressWatchdog();
          if (state == PlayerState.playing) {
            if (_isBuffering && _shouldKeepPlaying) {
              Logger.dLog(_tag, "播放器因缓冲暂停，等待缓冲恢复");
              return;
            }
            stateNotifier.value = PlayerState.paused;
            _scheduleUnexpectedPauseRecovery(PlayerState.paused);
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        Logger.dLog(_tag, "播放完成: completed=$completed");
        if (completed) {
          stateNotifier.value = PlayerState.stopped;
          _scheduleUnexpectedPauseRecovery(PlayerState.stopped);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((error) {
        Logger.eLog(_tag, "播放器错误: $error");
        _reportPlaybackError();
        _schedulePlaybackRecovery(reason: "播放器错误: $error", forceReload: true);
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        Logger.dLog(_tag, "缓冲状态变化: buffering=$buffering");
        _isBuffering = buffering;
        if (buffering) {
          // media_kit may report playing=false before it reports buffering.
          // Do not let that transient state trigger a competing recovery.
          _cancelUnexpectedPauseRecovery();
          _scheduleBufferingStallRecovery();
        } else {
          _cancelBufferingStallRecovery();
          if (state == PlayerState.playing) {
            _scheduleStablePlaybackReset();
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen(_onPlaybackPositionChanged),
    );

    _subscriptions.add(
      _player.stream.log.listen((log) {
        Logger.dLog(_tag, "[${log.level}] ${log.prefix} : ${log.text}");
      }),
    );
  }

  Future<void> playUrl(String url, {bool forceReload = false}) async {
    Logger.dLog(_tag, "开始播放：$url, forceReload=$forceReload");
    if (url.isEmpty) {
      Logger.wLog(_tag, "播放地址为空，忽略播放请求");
      await stop();
      _reportPlaybackError(kind: PlaybackErrorKind.noPlayableUrl);
      return;
    }

    final requestId = ++_playRequestId;
    _shouldKeepPlaying = true;
    _resetRecoveryState();
    try {
      await _playUrl(url, requestId: requestId, forceReload: forceReload);
    } catch (error, stackTrace) {
      Logger.eLog(_tag, "开始播放失败", error: error, stackTrace: stackTrace);
      _reportPlaybackError();
      _schedulePlaybackRecovery(reason: '开始播放失败', forceReload: true);
    }
  }

  Future<void> _playUrl(
    String url, {
    required int requestId,
    bool forceReload = false,
  }) async {
    await _liveStreamConfiguration;
    if (!_isCurrentPlaybackRequest(requestId)) {
      return;
    }

    if (forceReload || url != _curPlayUrl) {
      _isReloadingMedia = true;
      try {
        _resetPlaybackProgress();
        await _player.stop();
        if (!_isCurrentPlaybackRequest(requestId)) {
          return;
        }
        _curPlayUrl = url;
        await _player.open(Media(url));
      } finally {
        _isReloadingMedia = false;
      }
      return;
    }

    await _player.play();
  }

  Future<void> play() async {
    Logger.dLog(_tag, "继续播放");
    _shouldKeepPlaying = true;
    _resetRecoveryState();
    try {
      await _player.play();
    } catch (error, stackTrace) {
      Logger.eLog(_tag, "继续播放失败", error: error, stackTrace: stackTrace);
      _reportPlaybackError();
      _schedulePlaybackRecovery(reason: '继续播放失败', forceReload: true);
    }
  }

  Future<void> pause() async {
    Logger.dLog(_tag, "暂停播放");
    _playRequestId++;
    _shouldKeepPlaying = false;
    _resetRecoveryState();
    _stopPlaybackProgressWatchdog();
    await _player.pause();
  }

  Future<void> stop() async {
    Logger.dLog(_tag, "停止播放");
    _playRequestId++;
    _shouldKeepPlaying = false;
    _resetRecoveryState();
    _stopPlaybackProgressWatchdog();
    await _player.stop();
    _curPlayUrl = "";
    _isBuffering = false;
    stateNotifier.value = PlayerState.stopped;
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 100.0).toDouble());
  }

  void _reportPlaybackError({
    PlaybackErrorKind kind = PlaybackErrorKind.reconnecting,
  }) {
    errorNotifier.value = PlaybackError(kind: kind, sequence: ++_errorSequence);
    stateNotifier.value = PlayerState.error;
  }

  void _clearPlaybackError() {
    if (errorNotifier.value != null) {
      errorNotifier.value = null;
    }
  }

  bool _canRecoverPlayback() {
    if (_isDisposed || _isReloadingMedia || !_shouldKeepPlaying) {
      return false;
    }

    if (_curPlayUrl.isEmpty) {
      return false;
    }

    return true;
  }

  bool _isCurrentPlaybackRequest(int requestId) {
    return !_isDisposed && _shouldKeepPlaying && requestId == _playRequestId;
  }

  bool _shouldRecoverPlayback(PlayerState playerState) {
    if (!_canRecoverPlayback()) {
      return false;
    }

    return playerState == PlayerState.paused ||
        playerState == PlayerState.stopped;
  }

  void _scheduleUnexpectedPauseRecovery(PlayerState playerState) {
    if (!_shouldRecoverPlayback(playerState)) {
      return;
    }

    _schedulePlaybackRecovery(
      reason: "非预期播放中断: state=$playerState",
      forceReload: false,
    );
  }

  void _schedulePlaybackRecovery({
    required String reason,
    required bool forceReload,
  }) {
    if (!_canRecoverPlayback()) {
      return;
    }

    if (_unexpectedPauseRecoveryTimer?.isActive ?? false) {
      return;
    }

    if (_unexpectedPauseRecoveries >= _maxUnexpectedPauseRecoveries) {
      Logger.wLog(
        _tag,
        "播放自动恢复已达到上限，等待用户手动处理: reason=$reason, "
        "state=$state, url=$_curPlayUrl",
      );
      return;
    }

    Logger.wLog(
      _tag,
      "准备自动恢复播放: reason=$reason, "
      "attempt=${_unexpectedPauseRecoveries + 1}, "
      "forceReload=$forceReload, url=$_curPlayUrl",
    );
    _unexpectedPauseRecoveryTimer = Timer(
      _unexpectedPauseRecoveryDelay,
      () => _recoverPlayback(reason: reason, forceReload: forceReload),
    );
  }

  void _scheduleBufferingStallRecovery() {
    if (!_canRecoverPlayback()) {
      return;
    }

    if (_bufferingStallRecoveryTimer?.isActive ?? false) {
      return;
    }

    _bufferingStallRecoveryTimer = Timer(_bufferingStallRecoveryDelay, () {
      _bufferingStallRecoveryTimer = null;
      if (_isBuffering) {
        _schedulePlaybackRecovery(
          reason: "缓冲超时 ${_bufferingStallRecoveryDelay.inSeconds}s",
          forceReload: true,
        );
      }
    });
  }

  void _onPlaybackPositionChanged(Duration position) {
    if (!_shouldKeepPlaying || _isReloadingMedia || position <= Duration.zero) {
      return;
    }

    final previousPosition = _lastPlaybackPosition;
    if (previousPosition == null || position > previousPosition) {
      _lastPlaybackPosition = position;
      _lastPlaybackProgressTime = DateTime.now();
      return;
    }

    if (previousPosition - position >= _positionRollbackThreshold) {
      Logger.wLog(
        _tag,
        '检测到直播播放位置回退: '
        '${previousPosition.inMilliseconds}ms -> ${position.inMilliseconds}ms',
      );
      _resetPlaybackProgress();
      _schedulePlaybackRecovery(reason: '直播播放位置回退', forceReload: true);
    }
  }

  void _startPlaybackProgressWatchdog() {
    if (_playbackProgressWatchdogTimer?.isActive ?? false) {
      return;
    }

    _playbackProgressWatchdogTimer = Timer.periodic(
      _playbackProgressCheckInterval,
      (_) => _checkPlaybackProgress(),
    );
  }

  void _checkPlaybackProgress() {
    if (!_canRecoverPlayback() ||
        state != PlayerState.playing ||
        _isBuffering) {
      return;
    }

    final lastProgressTime = _lastPlaybackProgressTime;
    if (lastProgressTime == null ||
        DateTime.now().difference(lastProgressTime) <
            _playbackProgressTimeout) {
      return;
    }

    Logger.wLog(
      _tag,
      '直播播放位置已 ${_playbackProgressTimeout.inSeconds}s 未前进，重新连接流',
    );
    _resetPlaybackProgress();
    _schedulePlaybackRecovery(reason: '直播播放位置停滞', forceReload: true);
  }

  void _resetPlaybackProgress() {
    _lastPlaybackPosition = null;
    _lastPlaybackProgressTime = null;
  }

  void _stopPlaybackProgressWatchdog() {
    _playbackProgressWatchdogTimer?.cancel();
    _playbackProgressWatchdogTimer = null;
    _resetPlaybackProgress();
  }

  Future<void> _recoverPlayback({
    required String reason,
    required bool forceReload,
  }) async {
    _unexpectedPauseRecoveryTimer = null;
    if (!_canRecoverPlayback()) {
      return;
    }

    _unexpectedPauseRecoveries++;
    final shouldForceReload = forceReload || _unexpectedPauseRecoveries > 1;
    Logger.wLog(
      _tag,
      "自动恢复播放: reason=$reason, state=$state, "
      "attempt=$_unexpectedPauseRecoveries, "
      "forceReload=$shouldForceReload, url=$_curPlayUrl",
    );

    try {
      await _playUrl(
        _curPlayUrl,
        requestId: _playRequestId,
        forceReload: shouldForceReload,
      );
    } catch (e, stackTrace) {
      Logger.eLog(_tag, "自动恢复播放失败", error: e, stackTrace: stackTrace);
      _reportPlaybackError();
      _schedulePlaybackRecovery(reason: reason, forceReload: true);
    }
  }

  void _resetRecoveryState() {
    _unexpectedPauseRecoveries = 0;
    _cancelUnexpectedPauseRecovery();
    _cancelBufferingStallRecovery();
    _stablePlaybackResetTimer?.cancel();
    _stablePlaybackResetTimer = null;
  }

  void _cancelUnexpectedPauseRecovery() {
    _unexpectedPauseRecoveryTimer?.cancel();
    _unexpectedPauseRecoveryTimer = null;
  }

  void _cancelBufferingStallRecovery() {
    _bufferingStallRecoveryTimer?.cancel();
    _bufferingStallRecoveryTimer = null;
  }

  void _scheduleStablePlaybackReset() {
    _stablePlaybackResetTimer?.cancel();
    _stablePlaybackResetTimer = Timer(_stablePlaybackResetDelay, () {
      _unexpectedPauseRecoveries = 0;
    });
  }

  void dispose() {
    _isDisposed = true;
    _playRequestId++;
    _resetRecoveryState();
    _stopPlaybackProgressWatchdog();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    stateNotifier.dispose();
    errorNotifier.dispose();
    _player.dispose();
  }
}
