import 'package:flutter/foundation.dart';
import 'package:radio_tower/database/RecentPlayDb.dart';
import 'package:radio_tower/entity/RadioStation.dart';

class RecentPlayModel extends ChangeNotifier {
  RecentPlayModel({RecentPlayDb? database}) : _database = database ?? RecentPlayDb() {
    reload();
  }

  final RecentPlayDb _database;
  bool _isLoading = false;
  List<RadioStation> _stations = const [];

  bool get isLoading => _isLoading;
  List<RadioStation> get stations => List.unmodifiable(_stations);

  Future<void> recordStation(RadioStation station) async {
    await _database.recordStation(station);
    await reload();
  }

  Future<void> reload() async {
    _isLoading = true;
    notifyListeners();
    try {
      _stations = await _database.getStations();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clear() async {
    await _database.clear();
    await reload();
  }
}
