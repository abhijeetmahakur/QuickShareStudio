/// Sender-side limit on wrong codes. PeerJS cannot tell the receiver that someone guessed a
/// code that does not exist, so the sender throttles itself: after [maxAttempts] wrong codes
/// it locks for [lockout], doubling each time it locks again.
class AttemptLimiter {
  AttemptLimiter({this.maxAttempts = 5, this.lockout = const Duration(minutes: 1), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final Duration lockout;
  final DateTime Function() _clock;

  int _failures = 0;
  int _lockouts = 0;
  DateTime? _lockedUntil;

  bool get isLocked {
    final until = _lockedUntil;
    return until != null && _clock().isBefore(until);
  }

  Duration get lockRemaining {
    final until = _lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_clock());
    return left.isNegative ? Duration.zero : left;
  }

  int get remainingAttempts => isLocked ? 0 : maxAttempts - _failures;

  /// Records a wrong code. Returns true if this locked the limiter.
  bool recordFailure() {
    if (isLocked) return true;
    _failures++;
    if (_failures < maxAttempts) return false;
    _failures = 0;
    _lockedUntil = _clock().add(lockout * (1 << _lockouts.clamp(0, 5)));
    _lockouts++;
    return true;
  }

  void recordSuccess() {
    _failures = 0;
    _lockouts = 0;
    _lockedUntil = null;
  }
}
