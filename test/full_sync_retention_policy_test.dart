import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/services/full_sync_retention_policy.dart';

void main() {
  const policy = FullSyncRetentionPolicy();

  test(
    'retains a station missing from only one successful full generation',
    () {
      expect(
        policy.resolve(
          currentGeneration: 5,
          lastSeenGeneration: 4,
          isFavorite: false,
        ),
        FullSyncRetentionAction.retain,
      );
    },
  );

  test(
    'removes a non-favorite missing from two successful full generations',
    () {
      expect(
        policy.resolve(
          currentGeneration: 5,
          lastSeenGeneration: 3,
          isFavorite: false,
        ),
        FullSyncRetentionAction.remove,
      );
    },
  );

  test('keeps a favorite snapshot but marks it inactive after two misses', () {
    expect(
      policy.resolve(
        currentGeneration: 5,
        lastSeenGeneration: 3,
        isFavorite: true,
      ),
      FullSyncRetentionAction.deactivate,
    );
  });
}
