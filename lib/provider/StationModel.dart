import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:radio_tower/common/station_sync_schedule.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/manger/ConfigKeys.dart';
import 'package:radio_tower/manger/ConfigMgr.dart';
import 'package:radio_tower/networks/RadioDataFetcher.dart';
import 'package:radio_tower/repository/station_repository.dart';
import 'package:radio_tower/services/station_catalog_store.dart';
import 'package:radio_tower/services/station_sync_service.dart';

abstract interface class StationSyncPreferences {
  int getInt(String key, int defaultValue);
  Future<void> saveValues(Map<String, int> values);
}

class ConfigStationSyncPreferences implements StationSyncPreferences {
  @override
  int getInt(String key, int defaultValue) =>
      ConfigMgr().getIntVal(key, defaultValue);

  @override
  Future<void> saveValues(Map<String, int> values) async {
    final config = ConfigMgr();
    for (final entry in values.entries) {
      config.put(entry.key, entry.value);
    }
    await config.save();
  }
}

class StationModel extends ChangeNotifier {
  StationModel({
    StationCatalogStore? repository,
    StationRemoteSource? remoteSource,
    StationSyncPreferences? preferences,
  }) : _repository = repository ?? StationRepository.instance,
       _preferences = preferences ?? ConfigStationSyncPreferences() {
    _syncService = StationSyncService(
      remoteSource: remoteSource ?? RadioDataFetcher(),
      writeStations: _repository.updateStations,
      writeFullStations: _repository.updateFullSyncStations,
      finalizeFullSync: _repository.finalizeFullSync,
    );
  }

  final StationCatalogStore _repository;
  final StationSyncPreferences _preferences;
  final StationSyncSchedule _schedule = const StationSyncSchedule();
  late final StationSyncService _syncService;
  Future<void>? _initializing;
  Future<StationSyncResult>? _syncing;
  bool _initialized = false;
  bool _hideOfflineStations = true;
  int _dataVersion = 0;
  StationSyncState _syncState = const StationSyncState.idle();

  bool get isInitialized => _initialized;
  int get dataVersion => _dataVersion;
  StationSyncState get syncState => _syncState;
  bool get isSyncing => _syncState.status == StationSyncStatus.syncing;
  Object? get syncError => _syncState.error;
  bool get hideOfflineStations => _hideOfflineStations;

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _repository.init();
      _hideOfflineStations = ConfigMgr().getBoolVal(
        ConfigKeys.KEY_HIDE_OFFLINE_STATIONS,
        true,
      );
      if (_preferences.getInt(ConfigKeys.KEY_STATION_SYNC_SCHEMA_VERSION, 0) !=
          StationSyncSchedule.currentSchemaVersion) {
        await _repository.activateLegacyStationsForSyncMigration();
      }
      _initialized = true;
      notifyListeners();
    } finally {
      _initializing = null;
    }
  }

  Future<StationSyncResult> syncIfNeeded() => sync(forceFull: false);
  Future<StationSyncResult> retry() => sync(forceFull: false);
  Future<StationSyncResult> syncNow() => sync(forceFull: true);

  Future<StationSyncResult> sync({required bool forceFull}) {
    final existing = _syncing;
    if (existing != null) return existing;
    final run = _runSync(forceFull);
    _syncing = run;
    return run.whenComplete(() {
      if (identical(_syncing, run)) _syncing = null;
    });
  }

  Future<StationSyncResult> _runSync(bool forceFull) async {
    await initialize();
    final now = DateTime.now().millisecondsSinceEpoch;
    final needsFull =
        forceFull ||
        _schedule.requiresFullSync(
          storedSchemaVersion: _preferences.getInt(
            ConfigKeys.KEY_STATION_SYNC_SCHEMA_VERSION,
            0,
          ),
          lastSuccessfulFullSyncAt: _preferences.getInt(
            ConfigKeys.KEY_LAST_SUCCESSFUL_FULL_SYNC_TIME,
            0,
          ),
          now: now,
        );
    _syncState = StationSyncState(
      status: StationSyncStatus.syncing,
      kind: needsFull ? StationSyncKind.full : StationSyncKind.incremental,
    );
    notifyListeners();

    final result =
        needsFull
            ? await _syncService.synchronizeFull(
              fullSyncGeneration:
                  _preferences.getInt(ConfigKeys.KEY_FULL_SYNC_GENERATION, 0) +
                  1,
            )
            : await _syncService.synchronizeIncrementally(
              currentWatermark: _preferences.getInt(
                ConfigKeys.KEY_LAST_INCREMENTAL_SYNC_WATERMARK,
                0,
              ),
              nextWatermark: now,
            );
    _syncState = _syncService.state;
    if (result.isSuccess) {
      await _persistSuccessfulSync(result);
      _dataVersion++;
    }
    notifyListeners();
    return result;
  }

  Future<void> _persistSuccessfulSync(StationSyncResult result) {
    if (result.kind == StationSyncKind.full) {
      return _preferences.saveValues({
        ConfigKeys.KEY_STATION_SYNC_SCHEMA_VERSION:
            StationSyncSchedule.currentSchemaVersion,
        ConfigKeys.KEY_LAST_SUCCESSFUL_FULL_SYNC_TIME:
            DateTime.now().millisecondsSinceEpoch,
        ConfigKeys.KEY_LAST_INCREMENTAL_SYNC_WATERMARK:
            DateTime.now().millisecondsSinceEpoch,
        ConfigKeys.KEY_FULL_SYNC_GENERATION: result.fullSyncGeneration!,
      });
    }
    return _preferences.saveValues({
      ConfigKeys.KEY_LAST_INCREMENTAL_SYNC_WATERMARK: result.watermark!,
    });
  }

  Future<List<RadioStation>> queryStations(StationQueryParams params) =>
      _repository.queryStations(params);

  Future<void> setHideOfflineStations(bool hideOfflineStations) async {
    if (_hideOfflineStations == hideOfflineStations) {
      return;
    }
    _hideOfflineStations = hideOfflineStations;
    notifyListeners();
    await ConfigMgr()
        .put(ConfigKeys.KEY_HIDE_OFFLINE_STATIONS, hideOfflineStations)
        .save();
  }
  Future<List<String>> queryDistinctCountry() =>
      _repository.queryDistinctCountry();
  Future<List<String>> queryDistinctLanguage() =>
      _repository.queryDistinctLanguage();
  Future<List<String>> queryDistinctTag() => _repository.queryDistinctTag();
}
