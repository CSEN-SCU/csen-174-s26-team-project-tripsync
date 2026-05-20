/// At most [maxSendsPerMinute] LLM requests may **start** within each rolling [window]
/// (shared by **Generate description** and **Ask TripSync**). Not a security boundary.
final class LlmChatRateLimiter {
  LlmChatRateLimiter({
    this.maxSendsPerMinute = 3,
    this.window = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxSendsPerMinute;
  final Duration window;
  final DateTime Function() _now;

  final List<DateTime> _sendStarts = [];

  void _prune(DateTime now) {
    _sendStarts.removeWhere((s) => now.difference(s) >= window);
  }

  /// `null` if the user may start another request; otherwise a short UI message.
  String? rejectReason() {
    final now = _now();
    _prune(now);
    if (_sendStarts.length >= maxSendsPerMinute) {
      final oldest = _sendStarts.first;
      final expires = oldest.add(window);
      var wait = expires.difference(now);
      if (wait.isNegative || wait.inMilliseconds == 0) {
        wait = const Duration(seconds: 1);
      }
      final secs = wait.inSeconds.clamp(1, 60);
      return 'Up to $maxSendsPerMinute generations per minute. Try again in about $secs s.';
    }
    return null;
  }

  /// Call when a request **starts** (after [rejectReason] is null), before `await` on the network call.
  void recordSendStarted() {
    final now = _now();
    _prune(now);
    _sendStarts.add(now);
  }
}
