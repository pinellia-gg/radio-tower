enum FullSyncRetentionAction { retain, deactivate, remove }

class FullSyncRetentionPolicy {
  const FullSyncRetentionPolicy();

  FullSyncRetentionAction resolve({
    required int currentGeneration,
    required int lastSeenGeneration,
    required bool isFavorite,
  }) {
    if (currentGeneration - lastSeenGeneration < 2) {
      return FullSyncRetentionAction.retain;
    }
    return isFavorite
        ? FullSyncRetentionAction.deactivate
        : FullSyncRetentionAction.remove;
  }
}
