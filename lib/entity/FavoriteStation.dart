import 'package:objectbox/objectbox.dart';

import 'RadioStation.dart';

@Entity()
class FavoriteStation {
  @Id()
  int id = 0;

  @Index()
  int listId = 0;

  @Index()
  String stationuuid = "";

  int createdAt = 0;
  int updatedAt = 0;

  final station = ToOne<RadioStation>();

  FavoriteStation();

  factory FavoriteStation.fromRadioStation(int listId, RadioStation station) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return FavoriteStation()
      ..listId = listId
      ..stationuuid = station.stationuuid
      ..createdAt = now
      ..updatedAt = now
      ..station.targetId = station.ID;
  }

  void updateFromStation(RadioStation station) {
    final now = DateTime.now().millisecondsSinceEpoch;
    createdAt = createdAt == 0 ? now : createdAt;
    updatedAt = now;
    stationuuid = station.stationuuid;
    this.station.targetId = station.ID;
  }
}
