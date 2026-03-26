/// AI Gateway client — calls your self-hosted gateway (OpenClaw/LiteLLM).
/// Nearly identical to OpenAiService because the gateway speaks the same protocol.
/// The key difference: no API key in the client, model names can be aliases.
/// See Chapter 6 for gateway setup and configuration.
library;

import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';
import 'openai_service.dart';

class GatewayAiService implements AiService {
  final Dio _dio;
  final String _defaultModel;

  GatewayAiService({
    required String gatewayUrl,
    String? authToken,
    String defaultModel = 'smart',
  })  : _defaultModel = defaultModel,
        _dio = Dio(BaseOptions(
          baseUrl: gatewayUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 120),
          headers: {
            'Content-Type': 'application/json',
            if (authToken != null) 'Authorization': 'Bearer $authToken',
          },
        ));

  @override
  String get name => 'Gateway';

  @override
  Future<bool> isAvailable() async {
    try {
      final response = await _dio.get('/v1/models');
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
      '/v1/chat/completions',
      data: {
        'model': model ?? _defaultModel,
        'messages': messages.map((m) => m.toApiJson()).toList(),
        'temperature': temperature ?? 0.7,
        'stream': true,
      },
      options: Options(responseType: ResponseType.stream),
    );

    // Same SSE parser as OpenAI — the gateway speaks the same protocol
    yield* OpenAiService.parseSseStream(response.data!.stream);
  }
}
