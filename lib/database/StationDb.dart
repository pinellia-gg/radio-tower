import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:radio_tower/database/ObjectBox.dart';
import 'package:lib_common/log/Logger.dart';
import 'package:radio_tower/objectbox.g.dart';

import '../entity/RadioStation.dart';
import '../common/extensions/StringEx.dart';

class StationDb {
  static const String _tag = "StationDB";

  // late final ObjectBox objectBox;
  // late final Box<RadioStation> stationBox;

  StationDb._create() {
    Logger.dLog(_tag, "class _Create called");
  }

  static final StationDb _instance = StationDb._create();

  factory StationDb() {
    return _instance;
  }

  // static StationDb INS() {
  //   return _instance;
  // }

  static StationDb get INS {
    return _instance;
  }

  void test() {}

  Future<void> init() async {
    // objectBox = await ObjectBox.createAsync();
    // stationBox = objectBox.store.box<RadioStation>();
  }

  void updateStations(List<RadioStation> newStations) async {
    var token = RootIsolateToken.instance;

    return await Isolate.run(() async {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

      ObjectBox objectBoxT = await ObjectBox.createAsync();
      Box<RadioStation> stationBox = objectBoxT.store.box<RadioStation>();

      for (var station in newStations) {
        var oldStation =
            stationBox
                .query(RadioStation_.stationuuid.equals(station.stationuuid))
                .build()
                .findFirst();

        station.name = station.name.trim();

        if (station.name.isEmptyOrBlank()) {
          continue;
        }

        station.country = station.country.trim();
        station.tags = station.tags.trim();

        if (oldStation != null) {
          station.ID = oldStation.ID;
          stationBox.put(station);
        } else {
          stationBox.put(station);
        }
      }
    });
  }

  Future<List<RadioStation>> queryStations(
    String filterName,
    String filterCountry,
    String filterLanguage,
    String filterTag,
    int offset,
    int limit,
  ) {
    var token = RootIsolateToken.instance;
    return Isolate.run(() async {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

      ObjectBox objectBoxT = await ObjectBox.createAsync();
      Box<RadioStation> box = objectBoxT.store.box<RadioStation>();
      Condition<RadioStation>? queryCondition;

      if (filterName.isNotEmpty) {
        queryCondition = RadioStation_.name.contains(
          filterName,
          caseSensitive: false,
        );
      }

      if (filterCountry.isNotEmpty) {
        queryCondition =
            queryCondition == null
                ? RadioStation_.country.contains(
                  filterCountry,
                  caseSensitive: false,
                )
                : queryCondition.and(
                  RadioStation_.country.contains(filterCountry),
                );
      }

      if (filterLanguage.isNotEmpty) {
        queryCondition =
            queryCondition == null
                ? RadioStation_.language.contains(
                  filterLanguage,
                  caseSensitive: false,
                )
                : queryCondition.and(
                  RadioStation_.language.contains(
                    filterLanguage,
                    caseSensitive: false,
                  ),
                );
      }

      if (filterTag.isNotEmpty) {
        queryCondition =
            queryCondition == null
                ? RadioStation_.tags.contains(filterTag, caseSensitive: false)
                : queryCondition.and(
                  RadioStation_.tags.contains(filterTag, caseSensitive: false),
                );
      }

      Query<RadioStation> query =
          box.query(queryCondition).order(RadioStation_.name).build();
      query
        ..offset = offset
        ..limit = limit;

      List<RadioStation> resultStations = await query.findAsync();

      resultStations.removeWhere((station) {
        return station.name.isEmptyOrBlank();
      });

      return query.findAsync();
    });
  }

  Future<List<String>> queryDistinctCountry() async {
    List<String> countrys = await queryProperty(
      RadioStation_.country,
      distinct: true,
    );

    countrys.removeWhere((str) => str.isEmptyOrBlank());
    countrys.sort((a, b) => a.compareTo(b));

    return countrys;
  }

  Future<List<String>> queryDistinctLanguage() async {
    List<String> lans = await queryProperty(
      RadioStation_.language,
      distinct: true,
    );

    List<String> result = await Isolate.run(() async {
      var lanSet = HashSet<String>();
      var filterSet = HashSet<String>();

      for (String lan in lans) {
        if (lan.contains(",")) {
          List<String> lanArr = lan.split(",");
          for (String l in lanArr) {
            lanSet.add(l);
          }
        } else if (lan.isNotBlank()) {
          lanSet.add(lan);
        }
      }

      for (String lan in lanSet) {
        String fixLan = "";
        if (lan.startsWith("#")) {
          fixLan = lan.substring(1);
        } else {
          fixLan = lan;
        }

        if (fixLan.startsWith("+") || fixLan.startsWith("[0 - 9]")) {
          //跳过不正常的语言
          continue;
        }

        if (fixLan.isNotEmptyOrBlank()) {
          filterSet.add(fixLan.firstLetterToUpper());
        }
      }

      List<String> sortedList = filterSet.toList();
      sortedList.sort((a, b) => a.compareTo(b));

      return sortedList;
    });

    return result;
  }

  Future<List<String>> queryDistinctTag() async {
    final tags = await queryProperty(RadioStation_.tags, distinct: true);

    return await Isolate.run(() async {
      final tagSet = HashSet<String>();
      final filterSet = HashSet<String>();

      for (String tag in tags) {
        if (tag.contains(",")) {
          final lanArr = tag.split(",");
          for (String l in lanArr) {
            tagSet.add(l.replaceFirst("\"", " ").trim());
          }
        } else if (tag.isNotEmptyOrBlank()) {
          tagSet.add(tag.replaceFirst("\"", " ").trim());
        }
      }

      for (String tag in tagSet) {
        var fixTag = "";
        if (tag.startsWith("#")) {
          fixTag = tag.replaceFirst("^#+", "");
        } else {
          fixTag = tag;
        }

        if (fixTag.startsWith(".") ||
            fixTag.startsWith("'") ||
            fixTag.startsWith("-")) {
          continue;
        }

        if (fixTag.length >= 2) {
          filterSet.add(fixTag.firstLetterToUpper());
        }
      }

      List<String> sortedList = filterSet.toList();
      sortedList.sort((a, b) => a.compareTo(b));

      return sortedList;
    });
  }

  Future<List<String>> queryProperty(
    QueryStringProperty<RadioStation> property, {
    bool distinct = false,
  }) async {
    var token = RootIsolateToken.instance;

    return await Isolate.run(() async {
      // WidgetsFlutterBinding.ensureInitialized(); // Often a good general initializer
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

      ObjectBox objectBoxT = await ObjectBox.createAsync();
      Box<RadioStation> box = objectBoxT.store.box<RadioStation>();

      // Box<RadioStation> box = stationBox;

      final query = box.query().build();
      final propertyQuery = query.property(property);
      propertyQuery.distinct = distinct;

      List<String> result = propertyQuery.find();
      propertyQuery.close();

      return result;
    });
  }
}
