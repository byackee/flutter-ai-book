/// Consistent message model that works across all providers.
/// See Chapter 2 for the base model and Chapter 3 for UI extensions.
library;

enum MessageRole { system, user, assistant }

enum MessageStatus { sending, streaming, complete, error }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final String? model;
  final Duration? responseTime;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.complete,
    this.model,
    this.responseTime,
  });

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    Duration? responseTime,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      status: status ?? this.status,
      model: model,
      responseTime: responseTime ?? this.responseTime,
    );
  }

  Map<String, dynamic> toApiJson() => {
        'role': role.name,
        'content': content,
      };

  factory ChatMessage.user(String content) => ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: MessageRole.user,
        content: content,
        timestamp: DateTime.now(),
      );

  factory ChatMessage.system(String content) => ChatMessage(
        id: 'system',
        role: MessageRole.system,
        content: content,
        timestamp: DateTime.now(),
      );
}
