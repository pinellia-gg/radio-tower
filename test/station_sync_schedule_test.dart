import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/common/station_sync_schedule.dart';

void main() {
  const schedule = StationSyncSchedule();
  const hour = Duration(hours: 1);
  const now = 1000 * 1000 * 1000;

  test(
    'requires a full sync on the first run after the metadata migration',
    () {
      expect(
        schedule.requiresFullSync(
          storedSchemaVersion: 0,
          lastSuccessfulFullSyncAt: now - hour.inMilliseconds,
          now: now,
        ),
        isTrue,
      );
    },
  );

  test('uses milliseconds for the 48 hour full-sync boundary', () {
    expect(
      schedule.requiresFullSync(
        storedSchemaVersion: StationSyncSchedule.currentSchemaVersion,
        lastSuccessfulFullSyncAt:
            now - StationSyncSchedule.fullSyncInterval.inMilliseconds + 1,
        now: now,
      ),
      isFalse,
    );
    expect(
      schedule.requiresFullSync(
        storedSchemaVersion: StationSyncSchedule.currentSchemaVersion,
        lastSuccessfulFullSyncAt:
            now - StationSyncSchedule.fullSyncInterval.inMilliseconds,
        now: now,
      ),
      isTrue,
    );
  });
}
