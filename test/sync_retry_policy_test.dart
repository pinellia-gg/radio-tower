import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/common/sync_retry_policy.dart';

void main() {
  test('backs off failed runs and caps the retry delay', () {
    final policy = SyncRetryPolicy(
      initialDelay: const Duration(seconds: 2),
      maxDelay: const Duration(seconds: 8),
    );

    expect(policy.nextDelay(), const Duration(seconds: 2));
    expect(policy.nextDelay(), const Duration(seconds: 4));
    expect(policy.nextDelay(), const Duration(seconds: 8));
    expect(policy.nextDelay(), const Duration(seconds: 8));
  });

  test('resets backoff after a successful request', () {
    final policy = SyncRetryPolicy(
      initialDelay: const Duration(seconds: 2),
      maxDelay: const Duration(seconds: 8),
    );

    policy.nextDelay();
    policy.nextDelay();
    policy.reset();

    expect(policy.nextDelay(), const Duration(seconds: 2));
  });
}
