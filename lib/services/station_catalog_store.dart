import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/repository/station_repository.dart';

abstract interface class StationCatalogStore {
  Future<void> init();
  Future<void> activateLegacyStationsForSyncMigration();
  Future<void> updateStations(List<RadioStation> stations);
  Future<void> updateFullSyncStations(
    List<RadioStation> stations,
    int generation,
  );
  Future<void> finalizeFullSync(int generation);
  Future<List<RadioStation>> queryStations(StationQueryParams params);
  Future<List<String>> queryDistinctCountry();
  Future<List<String>> queryDistinctLanguage();
  Future<List<String>> queryDistinctTag();
}
