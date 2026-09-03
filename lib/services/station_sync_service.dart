import 'dart:async';

import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/networks/RadioDataFetcher.dart';

typedef StationBatchWriter = Future<void> Function(List<RadioStation> stations);
typedef FullStationBatchWriter =
    Future<void> Function(List<RadioStation> stations, int generation);
typedef FullSyncFinalizer = Future<void> Function(int generation);

enum StationSyncStatus { idle, syncing, succeeded, failed }

enum StationSyncKind { full, incremental }

class StationSyncState {
  const StationSyncState({
    required this.status,
    this.kind,
    this.error,
    this.pageCount = 0,
  });

  const StationSyncState.idle() : this(status: StationSyncStatus.idle);

  final StationSyncStatus status;
  final StationSyncKind? kind;
  final Object? error;
  final int pageCount;
}

class StationSyncResult {
  const StationSyncResult._({
    required this.kind,
    required this.pageCount,
    this.watermark,
    this.fullSyncGeneration,
    this.error,
  });

  const StationSyncResult.success({
    required StationSyncKind kind,
    required int pageCount,
    int? watermark,
    int? fullSyncGeneration,
  }) : this._(
         kind: kind,
         pageCount: pageCount,
         watermark: watermark,
         fullSyncGeneration: fullSyncGeneration,
       );

  const StationSyncResult.failure({
    required StationSyncKind kind,
    required int pageCount,
    required Object error,
  }) : this._(kind: kind, pageCount: pageCount, error: error);

  final StationSyncKind kind;
  final int pageCount;
  final int? watermark;
  final int? fullSyncGeneration;
  final Object? error;

  bool get isSuccess => error == null;
}

class StationSyncException implements Exception {
  const StationSyncException(this.message);

  final String message;

  @override
  String toString() => 'StationSyncException: $message';
}

class StationSyncService {
  StationSyncService({
    required StationRemoteSource remoteSource,
    required StationBatchWriter writeStations,
    FullStationBatchWriter? writeFullStations,
    FullSyncFinalizer? finalizeFullSync,
    this.pageSize = 1000,
    this.maxPageCount = 1000,
    this.incrementalOverlap = const Duration(hours: 2),
  }) : _remoteSource = remoteSource,
       _writeStations = writeStations,
       _writeFullStations = writeFullStations,
       _finalizeFullSync = finalizeFullSync;

  final StationRemoteSource _remoteSource;
  final StationBatchWriter _writeStations;
  final FullStationBatchWriter? _writeFullStations;
  final FullSyncFinalizer? _finalizeFullSync;
  final int pageSize;
  final int maxPageCount;
  final Duration incrementalOverlap;

  StationSyncState _state = const StationSyncState.idle();
  Future<StationSyncResult>? _activeRun;
  StationSyncKind? _activeKind;

  StationSyncState get state => _state;

  Future<StationSyncResult> synchronizeFull({required int fullSyncGeneration}) {
    return _startRun(
      StationSyncKind.full,
      () => _synchronizeFull(fullSyncGeneration),
    );
  }

  Future<StationSyncResult> synchronizeIncrementally({
    required int currentWatermark,
    required int nextWatermark,
  }) {
    return _startRun(
      StationSyncKind.incremental,
      () => _synchronizeIncrementally(
        currentWatermark: currentWatermark,
        nextWatermark: nextWatermark,
      ),
    );
  }

  Future<StationSyncResult> _startRun(
    StationSyncKind kind,
    Future<StationSyncResult> Function() action,
  ) {
    final activeRun = _activeRun;
    if (activeRun != null) {
      if (_activeKind != kind) {
        return Future.value(
          StationSyncResult.failure(
            kind: kind,
            pageCount: _state.pageCount,
            error: const StationSyncException('另一种电台同步正在进行'),
          ),
        );
      }
      return activeRun;
    }

    final run = action();
    _activeRun = run;
    _activeKind = kind;
    return run.whenComplete(() {
      if (identical(_activeRun, run)) {
        _activeRun = null;
        _activeKind = null;
      }
    });
  }

  Future<StationSyncResult> _synchronizeFull(int fullSyncGeneration) async {
    var pageCount = 0;
    _state = const StationSyncState(
      status: StationSyncStatus.syncing,
      kind: StationSyncKind.full,
    );
    try {
      await _ensureServer();
      var offset = 0;
      final seenUuids = <String>{};
      while (true) {
        if (pageCount >= maxPageCount) {
          throw const StationSyncException('全量同步超过安全页数上限');
        }
        final stations = await _remoteSource.fetchRadioStationList(
          offset: offset,
          limit: pageSize,
        );
        pageCount++;
        await _writeUniqueStations(
          stations,
          seenUuids,
          fullSyncGeneration: fullSyncGeneration,
        );
        if (stations.length < pageSize) {
          await _finalizeFullSync?.call(fullSyncGeneration);
          return _succeed(
            StationSyncKind.full,
            pageCount,
            fullSyncGeneration: fullSyncGeneration,
          );
        }
        offset += stations.length;
      }
    } catch (error) {
      return _fail(StationSyncKind.full, pageCount, error);
    }
  }

  Future<StationSyncResult> _synchronizeIncrementally({
    required int currentWatermark,
    required int nextWatermark,
  }) async {
    var pageCount = 0;
    _state = const StationSyncState(
      status: StationSyncStatus.syncing,
      kind: StationSyncKind.incremental,
    );
    try {
      await _ensureServer();
      final overlapStart = currentWatermark - incrementalOverlap.inMilliseconds;
      var offset = 0;
      int? previousTimestamp;
      final seenUuids = <String>{};

      while (true) {
        if (pageCount >= maxPageCount) {
          throw const StationSyncException('增量同步超过安全页数上限');
        }
        final stations = await _remoteSource.fetchChangedStations(
          offset: offset,
          limit: pageSize,
        );
        pageCount++;
        previousTimestamp = _validateDescendingLastChange(
          stations,
          previousTimestamp,
        );
        await _writeUniqueStations(stations, seenUuids);

        if (stations.isEmpty || stations.length < pageSize) {
          return _succeed(
            StationSyncKind.incremental,
            pageCount,
            watermark: nextWatermark,
          );
        }

        final oldestTimestamp = _lastChangeTimestamp(stations.last);
        if (oldestTimestamp <= overlapStart) {
          return _succeed(
            StationSyncKind.incremental,
            pageCount,
            watermark: nextWatermark,
          );
        }
        offset += stations.length;
      }
    } catch (error) {
      return _fail(StationSyncKind.incremental, pageCount, error);
    }
  }

  Future<void> _ensureServer() async {
    if (!await _remoteSource.ensureServer()) {
      throw const StationSyncException('没有可用的 Radio Browser 节点');
    }
  }

  Future<void> _writeUniqueStations(
    List<RadioStation> stations,
    Set<String> seenUuids, {
    int? fullSyncGeneration,
  }) async {
    final uniqueStations = <RadioStation>[];
    for (final station in stations) {
      final uuid = station.stationuuid;
      if (uuid.isEmpty || seenUuids.add(uuid)) {
        uniqueStations.add(station);
      }
    }
    if (uniqueStations.isNotEmpty) {
      if (fullSyncGeneration == null) {
        await _writeStations(uniqueStations);
      } else if (_writeFullStations != null) {
        await _writeFullStations(uniqueStations, fullSyncGeneration);
      } else {
        await _writeStations(uniqueStations);
      }
    }
  }

  int? _validateDescendingLastChange(
    List<RadioStation> stations,
    int? previousTimestamp,
  ) {
    for (final station in stations) {
      final timestamp = _lastChangeTimestamp(station);
      if (previousTimestamp != null && timestamp > previousTimestamp) {
        throw const StationSyncException('/lastchange 响应未按最后修改时间倒序排列');
      }
      previousTimestamp = timestamp;
    }
    return previousTimestamp;
  }

  int _lastChangeTimestamp(RadioStation station) {
    final timestamp = station.lastchangetime ?? station.lastchangetime_iso8601;
    if (timestamp == null) {
      throw const StationSyncException('/lastchange 响应缺少最后修改时间');
    }
    return timestamp.toUtc().millisecondsSinceEpoch;
  }

  StationSyncResult _succeed(
    StationSyncKind kind,
    int pageCount, {
    int? watermark,
    int? fullSyncGeneration,
  }) {
    _state = StationSyncState(
      status: StationSyncStatus.succeeded,
      kind: kind,
      pageCount: pageCount,
    );
    return StationSyncResult.success(
      kind: kind,
      pageCount: pageCount,
      watermark: watermark,
      fullSyncGeneration: fullSyncGeneration,
    );
  }

  StationSyncResult _fail(StationSyncKind kind, int pageCount, Object error) {
    _state = StationSyncState(
      status: StationSyncStatus.failed,
      kind: kind,
      pageCount: pageCount,
      error: error,
    );
    return StationSyncResult.failure(
      kind: kind,
      pageCount: pageCount,
      error: error,
    );
  }
}
