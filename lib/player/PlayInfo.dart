import 'package:radio_tower/entity/RadioStation.dart';

typedef PlayInfo =
    ({RadioStation? radioStation, String musicInfo, bool needPlay});

PlayInfo createEmptyPlayInfo() {
  return (radioStation: null, musicInfo: "", needPlay: false);
}
