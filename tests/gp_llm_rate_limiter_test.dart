import 'package:llm_integration/llm_integration.dart';
import 'package:test/test.dart';

void main() {
  test('rate limiter: allows first three sends within the window', () {
    var t = DateTime.utc(2025, 1, 1, 12);
    final lim = LlmChatRateLimiter(now: () => t);
    expect(lim.rejectReason(), isNull);
    lim.recordSendStarted();
    expect(lim.rejectReason(), isNull);
    lim.recordSendStarted();
    expect(lim.rejectReason(), isNull);
    lim.recordSendStarted();
    expect(lim.rejectReason(), isNotNull);
    expect(lim.rejectReason(), contains('3'));
  });

  test('rate limiter: fourth send allowed after rolling minute clears oldest', () {
    var t = DateTime.utc(2025, 1, 1, 12);
    final lim = LlmChatRateLimiter(now: () => t);
    lim.recordSendStarted();
    lim.recordSendStarted();
    lim.recordSendStarted();
    expect(lim.rejectReason(), isNotNull);

    t = t.add(const Duration(seconds: 61));
    expect(lim.rejectReason(), isNull);
    lim.recordSendStarted();
    expect(lim.rejectReason(), isNull);
  });
}
