/// Wraps any AiService with automatic retry and exponential backoff.
/// See Chapter 4 for error handling details.
library;

import 'dart:math' as math;
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

class RetryAiService implements AiService {
  final AiService _inner;
  final int maxRetries;

  RetryAiService(this._inner, {this.maxRetries = 3});

  @override
  String get name => '${_inner.name}(retry)';

  @override
  Future<bool> isAvailable() => _inner.isAvailable();

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    int attempt = 0;

    while (true) {
      try {
        await for (final chunk in _inner.chat(
          messages: messages,
          model: model,
          temperature: temperature,
        )) {
          yield chunk;
        }
        return; // Success
      } on DioException catch (e) {
        attempt++;
        final statusCode = e.response?.statusCode;
        final isRetryable = statusCode == 429 ||
            statusCode == 500 ||
            statusCode == 502 ||
            statusCode == 503;

        if (!isRetryable || attempt >= maxRetries) {
          throw AiServiceException(
            message: _extractErrorMessage(e) ?? 'Unknown error',
            statusCode: statusCode,
            isRetryable: isRetryable,
          );
        }

        // Exponential backoff: 1s, 2s, 4s...
        final delay = Duration(seconds: math.pow(2, attempt).toInt());
        await Future.delayed(delay);
      }
    }
  }

  String? _extractErrorMessage(DioException e) {
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      return body['error']?['message'] as String? ??
          body['message'] as String?;
    }
    if (body is String) return body;
    return null;
  }
}
