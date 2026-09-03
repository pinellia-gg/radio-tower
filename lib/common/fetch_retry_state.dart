enum FetchAttemptStatus { completed, running, failed }

class FetchRetryState {
  FetchRetryState({required this.maxFailures});

  final int maxFailures;
  FetchAttemptStatus _status = FetchAttemptStatus.completed;
  int _failureCount = 0;

  bool get isTerminal => _status != FetchAttemptStatus.running;
  bool get isCompleted => _status == FetchAttemptStatus.completed;
  bool get shouldContinue => _status == FetchAttemptStatus.running;
  int get failureCount => _failureCount;

  void start() {
    _status = FetchAttemptStatus.running;
    _failureCount = 0;
  }

  void recordSuccess() {
    if (_status == FetchAttemptStatus.running) {
      _failureCount = 0;
    }
  }

  void recordFailure() {
    if (_status != FetchAttemptStatus.running) {
      return;
    }
    _failureCount++;
    if (_failureCount > maxFailures) {
      _status = FetchAttemptStatus.failed;
    }
  }

  void markCompleted() {
    _status = FetchAttemptStatus.completed;
    _failureCount = 0;
  }

  void markFailed() {
    _status = FetchAttemptStatus.failed;
  }
}
