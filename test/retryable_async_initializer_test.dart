import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/common/retryable_async_initializer.dart';

void main() {
  test(
    'shares concurrent initialization and caches a successful result',
    () async {
      final initializer = RetryableAsyncInitializer<Object>();
      final result = Object();
      var calls = 0;
      final gate = Completer<Object>();

      Future<Object> create() {
        calls++;
        return gate.future;
      }

      final first = initializer.getOrCreate(create);
      final second = initializer.getOrCreate(create);
      expect(calls, 1);

      gate.complete(result);
      expect(await first, same(result));
      expect(await second, same(result));
      expect(await initializer.getOrCreate(create), same(result));
      expect(calls, 1);
    },
  );

  test('allows a retry after a failed initialization', () async {
    final initializer = RetryableAsyncInitializer<Object>();
    var calls = 0;

    Future<Object> create() async {
      calls++;
      if (calls == 1) {
        throw StateError('first attempt failed');
      }
      return Object();
    }

    await expectLater(
      initializer.getOrCreate(create),
      throwsA(isA<StateError>()),
    );
    final value = await initializer.getOrCreate(create);

    expect(value, isA<Object>());
    expect(calls, 2);
  });

  test('invalidates stale lifecycle work after dispose or restart', () {
    final lifecycle = LifecycleGeneration();
    final first = lifecycle.begin();
    expect(lifecycle.isCurrent(first), isTrue);

    lifecycle.invalidate();
    expect(lifecycle.isCurrent(first), isFalse);

    final second = lifecycle.begin();
    expect(lifecycle.isCurrent(second), isTrue);
    expect(lifecycle.isCurrent(first), isFalse);
  });

  test(
    'fails all pending worker requests during a lifecycle transition',
    () async {
      final requests = PendingRequestRegistry();
      final first = requests.add(1);
      final second = requests.add(2);
      final error = StateError('worker stopped');
      final firstExpectation = expectLater(first.future, throwsA(same(error)));
      final secondExpectation = expectLater(
        second.future,
        throwsA(same(error)),
      );

      requests.failAll(error, StackTrace.current);

      await Future.wait([firstExpectation, secondExpectation]);
      expect(requests.length, 0);
    },
  );
}
