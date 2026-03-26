/// Client-side rate limiter to prevent UI from spamming requests.
/// See Chapter 10 for server-side rate limiting with nginx/gateway.
library;

import 'dart:collection';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

class RateLimiter {
  final int maxRequests;
  final Duration window;
  final Queue<DateTime> _timestamps = Queue();

  RateLimiter({this.maxRequests = 20, this.window = const Duration(minutes: 1)});

  bool get canProceed {
    _cleanup();
    return _timestamps.length < maxRequests;
  }

  void record() => _timestamps.add(DateTime.now());

  Duration? get retryAfter {
    if (canProceed) return null;
    final oldest = _timestamps.first;
    return window - DateTime.now().difference(oldest);
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(window);
    while (_timestamps.isNotEmpty && _timestamps.first.isBefore(cutoff)) {
      _timestamps.removeFirst();
    }
  }
}

class RateLimitedAiService implements AiService {
  final AiService _inner;
  final RateLimiter _limiter;

  RateLimitedAiService(this._inner, {int maxPerMinute = 20})
      : _limiter = RateLimiter(maxRequests: maxPerMinute);

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    if (!_limiter.canProceed) {
      throw AiServiceException(
        message: 'Rate limit exceeded. Try again in '
            '${_limiter.retryAfter?.inSeconds}s.',
        isRetryable: true,
        retryAfter: _limiter.retryAfter,
      );
    }
    _limiter.record();
    yield* _inner.chat(messages: messages, model: model, temperature: temperature);
  }

  @override
  String get name => _inner.name;
  @override
  Future<bool> isAvailable() => _inner.isAvailable();
}
