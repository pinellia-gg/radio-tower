import 'package:radio_tower/database/ObjectBox.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/entity/RecentPlay.dart';
import 'package:radio_tower/objectbox.g.dart';

class RecentPlayDb {
  RecentPlayDb._create();

  static final RecentPlayDb _instance = RecentPlayDb._create();

  factory RecentPlayDb() => _instance;

  Future<void> recordStation(RadioStation station) async {
    if (station.stationuuid.isEmpty) {
      return;
    }

    final objectBox = await ObjectBox.createAsync();
    final stationBox = objectBox.store.box<RadioStation>();
    final recentPlayBox = objectBox.store.box<RecentPlay>();

    objectBox.store.runInTransaction(TxMode.write, () {
      final storedStation = _findStation(stationBox, station);
      if (storedStation == null) {
        return;
      }

      final query =
          recentPlayBox
              .query(RecentPlay_.stationuuid.equals(storedStation.stationuuid))
              .build();
      try {
        final records = query.find();
        final recentPlay =
            records.isEmpty ? RecentPlay() : records.removeAt(0);
        if (records.isNotEmpty) {
          recentPlayBox.removeMany(records.map((record) => record.id).toList());
        }
        recentPlay
          ..stationuuid = storedStation.stationuuid
          ..playedAt = DateTime.now().millisecondsSinceEpoch
          ..station.targetId = storedStation.ID;
        recentPlayBox.put(recentPlay);
      } finally {
        query.close();
      }
    });
  }

  Future<List<RadioStation>> getStations({int limit = 100}) async {
    final objectBox = await ObjectBox.createAsync();
    final recentPlayBox = objectBox.store.box<RecentPlay>();
    final stationBox = objectBox.store.box<RadioStation>();
    final query =
        recentPlayBox
            .query()
            .order(RecentPlay_.playedAt, flags: Order.descending)
            .order(RecentPlay_.id, flags: Order.descending)
            .build()
          ..limit = limit;
    try {
      final stations = <RadioStation>[];
      final recordsToUpdate = <RecentPlay>[];
      for (final recentPlay in query.find()) {
        var station = recentPlay.station.target;
        if (station == null || station.stationuuid != recentPlay.stationuuid) {
          station = _findStationByUuid(stationBox, recentPlay.stationuuid);
          if (station != null) {
            recentPlay.station.targetId = station.ID;
            recordsToUpdate.add(recentPlay);
          }
        }
        if (station != null) {
          stations.add(station);
        }
      }
      if (recordsToUpdate.isNotEmpty) {
        recentPlayBox.putMany(recordsToUpdate);
      }
      return stations;
    } finally {
      query.close();
    }
  }

  Future<void> clear() async {
    final objectBox = await ObjectBox.createAsync();
    objectBox.store.box<RecentPlay>().removeAll();
  }

  RadioStation? _findStation(
    Box<RadioStation> stationBox,
    RadioStation station,
  ) {
    if (station.ID > 0) {
      final storedStation = stationBox.get(station.ID);
      if (storedStation != null &&
          storedStation.stationuuid == station.stationuuid) {
        return storedStation;
      }
    }
    return _findStationByUuid(stationBox, station.stationuuid);
  }

  RadioStation? _findStationByUuid(
    Box<RadioStation> stationBox,
    String stationUuid,
  ) {
    final query =
        stationBox.query(RadioStation_.stationuuid.equals(stationUuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }
}
