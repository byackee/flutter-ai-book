/// Anthropic Claude integration with streaming.
/// Note: different headers, different SSE event types, system message separated.
/// See Chapter 4 for details.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

class AnthropicService implements AiService {
  final Dio _dio;
  final String _defaultModel;

  AnthropicService({
    required String apiKey,
    String baseUrl = 'https://api.anthropic.com',
    String defaultModel = 'claude-sonnet-4-20250514',
    Duration timeout = const Duration(seconds: 60),
  })  : _defaultModel = defaultModel,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: timeout,
          receiveTimeout: const Duration(seconds: 120),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ));

  @override
  String get name => 'Anthropic';

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _dio.post('/v1/messages', data: {
        'model': _defaultModel,
        'max_tokens': 1,
        'messages': [
          {'role': 'user', 'content': 'hi'}
        ],
      });
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    // Anthropic separates system messages
    final systemMsg = messages
        .where((m) => m.role == MessageRole.system)
        .map((m) => m.content)
        .join('\n');

    final chatMessages = messages
        .where((m) => m.role != MessageRole.system)
        .map((m) => {
              return {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              };
            })
        .toList();

    final body = <String, dynamic>{
      'model': model ?? _defaultModel,
      'max_tokens': 4096,
      'messages': chatMessages,
      'stream': true,
    };

    if (systemMsg.isNotEmpty) body['system'] = systemMsg;
    if (temperature != null) body['temperature'] = temperature;

    final response = await _dio.post<ResponseBody>(
      '/v1/messages',
      data: body,
      options: Options(responseType: ResponseType.stream),
    );

    yield* _parseAnthropicSse(response.data!.stream);
  }

  Stream<String> _parseAnthropicSse(Stream<Uint8List> byteStream) async* {
    String buffer = '';
    String currentEvent = '';

    await for (final chunk in byteStream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();

        if (trimmed.isEmpty) {
          currentEvent = '';
          continue;
        }

        if (trimmed.startsWith('event: ')) {
          currentEvent = trimmed.substring(7);
          continue;
        }

        if (!trimmed.startsWith('data: ')) continue;
        if (currentEvent != 'content_block_delta') continue;

        final jsonStr = trimmed.substring(6);
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          final text = delta['text'] as String?;
          if (text != null && text.isNotEmpty) {
            yield text;
          }
        } catch (_) {
          continue;
        }
      }
    }
  }
}
