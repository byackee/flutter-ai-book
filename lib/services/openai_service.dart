/// Full OpenAI integration with streaming SSE parsing.
/// Handles partial chunks, malformed JSON, and all edge cases.
/// See Chapter 4 for the complete walkthrough.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

class OpenAiService implements AiService {
  final Dio _dio;
  final String _apiKey;
  final String _defaultModel;

  OpenAiService({
    required String apiKey,
    String baseUrl = 'https://api.openai.com/v1',
    String defaultModel = 'gpt-4o',
    Duration timeout = const Duration(seconds: 60),
  })  : _apiKey = apiKey,
        _defaultModel = defaultModel,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: timeout,
          receiveTimeout: const Duration(seconds: 120),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ));

  @override
  String get name => 'OpenAI';

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _dio.get('/models');
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
    final response = await _dio.post<ResponseBody>(
      '/chat/completions',
      data: {
        'model': model ?? _defaultModel,
        'messages': messages.map((m) => m.toApiJson()).toList(),
        'temperature': temperature ?? 0.7,
        'stream': true,
      },
      options: Options(responseType: ResponseType.stream),
    );

    yield* parseSseStream(response.data!.stream);
  }

  /// Parse Server-Sent Events stream with proper buffer handling.
  /// This handles partial chunks split across TCP packets — the gotcha
  /// that most tutorials get wrong.
  static Stream<String> parseSseStream(Stream<Uint8List> byteStream) async* {
    String buffer = '';

    await for (final chunk in byteStream) {
      buffer += utf8.decode(chunk);

      // Split on newlines, keeping incomplete lines in buffer
      final lines = buffer.split('\n');
      buffer = lines.removeLast(); // Keep incomplete line

      for (final line in lines) {
        final trimmed = line.trim();

        if (trimmed.isEmpty) continue;
        if (trimmed == 'data: [DONE]') return;
        if (!trimmed.startsWith('data: ')) continue;

        final jsonStr = trimmed.substring(6);
        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final choices = json['choices'] as List;
          if (choices.isEmpty) continue;

          final delta = choices[0]['delta'] as Map<String, dynamic>;
          final content = delta['content'] as String?;

          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Malformed JSON — skip this chunk
          continue;
        }
      }
    }

    // Process any remaining buffer
    if (buffer.trim().isNotEmpty && buffer.trim().startsWith('data: ')) {
      final jsonStr = buffer.trim().substring(6);
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final content =
            json['choices']?[0]?['delta']?['content'] as String?;
        if (content != null) yield content;
      } catch (_) {}
    }
  }
}
