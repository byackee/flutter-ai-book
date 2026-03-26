/// Response caching and content moderation for production.
/// See Chapter 10 for the full production stack.
library;

import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

// ──────────────────────────────────────────────
// Cached AI Service
// ──────────────────────────────────────────────

class _CacheEntry {
  final String response;
  final DateTime timestamp;
  _CacheEntry({required this.response, required this.timestamp});
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(timestamp) > ttl;
}

class CachedAiService implements AiService {
  final AiService _inner;
  final Map<String, _CacheEntry> _cache = {};
  final Duration ttl;
  final int maxEntries;

  CachedAiService(this._inner,
      {this.ttl = const Duration(hours: 1), this.maxEntries = 500});

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    final key = _buildKey(messages, model);
    final cached = _cache[key];

    if (cached != null && !cached.isExpired(ttl)) {
      yield cached.response;
      return;
    }

    final buffer = StringBuffer();
    await for (final chunk in _inner.chat(
      messages: messages,
      model: model,
      temperature: temperature,
    )) {
      buffer.write(chunk);
      yield chunk;
    }

    if (_cache.length >= maxEntries) {
      final oldest = _cache.entries
          .reduce((a, b) =>
              a.value.timestamp.isBefore(b.value.timestamp) ? a : b);
      _cache.remove(oldest.key);
    }

    _cache[key] = _CacheEntry(
      response: buffer.toString(),
      timestamp: DateTime.now(),
    );
  }

  String _buildKey(List<ChatMessage> messages, String? model) {
    final content =
        messages.map((m) => '${m.role.name}:${m.content}').join('|');
    return '${model ?? "default"}:$content'.hashCode.toString();
  }

  @override
  String get name => '${_inner.name}(cached)';
  @override
  Future<bool> isAvailable() => _inner.isAvailable();
}

// ──────────────────────────────────────────────
// Content Moderation
// ──────────────────────────────────────────────

class ModerationResult {
  final bool flagged;
  final Map<String, bool> categories;
  final Map<String, double> scores;
  const ModerationResult(
      {required this.flagged,
      required this.categories,
      required this.scores});
}

class ModerationService {
  final Dio _dio;

  ModerationService({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.openai.com/v1',
          headers: {'Authorization': 'Bearer $apiKey'},
        ));

  Future<ModerationResult> check(String text) async {
    final response =
        await _dio.post('/moderations', data: {'input': text});
    final result = response.data['results'][0];
    return ModerationResult(
      flagged: result['flagged'] as bool,
      categories: Map<String, bool>.from(result['categories']),
      scores: Map<String, double>.from(
        (result['category_scores'] as Map)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
      ),
    );
  }
}

class ModeratedAiService implements AiService {
  final AiService _inner;
  final ModerationService _moderation;

  ModeratedAiService(this._inner, this._moderation);

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    final lastUser =
        messages.lastWhere((m) => m.role == MessageRole.user);
    final result = await _moderation.check(lastUser.content);
    if (result.flagged) {
      yield "I can't help with that request. Please rephrase your message.";
      return;
    }
    yield* _inner.chat(
        messages: messages, model: model, temperature: temperature);
  }

  @override
  String get name => '${_inner.name}(moderated)';
  @override
  Future<bool> isAvailable() => _inner.isAvailable();
}

// ──────────────────────────────────────────────
// Resilient AI Service (graceful degradation)
// ──────────────────────────────────────────────

class ResilientAiService implements AiService {
  final AiService _primary;
  final String _fallbackMessage;

  ResilientAiService(this._primary,
      {String fallbackMessage =
          'AI features are temporarily unavailable. Please try again later.'})
      : _fallbackMessage = fallbackMessage;

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    try {
      yield* _primary.chat(
          messages: messages, model: model, temperature: temperature);
    } catch (e) {
      yield _fallbackMessage;
    }
  }

  @override
  String get name => _primary.name;
  @override
  Future<bool> isAvailable() => _primary.isAvailable();
}
