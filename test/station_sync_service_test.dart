import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/networks/RadioDataFetcher.dart';
import 'package:radio_tower/services/station_sync_service.dart';

void main() {
  test(
    'does not advance the incremental watermark after a later page fails',
    () async {
      final source = _FakeStationRemoteSource(
        changedPages: [
          [_station('one', 100), _station('two', 99)],
          const _ThrowingPage(),
        ],
      );
      final written = <List<RadioStation>>[];
      final service = StationSyncService(
        remoteSource: source,
        writeStations: (stations) async => written.add(stations),
        pageSize: 2,
      );

      final result = await service.synchronizeIncrementally(
        currentWatermark: 90,
        nextWatermark: 110,
      );

      expect(result.isSuccess, isFalse);
      expect(result.watermark, isNull);
      expect(service.state.status, StationSyncStatus.failed);
      expect(written.single.map((station) => station.stationuuid), [
        'one',
        'two',
      ]);
    },
  );

  test(
    'uses a two-hour overlap and de-duplicates shifted incremental pages',
    () async {
      final hour = Duration.millisecondsPerHour;
      final source = _FakeStationRemoteSource(
        changedPages: [
          [_station('one', 12 * hour), _station('two', 11 * hour)],
          [_station('two', 11 * hour), _station('three', 10 * hour)],
          [_station('four', 9 * hour), _station('five', 8 * hour)],
        ],
      );
      final writtenUuids = <String>[];
      final service = StationSyncService(
        remoteSource: source,
        writeStations: (stations) async {
          writtenUuids.addAll(stations.map((station) => station.stationuuid));
        },
        pageSize: 2,
      );

      final result = await service.synchronizeIncrementally(
        currentWatermark: 10 * hour,
        nextWatermark: 13 * hour,
      );

      expect(result.isSuccess, isTrue);
      expect(result.watermark, 13 * hour);
      expect(source.changedOffsets, [0, 2, 4]);
      expect(writtenUuids, ['one', 'two', 'three', 'four', 'five']);
    },
  );

  test('fails an out-of-order lastchange page without writing it', () async {
    final source = _FakeStationRemoteSource(
      changedPages: [
        [_station('older', 100), _station('newer', 101)],
      ],
    );
    var writes = 0;
    final service = StationSyncService(
      remoteSource: source,
      writeStations: (_) async => writes++,
      pageSize: 2,
    );

    final result = await service.synchronizeIncrementally(
      currentWatermark: 0,
      nextWatermark: 200,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, isA<StationSyncException>());
    expect(writes, 0);
  });

  test('fails at the page cap without returning a checkpoint', () async {
    final source = _FakeStationRemoteSource(
      changedPages: [
        [_station('one', 100), _station('two', 99)],
        [_station('three', 98), _station('four', 97)],
      ],
    );
    final service = StationSyncService(
      remoteSource: source,
      writeStations: (_) async {},
      pageSize: 2,
      maxPageCount: 1,
    );

    final result = await service.synchronizeIncrementally(
      currentWatermark: 0,
      nextWatermark: 200,
    );

    expect(result.isSuccess, isFalse);
    expect(result.watermark, isNull);
    expect(result.error, isA<StationSyncException>());
  });

  test('rejects a different sync kind while a run is active', () async {
    final source = _BlockingStationRemoteSource();
    final service = StationSyncService(
      remoteSource: source,
      writeStations: (_) async {},
      pageSize: 2,
    );

    final incrementalRun = service.synchronizeIncrementally(
      currentWatermark: 0,
      nextWatermark: 200,
    );
    await source.changedRequestStarted.future;

    final fullResult = await service.synchronizeFull(fullSyncGeneration: 1);
    expect(fullResult.isSuccess, isFalse);
    expect(fullResult.kind, StationSyncKind.full);
    expect(fullResult.error, isA<StationSyncException>());

    source.completeChangedPage(const []);
    expect((await incrementalRun).isSuccess, isTrue);
  });

  test(
    'finalizes a full generation only after every page is written',
    () async {
      final source = _FullSyncFakeStationRemoteSource([
        [_station('one', 100), _station('two', 99)],
        [],
      ]);
      final writtenGenerations = <int>[];
      var finalizedGeneration = 0;
      final service = StationSyncService(
        remoteSource: source,
        writeStations: (_) async {},
        writeFullStations: (_, generation) async {
          writtenGenerations.add(generation);
        },
        finalizeFullSync: (generation) async {
          finalizedGeneration = generation;
        },
        pageSize: 2,
      );

      final result = await service.synchronizeFull(fullSyncGeneration: 4);

      expect(result.isSuccess, isTrue);
      expect(result.fullSyncGeneration, 4);
      expect(writtenGenerations, [4]);
      expect(finalizedGeneration, 4);
    },
  );
}

class _FakeStationRemoteSource implements StationRemoteSource {
  _FakeStationRemoteSource({required this.changedPages});

  final List<Object> changedPages;
  final List<int> changedOffsets = [];

  @override
  Future<bool> ensureServer() async => true;

  @override
  Future<List<RadioStation>> fetchChangedStations({
    int offset = 0,
    int limit = 0,
    bool hidebroken = false,
  }) async {
    changedOffsets.add(offset);
    final pageIndex = offset ~/ limit;
    final page = changedPages[pageIndex];
    if (page is _ThrowingPage) {
      throw StateError('network interrupted');
    }
    return page as List<RadioStation>;
  }

  @override
  Future<List<RadioStation>> fetchRadioStationList({
    int offset = 0,
    int limit = 0,
    bool reverse = false,
    bool hidebroken = false,
    String order = ApiListOrder.BY_NAME,
  }) async => const [];
}

class _ThrowingPage {
  const _ThrowingPage();
}

class _BlockingStationRemoteSource implements StationRemoteSource {
  final changedRequestStarted = Completer<void>();
  final _changedPage = Completer<List<RadioStation>>();

  void completeChangedPage(List<RadioStation> stations) {
    _changedPage.complete(stations);
  }

  @override
  Future<bool> ensureServer() async => true;

  @override
  Future<List<RadioStation>> fetchChangedStations({
    int offset = 0,
    int limit = 0,
    bool hidebroken = false,
  }) {
    changedRequestStarted.complete();
    return _changedPage.future;
  }

  @override
  Future<List<RadioStation>> fetchRadioStationList({
    int offset = 0,
    int limit = 0,
    bool reverse = false,
    bool hidebroken = false,
    String order = ApiListOrder.BY_NAME,
  }) async => const [];
}

class _FullSyncFakeStationRemoteSource implements StationRemoteSource {
  _FullSyncFakeStationRemoteSource(this.pages);

  final List<List<RadioStation>> pages;

  @override
  Future<bool> ensureServer() async => true;

  @override
  Future<List<RadioStation>> fetchChangedStations({
    int offset = 0,
    int limit = 0,
    bool hidebroken = false,
  }) async => const [];

  @override
  Future<List<RadioStation>> fetchRadioStationList({
    int offset = 0,
    int limit = 0,
    bool reverse = false,
    bool hidebroken = false,
    String order = ApiListOrder.BY_NAME,
  }) async => pages[offset ~/ limit];
}

RadioStation _station(String uuid, int millisecondsSinceEpoch) {
  return RadioStation()
    ..stationuuid = uuid
    ..name = uuid
    ..lastchangetime = DateTime.fromMillisecondsSinceEpoch(
      millisecondsSinceEpoch,
      isUtc: true,
    );
}
