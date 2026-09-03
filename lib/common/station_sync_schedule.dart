class StationSyncSchedule {
  static const int currentSchemaVersion = 2;
  static const Duration fullSyncInterval = Duration(hours: 48);

  const StationSyncSchedule();

  bool requiresFullSync({
    required int storedSchemaVersion,
    required int lastSuccessfulFullSyncAt,
    required int now,
  }) {
    if (storedSchemaVersion != currentSchemaVersion ||
        lastSuccessfulFullSyncAt <= 0) {
      return true;
    }

    return now - lastSuccessfulFullSyncAt >= fullSyncInterval.inMilliseconds;
  }
}
