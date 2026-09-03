class SyncRetryPolicy {
  SyncRetryPolicy({required this.initialDelay, required this.maxDelay})
    : assert(initialDelay > Duration.zero),
      assert(maxDelay >= initialDelay);

  final Duration initialDelay;
  final Duration maxDelay;
  int _consecutiveFailures = 0;

  Duration nextDelay() {
    final shift = _consecutiveFailures.clamp(0, 20);
    final multiplier = 1 << shift;
    final delay = initialDelay * multiplier;
    _consecutiveFailures++;
    return delay > maxDelay ? maxDelay : delay;
  }

  void reset() {
    _consecutiveFailures = 0;
  }
}
