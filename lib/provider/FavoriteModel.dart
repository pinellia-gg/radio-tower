import 'package:flutter/foundation.dart';
import 'package:radio_tower/database/FavoriteDb.dart';
import 'package:radio_tower/entity/FavoriteList.dart';
import 'package:radio_tower/entity/RadioStation.dart';

class FavoriteModel extends ChangeNotifier {
  final FavoriteDb _favoriteDb = FavoriteDb();

  bool _initialized = false;
  bool _loading = false;
  List<FavoriteList> _favoriteLists = [];
  Map<int, List<RadioStation>> _stationsByList = {};
  Set<String> _defaultFavoriteStationUuids = {};

  FavoriteModel() {
    reload();
  }

  bool get isLoading => _loading;

  List<FavoriteList> get favoriteLists => List.unmodifiable(_favoriteLists);

  FavoriteList? get defaultList {
    for (final list in _favoriteLists) {
      if (list.isDefault) {
        return list;
      }
    }
    return _favoriteLists.isEmpty ? null : _favoriteLists.first;
  }

  List<RadioStation> stationsForList(int listId) {
    return List.unmodifiable(_stationsByList[listId] ?? []);
  }

  bool isInDefaultList(RadioStation? station) {
    if (station == null || station.stationuuid.isEmpty) {
      return false;
    }
    return _defaultFavoriteStationUuids.contains(station.stationuuid);
  }

  Set<int> listIdsForStation(String stationUuid) {
    if (stationUuid.isEmpty) {
      return {};
    }

    final result = <int>{};
    for (final entry in _stationsByList.entries) {
      final hasStation = entry.value.any(
        (station) => station.stationuuid == stationUuid,
      );
      if (hasStation) {
        result.add(entry.key);
      }
    }
    return result;
  }

  Future<void> ensureLoaded() async {
    while (_loading) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (!_initialized) {
      await reload();
    }
  }

  Future<void> reload() async {
    _loading = true;
    notifyListeners();

    final lists = await _favoriteDb.getLists();
    final stationsByList = <int, List<RadioStation>>{};
    for (final list in lists) {
      stationsByList[list.id] = await _favoriteDb.getStations(list.id);
    }

    int? defaultId;
    for (final list in lists) {
      if (list.isDefault) {
        defaultId = list.id;
        break;
      }
    }

    _favoriteLists = lists;
    _stationsByList = stationsByList;
    _defaultFavoriteStationUuids =
        defaultId == null
            ? {}
            : (stationsByList[defaultId] ?? [])
                .map((station) => station.stationuuid)
                .toSet();
    _initialized = true;
    _loading = false;

    notifyListeners();
  }

  Future<FavoriteList?> createList(String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      return null;
    }

    final favoriteList = await _favoriteDb.createList(cleanName);
    await reload();
    return _favoriteLists.firstWhere(
      (list) => list.id == favoriteList.id,
      orElse: () => favoriteList,
    );
  }

  Future<bool> renameList(FavoriteList favoriteList, String name) async {
    final renamed = await _favoriteDb.renameList(favoriteList, name);
    await reload();
    return renamed;
  }

  Future<bool> deleteList(FavoriteList favoriteList) async {
    final deleted = await _favoriteDb.deleteList(favoriteList);
    await reload();
    return deleted;
  }

  Future<void> setStationLists(
    RadioStation station,
    Set<int> selectedListIds,
  ) async {
    await _favoriteDb.setStationLists(station, selectedListIds);
    await reload();
  }
}
