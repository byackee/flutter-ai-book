/// The contract every AI provider must implement.
/// Your UI should never know which provider it's talking to.
/// See Chapter 2 for the full architecture discussion.
library;

import 'chat_message.dart';

abstract class AiService {
  /// Send a message and get a streaming response
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  });

  /// Check if the service is available
  Future<bool> isAvailable();

  /// Get the service name (for logging/debugging)
  String get name;
}

/// Exception thrown by AI services
class AiServiceException implements Exception {
  final String message;
  final int? statusCode;
  final bool isRetryable;
  final Duration? retryAfter;

  const AiServiceException({
    required this.message,
    this.statusCode,
    this.isRetryable = false,
    this.retryAfter,
  });

  @override
  String toString() => 'AiServiceException($statusCode): $message';
}
