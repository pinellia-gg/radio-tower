import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/common/fetch_retry_state.dart';

void main() {
  test('ends a failed run without treating it as a completed sync', () {
    final state = FetchRetryState(maxFailures: 3);

    state.start();
    for (var attempt = 0; attempt < 4; attempt++) {
      state.recordFailure();
    }

    expect(state.isTerminal, isTrue);
    expect(state.isCompleted, isFalse);
    expect(state.shouldContinue, isFalse);

    state.start();
    expect(state.shouldContinue, isTrue);
    expect(state.failureCount, 0);
  });

  test('only marks a run completed when the caller completes it', () {
    final state = FetchRetryState(maxFailures: 1);

    state.start();
    state.recordSuccess();
    expect(state.isCompleted, isFalse);

    state.markCompleted();
    expect(state.isCompleted, isTrue);
  });
}
