import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:objectbox/objectbox.dart' show Order;
import 'package:lib_common/log/Logger.dart';
import 'package:radio_tower/common/extensions/StringEx.dart';
import 'package:radio_tower/common/retryable_async_initializer.dart';
import 'package:radio_tower/database/ObjectBox.dart';
import 'package:radio_tower/entity/FavoriteStation.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/objectbox.g.dart';
import 'package:radio_tower/services/full_sync_retention_policy.dart';
import 'package:radio_tower/services/station_catalog_store.dart';

enum StationSort { name, popularity, votes, clickTrend }

class StationQueryParams {
  const StationQueryParams({
    required this.filterName,
    required this.filterCountry,
    required this.filterLanguage,
    required this.filterTag,
    this.hideOfflineStations = true,
    this.sort = StationSort.name,
    required this.offset,
    required this.limit,
  });

  final String filterName;
  final String filterCountry;
  final String filterLanguage;
  final String filterTag;
  final bool hideOfflineStations;
  final StationSort sort;
  final int offset;
  final int limit;
}

class StationRepository implements StationCatalogStore {
  StationRepository._();

  static final StationRepository instance = StationRepository._();

  Isolate? _isolate;
  SendPort? _workerSendPort;
  ReceivePort? _receivePort;
  ReceivePort? _workerErrorPort;
  ReceivePort? _workerExitPort;
  Completer<void>? _initCompleter;
  final LifecycleGeneration _lifecycle = LifecycleGeneration();
  bool _isClosing = false;
  int _nextRequestId = 0;
  final _pendingRequests = PendingRequestRegistry();

  Future<void> init() {
    if (_workerSendPort != null) {
      return Future.value();
    }
    if (_isClosing) {
      return Future.error(
        StateError('Station repository is closing and cannot be initialized'),
      );
    }

    final initCompleter = _initCompleter;
    if (initCompleter != null) {
      return initCompleter.future;
    }

    final completer = Completer<void>();
    final generation = _lifecycle.begin();
    _initCompleter = completer;

    unawaited(_startWorker(completer, generation));

    return completer.future;
  }

  Future<void> _startWorker(Completer<void> completer, int generation) async {
    ReceivePort? receivePort;
    ReceivePort? errorPort;
    ReceivePort? exitPort;
    Isolate? isolate;
    var adopted = false;

    try {
      final objectBox = await ObjectBox.createAsync();
      if (!_isCurrentStartup(completer, generation)) {
        return;
      }

      final databasePath = objectBox.store.directoryPath;
      receivePort = ReceivePort();
      errorPort = ReceivePort();
      exitPort = ReceivePort();
      receivePort.listen(
        (message) => _handleWorkerMessage(message, completer, generation),
      );
      errorPort.listen((message) {
        _failWorker(
          StateError('Station repository worker crashed: $message'),
          StackTrace.current,
          completer: completer,
          generation: generation,
        );
      });
      exitPort.listen((_) {
        if (!_isClosing && _isCurrentStartup(completer, generation)) {
          _failWorker(
            StateError('Station repository worker exited unexpectedly'),
            StackTrace.current,
            completer: completer,
            generation: generation,
          );
        }
      });

      isolate = await Isolate.spawn(
        _stationRepositoryWorkerMain,
        _StationRepositoryWorkerConfig(receivePort.sendPort, databasePath),
        debugName: "StationRepositoryWorker",
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      if (!_isCurrentStartup(completer, generation)) {
        return;
      }

      _receivePort = receivePort;
      _workerErrorPort = errorPort;
      _workerExitPort = exitPort;
      _isolate = isolate;
      adopted = true;
    } catch (error, stackTrace) {
      _failWorker(
        error,
        stackTrace,
        completer: completer,
        generation: generation,
      );
    } finally {
      if (!adopted) {
        receivePort?.close();
        errorPort?.close();
        exitPort?.close();
        isolate?.kill(priority: Isolate.immediate);
      }
    }
  }

  Future<void> dispose() async {
    final workerSendPort = _workerSendPort;
    if (workerSendPort == null) {
      _lifecycle.invalidate();
      final initCompleter = _initCompleter;
      if (initCompleter != null && !initCompleter.isCompleted) {
        initCompleter.completeError(
          StateError('Station repository was disposed during initialization'),
        );
      }
      _resetWorker();
      return;
    }

    _isClosing = true;
    try {
      try {
        await _sendRequest<bool>(
          _StationRepositoryOperation.close,
          null,
          allowWhileClosing: true,
        ).timeout(const Duration(seconds: 3));
      } catch (error, stackTrace) {
        Logger.wLog(
          'StationRepository',
          '关闭数据库 worker 失败',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      _lifecycle.invalidate();
      _resetWorker(
        StateError(
          'Station repository was disposed before a request completed',
        ),
      );
      _isClosing = false;
    }
  }

  bool _isCurrentStartup(Completer<void> completer, int generation) {
    return _lifecycle.isCurrent(generation) &&
        identical(_initCompleter, completer);
  }

  void _failWorker(
    Object error,
    StackTrace stackTrace, {
    Completer<void>? completer,
    int? generation,
  }) {
    if (completer != null &&
        generation != null &&
        !_isCurrentStartup(completer, generation)) {
      return;
    }

    final initCompleter = _initCompleter;
    if (initCompleter != null && !initCompleter.isCompleted) {
      initCompleter.completeError(error, stackTrace);
    }
    _pendingRequests.failAll(error, stackTrace);
    _resetWorker();
  }

  void _resetWorker([Object? pendingError]) {
    if (_pendingRequests.length > 0) {
      _pendingRequests.failAll(
        pendingError ?? StateError('Station repository worker stopped'),
        StackTrace.current,
      );
    }
    _receivePort?.close();
    _receivePort = null;
    _workerErrorPort?.close();
    _workerErrorPort = null;
    _workerExitPort?.close();
    _workerExitPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
    _initCompleter = null;
  }

  Future<void> updateStations(List<RadioStation> stations) async {
    if (stations.isEmpty) {
      return;
    }

    await _sendRequest<void>(
      _StationRepositoryOperation.updateStations,
      stations,
    );
  }

  Future<void> updateFullSyncStations(
    List<RadioStation> stations,
    int generation,
  ) async {
    if (stations.isEmpty) {
      return;
    }
    await _sendRequest<void>(
      _StationRepositoryOperation.updateFullSyncStations,
      _FullSyncStationBatch(stations, generation),
    );
  }

  Future<void> finalizeFullSync(int generation) {
    return _sendRequest<void>(
      _StationRepositoryOperation.finalizeFullSync,
      generation,
    );
  }

  Future<void> activateLegacyStationsForSyncMigration() {
    return _sendRequest<void>(
      _StationRepositoryOperation.activateLegacyStationsForSyncMigration,
      null,
    );
  }

  Future<List<RadioStation>> queryStations(StationQueryParams params) {
    return _sendRequest<List<RadioStation>>(
      _StationRepositoryOperation.queryStations,
      params,
    );
  }

  Future<List<String>> queryDistinctCountry() {
    return _sendRequest<List<String>>(
      _StationRepositoryOperation.queryDistinctCountry,
      null,
    );
  }

  Future<List<String>> queryDistinctLanguage() {
    return _sendRequest<List<String>>(
      _StationRepositoryOperation.queryDistinctLanguage,
      null,
    );
  }

  Future<List<String>> queryDistinctTag() {
    return _sendRequest<List<String>>(
      _StationRepositoryOperation.queryDistinctTag,
      null,
    );
  }

  Future<T> _sendRequest<T>(
    _StationRepositoryOperation operation,
    Object? payload, {
    bool allowWhileClosing = false,
  }) async {
    if (_isClosing && !allowWhileClosing) {
      throw StateError('Station repository is closing');
    }
    await init();
    if (_isClosing && !allowWhileClosing) {
      throw StateError('Station repository is closing');
    }

    final workerSendPort = _workerSendPort;
    if (workerSendPort == null) {
      throw StateError('Station repository worker is unavailable');
    }

    final requestId = _nextRequestId++;
    final completer = _pendingRequests.add(requestId);
    workerSendPort.send(
      _StationRepositoryRequest(requestId, operation, payload),
    );

    return (await completer.future) as T;
  }

  void _handleWorkerMessage(
    Object? message,
    Completer<void> completer,
    int generation,
  ) {
    if (!_isCurrentStartup(completer, generation)) {
      return;
    }

    if (message is SendPort) {
      _workerSendPort = message;
      if (!completer.isCompleted) {
        completer.complete();
      }
      return;
    }

    if (message is _StationRepositoryWorkerError) {
      final error = StateError(message.message);
      _failWorker(
        error,
        StackTrace.fromString(message.stackTrace),
        completer: completer,
        generation: generation,
      );
      return;
    }

    if (message is _StationRepositoryResponse) {
      final completer = _pendingRequests.take(message.requestId);
      if (completer == null || completer.isCompleted) {
        return;
      }

      if (message.errorMessage != null) {
        completer.completeError(
          StateError(message.errorMessage!),
          StackTrace.fromString(message.stackTrace ?? ""),
        );
      } else {
        completer.complete(message.result);
      }
    }
  }
}

enum _StationRepositoryOperation {
  updateStations,
  updateFullSyncStations,
  finalizeFullSync,
  activateLegacyStationsForSyncMigration,
  queryStations,
  queryDistinctCountry,
  queryDistinctLanguage,
  queryDistinctTag,
  close,
}

class _StationRepositoryWorkerConfig {
  const _StationRepositoryWorkerConfig(this.mainSendPort, this.databasePath);

  final SendPort mainSendPort;
  final String databasePath;
}

class _StationRepositoryRequest {
  const _StationRepositoryRequest(this.requestId, this.operation, this.payload);

  final int requestId;
  final _StationRepositoryOperation operation;
  final Object? payload;
}

class _FullSyncStationBatch {
  const _FullSyncStationBatch(this.stations, this.generation);

  final List<RadioStation> stations;
  final int generation;
}

class _StationRepositoryResponse {
  const _StationRepositoryResponse({
    required this.requestId,
    this.result,
    this.errorMessage,
    this.stackTrace,
  });

  final int requestId;
  final Object? result;
  final String? errorMessage;
  final String? stackTrace;
}

class _StationRepositoryWorkerError {
  const _StationRepositoryWorkerError(this.message, this.stackTrace);

  final String message;
  final String stackTrace;
}

void _stationRepositoryWorkerMain(_StationRepositoryWorkerConfig config) {
  final receivePort = ReceivePort();
  late final Store store;

  try {
    store = Store.attach(getObjectBoxModel(), config.databasePath);
  } catch (error, stackTrace) {
    config.mainSendPort.send(
      _StationRepositoryWorkerError(error.toString(), stackTrace.toString()),
    );
    receivePort.close();
    return;
  }

  config.mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! _StationRepositoryRequest) {
      return;
    }

    try {
      final result = _handleStationRepositoryRequest(
        store,
        receivePort,
        message,
      );
      config.mainSendPort.send(
        _StationRepositoryResponse(
          requestId: message.requestId,
          result: result,
        ),
      );
    } catch (error, stackTrace) {
      Logger.eLog(
        "StationRepositoryWorker",
        "处理电台数据库请求失败",
        error: error,
        stackTrace: stackTrace,
      );
      config.mainSendPort.send(
        _StationRepositoryResponse(
          requestId: message.requestId,
          errorMessage: error.toString(),
          stackTrace: stackTrace.toString(),
        ),
      );
    }
  });
}

Object? _handleStationRepositoryRequest(
  Store store,
  ReceivePort receivePort,
  _StationRepositoryRequest request,
) {
  switch (request.operation) {
    case _StationRepositoryOperation.updateStations:
      _updateStations(store, request.payload as List<RadioStation>);
      return null;
    case _StationRepositoryOperation.updateFullSyncStations:
      final batch = request.payload as _FullSyncStationBatch;
      _updateStations(
        store,
        batch.stations,
        fullSyncGeneration: batch.generation,
      );
      return null;
    case _StationRepositoryOperation.finalizeFullSync:
      _finalizeFullSync(store, request.payload as int);
      return null;
    case _StationRepositoryOperation.activateLegacyStationsForSyncMigration:
      _activateLegacyStationsForSyncMigration(store);
      return null;
    case _StationRepositoryOperation.queryStations:
      return _queryStations(store, request.payload as StationQueryParams);
    case _StationRepositoryOperation.queryDistinctCountry:
      return _queryDistinctCountry(store);
    case _StationRepositoryOperation.queryDistinctLanguage:
      return _queryDistinctLanguage(store);
    case _StationRepositoryOperation.queryDistinctTag:
      return _queryDistinctTag(store);
    case _StationRepositoryOperation.close:
      receivePort.close();
      store.close();
      return true;
  }
}

void _updateStations(
  Store store,
  List<RadioStation> newStations, {
  int? fullSyncGeneration,
}) {
  final stationBox = store.box<RadioStation>();

  store.runInTransaction(TxMode.write, () {
    final stationsToPut = <RadioStation>[];

    for (final station in newStations) {
      final trimmedName = station.name.trim();
      if (trimmedName.isEmptyOrBlank()) {
        continue;
      }

      station.name = trimmedName;
      station.country = station.country.trim();
      station.tags = station.tags.trim();
      station.isActive = true;
      station.syncStateInitialized = true;
      if (fullSyncGeneration != null) {
        station.lastSeenFullSyncGeneration = fullSyncGeneration;
      }

      final oldStationQuery =
          stationBox
              .query(RadioStation_.stationuuid.equals(station.stationuuid))
              .build();
      try {
        final oldStation = oldStationQuery.findFirst();
        if (oldStation != null) {
          station.ID = oldStation.ID;
        }
      } finally {
        oldStationQuery.close();
      }

      stationsToPut.add(station);
    }

    if (stationsToPut.isNotEmpty) {
      stationBox.putMany(stationsToPut);
    }
  });
}

void _finalizeFullSync(Store store, int generation) {
  final stationBox = store.box<RadioStation>();
  final favoriteBox = store.box<FavoriteStation>();
  const retentionPolicy = FullSyncRetentionPolicy();

  store.runInTransaction(TxMode.write, () {
    final favoriteUuids =
        favoriteBox
            .getAll()
            .map((favorite) => favorite.stationuuid)
            .where((uuid) => uuid.isNotEmpty)
            .toSet();
    final stationsToDeactivate = <RadioStation>[];
    final stationIdsToRemove = <int>[];

    for (final station in stationBox.getAll()) {
      switch (retentionPolicy.resolve(
        currentGeneration: generation,
        lastSeenGeneration: station.lastSeenFullSyncGeneration,
        isFavorite: favoriteUuids.contains(station.stationuuid),
      )) {
        case FullSyncRetentionAction.retain:
          break;
        case FullSyncRetentionAction.deactivate:
          if (station.isActive) {
            station.isActive = false;
            stationsToDeactivate.add(station);
          }
          break;
        case FullSyncRetentionAction.remove:
          stationIdsToRemove.add(station.ID);
      }
    }

    if (stationsToDeactivate.isNotEmpty) {
      stationBox.putMany(stationsToDeactivate);
    }
    if (stationIdsToRemove.isNotEmpty) {
      stationBox.removeMany(stationIdsToRemove);
    }
  });
}

void _activateLegacyStationsForSyncMigration(Store store) {
  final stationBox = store.box<RadioStation>();
  store.runInTransaction(TxMode.write, () {
    final stations = stationBox.getAll();
    for (final station in stations) {
      if (station.syncStateInitialized) {
        continue;
      }
      station.isActive = true;
      station.syncStateInitialized = true;
    }
    if (stations.isNotEmpty) {
      stationBox.putMany(stations);
    }
  });
}

List<RadioStation> _queryStations(Store store, StationQueryParams params) {
  final stationBox = store.box<RadioStation>();
  final queryBuilder = stationBox.query(_buildStationQueryCondition(params));
  switch (params.sort) {
    case StationSort.name:
      queryBuilder.order(RadioStation_.name);
    case StationSort.popularity:
      queryBuilder.order(RadioStation_.clickcount, flags: Order.descending);
      queryBuilder.order(RadioStation_.name);
    case StationSort.votes:
      queryBuilder.order(RadioStation_.votes, flags: Order.descending);
      queryBuilder.order(RadioStation_.name);
    case StationSort.clickTrend:
      queryBuilder.order(RadioStation_.clicktrend, flags: Order.descending);
      queryBuilder.order(RadioStation_.name);
  }
  queryBuilder.order(RadioStation_.ID);
  final query = queryBuilder.build()
    ..offset = params.offset
    ..limit = params.limit;

  try {
    final stations = query.find();
    stations.removeWhere((station) => station.name.isEmptyOrBlank());
    return stations;
  } finally {
    query.close();
  }
}

Condition<RadioStation>? _buildStationQueryCondition(
  StationQueryParams params,
) {
  Condition<RadioStation>? condition = RadioStation_.isActive.equals(true);

  void andCondition(Condition<RadioStation> nextCondition) {
    condition =
        condition == null ? nextCondition : condition!.and(nextCondition);
  }

  if (params.filterName.isNotEmpty) {
    andCondition(
      RadioStation_.name.contains(params.filterName, caseSensitive: false),
    );
  }

  if (params.hideOfflineStations) {
    andCondition(RadioStation_.lastcheckok.equals(true));
  }

  if (params.filterCountry.isNotEmpty) {
    andCondition(
      RadioStation_.country.contains(
        params.filterCountry,
        caseSensitive: false,
      ),
    );
  }

  if (params.filterLanguage.isNotEmpty) {
    andCondition(
      RadioStation_.language.contains(
        params.filterLanguage,
        caseSensitive: false,
      ),
    );
  }

  if (params.filterTag.isNotEmpty) {
    andCondition(
      RadioStation_.tags.contains(params.filterTag, caseSensitive: false),
    );
  }

  return condition;
}

List<String> _queryDistinctCountry(Store store) {
  final countries = _queryStringProperty(
    store,
    RadioStation_.country,
    distinct: true,
  );

  countries.removeWhere((str) => str.isEmptyOrBlank());
  countries.sort((a, b) => a.compareTo(b));
  return countries;
}

List<String> _queryDistinctLanguage(Store store) {
  final rawLanguages = _queryStringProperty(
    store,
    RadioStation_.language,
    distinct: true,
  );

  final languageSet = HashSet<String>();
  final filterSet = HashSet<String>();

  for (final language in rawLanguages) {
    if (language.contains(",")) {
      for (final item in language.split(",")) {
        languageSet.add(item);
      }
    } else if (language.isNotBlank()) {
      languageSet.add(language);
    }
  }

  for (final language in languageSet) {
    final fixedLanguage =
        language.startsWith("#") ? language.substring(1) : language;

    if (fixedLanguage.startsWith("+") || fixedLanguage.startsWith("[0 - 9]")) {
      continue;
    }

    if (fixedLanguage.isNotEmptyOrBlank()) {
      filterSet.add(fixedLanguage.firstLetterToUpper());
    }
  }

  final sortedList = filterSet.toList();
  sortedList.sort((a, b) => a.compareTo(b));
  return sortedList;
}

List<String> _queryDistinctTag(Store store) {
  final rawTags = _queryStringProperty(
    store,
    RadioStation_.tags,
    distinct: true,
  );

  final tagSet = HashSet<String>();
  final filterSet = HashSet<String>();

  for (final tag in rawTags) {
    if (tag.contains(",")) {
      for (final item in tag.split(",")) {
        tagSet.add(item.replaceFirst("\"", " ").trim());
      }
    } else if (tag.isNotEmptyOrBlank()) {
      tagSet.add(tag.replaceFirst("\"", " ").trim());
    }
  }

  for (final tag in tagSet) {
    final fixedTag =
        tag.startsWith("#") ? tag.replaceFirst(RegExp(r"^#+"), "") : tag;

    if (fixedTag.startsWith(".") ||
        fixedTag.startsWith("'") ||
        fixedTag.startsWith("-")) {
      continue;
    }

    if (fixedTag.length >= 2) {
      filterSet.add(fixedTag.firstLetterToUpper());
    }
  }

  final sortedList = filterSet.toList();
  sortedList.sort((a, b) => a.compareTo(b));
  return sortedList;
}

List<String> _queryStringProperty(
  Store store,
  QueryStringProperty<RadioStation> property, {
  bool distinct = false,
}) {
  final stationBox = store.box<RadioStation>();
  final query = stationBox.query(RadioStation_.isActive.equals(true)).build();
  final propertyQuery = query.property(property);
  propertyQuery.distinct = distinct;

  try {
    return propertyQuery.find();
  } finally {
    propertyQuery.close();
    query.close();
  }
}
