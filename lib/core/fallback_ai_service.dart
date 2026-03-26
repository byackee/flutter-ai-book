/// Tries providers in order until one succeeds.
/// OpenAI down? Anthropic takes over. No internet? Ollama kicks in.
/// See Chapter 2 for architecture discussion.
library;

import 'package:flutter/foundation.dart';
import 'ai_service.dart';
import 'chat_message.dart';

class FallbackAiService implements AiService {
  final List<AiService> providers;

  FallbackAiService(this.providers);

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    for (final provider in providers) {
      try {
        if (!await provider.isAvailable()) continue;

        await for (final chunk in provider.chat(
          messages: messages,
          model: model,
          temperature: temperature,
        )) {
          yield chunk;
        }
        return; // Success — stop trying other providers
      } catch (e) {
        debugPrint('${provider.name} failed: $e');
        continue; // Try next provider
      }
    }
    throw AiServiceException(message: 'All providers failed');
  }

  @override
  String get name =>
      'Fallback(${providers.map((p) => p.name).join(' → ')})';

  @override
  Future<bool> isAvailable() async {
    for (final provider in providers) {
      if (await provider.isAvailable()) return true;
    }
    return false;
  }
}
