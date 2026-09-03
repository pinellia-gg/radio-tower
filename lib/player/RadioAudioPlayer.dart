import 'package:lib_common/log/Logger.dart';
import 'package:audioplayers/audioplayers.dart';

class RadioAudioPlayer {
  static const String _tag = "Player";

  static final RadioAudioPlayer _instance = RadioAudioPlayer._internal();

  final _audioPlayer = AudioPlayer();

  RadioAudioPlayer._internal();

  String _curPlayUrl = "";

  init() {
    _audioPlayer.onLog.listen(
      (String msg) => Logger.dLog(_tag, "audioPlayer: $msg"),
      onError:
          (Object e, [StackTrace? stacktrace]) => Logger.eLog(
            _tag,
            "audio"
            "Player error: $e \n $stacktrace",
          ),
    );
  }

  factory RadioAudioPlayer() {
    return _instance;
  }

  void playUrl(String url) async {
    Logger.dLog(_tag, "开始播放：$url");

    if (url != _curPlayUrl) {
      pause();
    }

    _curPlayUrl = url;
    await _audioPlayer.setSourceUrl(url);

    await _audioPlayer.resume();
  }

  void pause() async {
    await _audioPlayer.pause();
  }

  void stop() async {
    await _audioPlayer.stop();
  }
}
