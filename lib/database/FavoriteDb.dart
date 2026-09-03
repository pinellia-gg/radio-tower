import 'package:radio_tower/database/ObjectBox.dart';
import 'package:radio_tower/entity/FavoriteList.dart';
import 'package:radio_tower/entity/FavoriteStation.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/objectbox.g.dart';

class FavoriteDb {
  // This identifier is never presented directly to the user. The UI renders
  // the default list using the active locale instead.
  static const String defaultListName = '__default_favorites__';

  FavoriteDb._create();

  static final FavoriteDb _instance = FavoriteDb._create();

  factory FavoriteDb() {
    return _instance;
  }

  Future<FavoriteList> ensureDefaultList() async {
    final objectBox = await ObjectBox.createAsync();
    final listBox = objectBox.store.box<FavoriteList>();

    final defaultQuery =
        listBox.query(FavoriteList_.isDefault.equals(true)).build();
    FavoriteList? defaultList;
    try {
      defaultList = defaultQuery.findFirst();
    } finally {
      defaultQuery.close();
    }

    if (defaultList == null) {
      final nameQuery =
          listBox.query(FavoriteList_.name.equals(defaultListName)).build();
      try {
        defaultList = nameQuery.findFirst();
      } finally {
        nameQuery.close();
      }
    }

    if (defaultList == null) {
      defaultList = FavoriteList(name: defaultListName, isDefault: true);
    } else {
      defaultList.name = defaultListName;
      defaultList.isDefault = true;
      defaultList.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    final id = listBox.put(defaultList);
    defaultList.id = id;
    return defaultList;
  }

  Future<List<FavoriteList>> getLists() async {
    await ensureDefaultList();
    final objectBox = await ObjectBox.createAsync();
    final listBox = objectBox.store.box<FavoriteList>();
    final query = listBox.query().order(FavoriteList_.createdAt).build();
    try {
      final lists = query.find();
      lists.sort((a, b) {
        if (a.isDefault != b.isDefault) {
          return a.isDefault ? -1 : 1;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
      return lists;
    } finally {
      query.close();
    }
  }

  Future<FavoriteList> createList(String name) async {
    final cleanName = name.trim();
    final objectBox = await ObjectBox.createAsync();
    final listBox = objectBox.store.box<FavoriteList>();
    final query = listBox.query(FavoriteList_.name.equals(cleanName)).build();
    try {
      final existing = query.findFirst();
      if (existing != null) {
        return existing;
      }
    } finally {
      query.close();
    }

    final favoriteList = FavoriteList(name: cleanName);
    final id = listBox.put(favoriteList);
    favoriteList.id = id;
    return favoriteList;
  }

  Future<bool> renameList(FavoriteList favoriteList, String name) async {
    await ensureDefaultList();

    final cleanName = name.trim();
    if (cleanName.isEmpty || favoriteList.isDefault) {
      return false;
    }

    final objectBox = await ObjectBox.createAsync();
    final listBox = objectBox.store.box<FavoriteList>();
    final currentList = listBox.get(favoriteList.id);
    if (currentList == null || currentList.isDefault) {
      return false;
    }

    final query = listBox.query(FavoriteList_.name.equals(cleanName)).build();
    try {
      final existing = query.findFirst();
      if (existing != null && existing.id != currentList.id) {
        return false;
      }
    } finally {
      query.close();
    }

    currentList.name = cleanName;
    currentList.updatedAt = DateTime.now().millisecondsSinceEpoch;
    listBox.put(currentList);
    return true;
  }

  Future<bool> deleteList(FavoriteList favoriteList) async {
    await ensureDefaultList();
    if (favoriteList.isDefault) {
      return false;
    }

    final objectBox = await ObjectBox.createAsync();
    final listBox = objectBox.store.box<FavoriteList>();
    final stationBox = objectBox.store.box<FavoriteStation>();

    final stationsQuery =
        stationBox
            .query(FavoriteStation_.listId.equals(favoriteList.id))
            .build();
    try {
      final favoriteIds = stationsQuery.findIds();
      if (favoriteIds.isNotEmpty) {
        stationBox.removeMany(favoriteIds);
      }
    } finally {
      stationsQuery.close();
    }

    return listBox.remove(favoriteList.id);
  }

  Future<List<RadioStation>> getStations(int listId) async {
    final objectBox = await ObjectBox.createAsync();
    final favoriteBox = objectBox.store.box<FavoriteStation>();
    final stationBox = objectBox.store.box<RadioStation>();
    final query =
        favoriteBox
            .query(FavoriteStation_.listId.equals(listId))
            .order(FavoriteStation_.createdAt)
            .build();
    try {
      final favorites = query.find();
      final stations = <RadioStation>[];
      final favoritesToUpdate = <FavoriteStation>[];

      for (final favorite in favorites) {
        var station = favorite.station.target;
        if (station == null || station.stationuuid != favorite.stationuuid) {
          station = _findStationByUuid(stationBox, favorite.stationuuid);
          if (station != null) {
            favorite.station.targetId = station.ID;
            favorite.updatedAt = DateTime.now().millisecondsSinceEpoch;
            favoritesToUpdate.add(favorite);
          }
        }

        if (station != null) {
          stations.add(station);
        }
      }

      if (favoritesToUpdate.isNotEmpty) {
        favoriteBox.putMany(favoritesToUpdate);
      }

      return stations;
    } finally {
      query.close();
    }
  }

  Future<Set<int>> getListIdsForStation(String stationUuid) async {
    if (stationUuid.isEmpty) {
      return {};
    }

    final objectBox = await ObjectBox.createAsync();
    final stationBox = objectBox.store.box<FavoriteStation>();
    final query =
        stationBox
            .query(FavoriteStation_.stationuuid.equals(stationUuid))
            .build();
    try {
      return query.find().map((favorite) => favorite.listId).toSet();
    } finally {
      query.close();
    }
  }

  Future<Set<String>> getDefaultFavoriteStationUuids() async {
    final defaultList = await ensureDefaultList();
    final objectBox = await ObjectBox.createAsync();
    final favoriteBox = objectBox.store.box<FavoriteStation>();
    final query =
        favoriteBox
            .query(FavoriteStation_.listId.equals(defaultList.id))
            .build();
    try {
      return query.find().map((favorite) => favorite.stationuuid).toSet();
    } finally {
      query.close();
    }
  }

  Future<void> setStationLists(
    RadioStation station,
    Set<int> selectedListIds,
  ) async {
    if (station.stationuuid.isEmpty) {
      return;
    }

    final lists = await getLists();
    final validListIds = lists.map((list) => list.id).toSet();
    final normalizedListIds =
        selectedListIds.where(validListIds.contains).toSet();

    final objectBox = await ObjectBox.createAsync();
    final favoriteBox = objectBox.store.box<FavoriteStation>();
    final stationBox = objectBox.store.box<RadioStation>();
    objectBox.store.runInTransaction(TxMode.write, () {
      final sourceStation = _resolveSourceStation(stationBox, station);
      final storedStation =
          sourceStation ?? _restoreInactiveStationSnapshot(stationBox, station);
      if (storedStation == null) {
        return;
      }

      final query =
          favoriteBox
              .query(
                FavoriteStation_.stationuuid.equals(storedStation.stationuuid),
              )
              .build();

      final existingByListId = <int, FavoriteStation>{};
      final idsToRemove = <int>[];
      try {
        final existingFavorites = query.find();
        for (final favorite in existingFavorites) {
          final shouldRemove =
              !normalizedListIds.contains(favorite.listId) ||
              !validListIds.contains(favorite.listId) ||
              existingByListId.containsKey(favorite.listId);
          if (shouldRemove) {
            idsToRemove.add(favorite.id);
            continue;
          }

          favorite.updateFromStation(storedStation);
          existingByListId[favorite.listId] = favorite;
        }
      } finally {
        query.close();
      }

      if (idsToRemove.isNotEmpty) {
        favoriteBox.removeMany(idsToRemove);
      }

      for (final favorite in existingByListId.values) {
        favoriteBox.put(favorite);
      }

      for (final listId in normalizedListIds) {
        if (existingByListId.containsKey(listId)) {
          continue;
        }
        favoriteBox.put(
          FavoriteStation.fromRadioStation(listId, storedStation),
        );
      }
    });
  }

  RadioStation? _restoreInactiveStationSnapshot(
    Box<RadioStation> stationBox,
    RadioStation station,
  ) {
    if (station.stationuuid.isEmpty) {
      return null;
    }
    station
      ..ID = 0
      ..isActive = false
      ..syncStateInitialized = true;
    final id = stationBox.put(station);
    station.ID = id;
    return station;
  }

  RadioStation? _resolveSourceStation(
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
    if (stationUuid.isEmpty) {
      return null;
    }

    final query =
        stationBox.query(RadioStation_.stationuuid.equals(stationUuid)).build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }
}
