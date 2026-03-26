/// Local LLM integration via Ollama.
/// Uses native /api/chat endpoint (more reliable than OpenAI-compat layer).
/// See Chapter 5 for setup, model selection, and hybrid strategies.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

class OllamaService implements AiService {
  final Dio _dio;
  final String _defaultModel;

  OllamaService({
    String baseUrl = 'http://localhost:11434',
    String defaultModel = 'qwen2.5:14b',
    Duration timeout = const Duration(seconds: 300),
  })  : _defaultModel = defaultModel,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: timeout,
          headers: {'Content-Type': 'application/json'},
        ));

  @override
  String get name => 'Ollama($_defaultModel)';

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _dio.get('/api/tags');
      if (response.statusCode != 200) return false;
      final models = response.data['models'] as List;
      return models.any(
        (m) => (m['name'] as String).startsWith(
          _defaultModel.split(':').first,
        ),
      );
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
      '/api/chat',
      data: {
        'model': model ?? _defaultModel,
        'messages': messages.map((m) => m.toApiJson()).toList(),
        'options': {
          if (temperature != null) 'temperature': temperature,
          'num_predict': 2048,
        },
        'stream': true,
      },
      options: Options(responseType: ResponseType.stream),
    );

    yield* _parseOllamaStream(response.data!.stream);
  }

  /// Ollama uses NDJSON, not SSE.
  Stream<String> _parseOllamaStream(Stream<Uint8List> byteStream) async* {
    String buffer = '';

    await for (final chunk in byteStream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>;
          if (json['done'] == true) return;

          final message = json['message'] as Map<String, dynamic>?;
          final content = message?['content'] as String?;

          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          continue;
        }
      }
    }
  }
}
