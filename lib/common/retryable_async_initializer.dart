import 'dart:async';

/// Shares an asynchronous initialization operation and allows a later retry
/// when the current attempt fails.
class RetryableAsyncInitializer<T extends Object> {
  T? _value;
  Future<T>? _inFlight;

  Future<T> getOrCreate(Future<T> Function() create) {
    final value = _value;
    if (value != null) {
      return Future.value(value);
    }

    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<T> future;
    future = Future<T>.sync(create)
        .then((value) {
          _value = value;
          return value;
        })
        .whenComplete(() {
          if (identical(_inFlight, future)) {
            _inFlight = null;
          }
        });
    _inFlight = future;
    return future;
  }
}

/// Invalidates asynchronous work that belongs to an older lifecycle.
class LifecycleGeneration {
  int _current = 0;

  int begin() => ++_current;

  void invalidate() {
    _current++;
  }

  bool isCurrent(int generation) => generation == _current;
}

/// Tracks worker requests so a lifecycle transition can fail every waiter.
class PendingRequestRegistry {
  final Map<int, Completer<Object?>> _requests = {};

  int get length => _requests.length;

  Completer<Object?> add(int requestId) {
    if (_requests.containsKey(requestId)) {
      throw StateError('Duplicate request id: $requestId');
    }
    final completer = Completer<Object?>();
    _requests[requestId] = completer;
    return completer;
  }

  Completer<Object?>? take(int requestId) => _requests.remove(requestId);

  void failAll(Object error, StackTrace stackTrace) {
    final pending = _requests.values.toList(growable: false);
    _requests.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }
}
