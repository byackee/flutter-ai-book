/// Voice assistant: STT → LLM → TTS pipeline.
/// Includes streaming TTS (speak while generating).
/// See Chapter 9 for the full implementation with UI.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

// ──────────────────────────────────────────────
// Speech-to-Text (Cloud: Whisper)
// ──────────────────────────────────────────────

class WhisperSttService {
  final Dio _dio;

  WhisperSttService({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.openai.com/v1',
          headers: {'Authorization': 'Bearer $apiKey'},
        ));

  Future<String> transcribe({
    required Uint8List audioBytes,
    String filename = 'audio.m4a',
    String language = 'en',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(audioBytes, filename: filename),
      'model': 'whisper-1',
      'language': language,
      'response_format': 'text',
    });

    final response = await _dio.post('/audio/transcriptions', data: formData);
    return response.data as String;
  }
}

// ──────────────────────────────────────────────
// Text-to-Speech (Cloud: OpenAI)
// ──────────────────────────────────────────────

enum TtsVoice {
  alloy('alloy'),
  echo('echo'),
  fable('fable'),
  onyx('onyx'),
  nova('nova'),
  shimmer('shimmer');

  final String value;
  const TtsVoice(this.value);
}

class OpenAiTtsService {
  final Dio _dio;

  OpenAiTtsService({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.openai.com/v1',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ));

  Future<Uint8List> synthesize({
    required String text,
    TtsVoice voice = TtsVoice.alloy,
    double speed = 1.0,
  }) async {
    final response = await _dio.post<List<int>>(
      '/audio/speech',
      data: {
        'model': 'tts-1',
        'input': text,
        'voice': voice.value,
        'speed': speed,
        'response_format': 'aac',
      },
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }
}

// ──────────────────────────────────────────────
// Voice Assistant Orchestrator
// ──────────────────────────────────────────────

enum VoiceAssistantState { idle, listening, thinking, speaking, error }

class VoiceInteraction {
  final String userText;
  final String assistantText;
  final DateTime timestamp;

  const VoiceInteraction({
    required this.userText,
    required this.assistantText,
    required this.timestamp,
  });

  factory VoiceInteraction.empty() => VoiceInteraction(
        userText: '',
        assistantText: '',
        timestamp: DateTime.now(),
      );

  bool get isEmpty => userText.isEmpty;
}

/// Chains STT → LLM → TTS in a single interaction.
/// For the full implementation with on-device STT/TTS and UI,
/// see Chapter 9 in the book.
class VoiceAssistantCore {
  final AiService ai;
  final _stateController = StreamController<VoiceAssistantState>.broadcast();

  Stream<VoiceAssistantState> get stateStream => _stateController.stream;
  VoiceAssistantState _state = VoiceAssistantState.idle;

  VoiceAssistantCore({required this.ai});

  /// Run the LLM part of the pipeline (STT and TTS are platform-specific)
  Future<String> think({required List<ChatMessage> messages}) async {
    _setState(VoiceAssistantState.thinking);
    final buffer = StringBuffer();
    await for (final chunk in ai.chat(messages: messages)) {
      buffer.write(chunk);
    }
    _setState(VoiceAssistantState.idle);
    return buffer.toString();
  }

  void _setState(VoiceAssistantState state) {
    _state = state;
    _stateController.add(state);
  }

  VoiceAssistantState get state => _state;

  void dispose() {
    _stateController.close();
  }
}

// ──────────────────────────────────────────────
// Streaming TTS: speak while generating
// ──────────────────────────────────────────────

/// Buffers LLM tokens and triggers TTS sentence by sentence.
/// Pass a speakFn that handles the actual speech.
class StreamingTtsBuffer {
  final Future<void> Function(String sentence) speakFn;
  final _buffer = StringBuffer();
  final _sentenceQueue = Queue<String>();
  bool _isSpeaking = false;

  StreamingTtsBuffer({required this.speakFn});

  void addToken(String token) {
    _buffer.write(token);

    final text = _buffer.toString();
    final sentenceEnd = RegExp(r'[.!?\n]\s');
    final match = sentenceEnd.firstMatch(text);

    if (match != null) {
      final sentence = text.substring(0, match.end).trim();
      _buffer.clear();
      _buffer.write(text.substring(match.end));

      if (sentence.isNotEmpty) {
        _sentenceQueue.add(sentence);
        _processQueue();
      }
    }
  }

  void flush() {
    final remaining = _buffer.toString().trim();
    if (remaining.isNotEmpty) {
      _sentenceQueue.add(remaining);
      _buffer.clear();
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_isSpeaking) return;
    _isSpeaking = true;

    while (_sentenceQueue.isNotEmpty) {
      final sentence = _sentenceQueue.removeFirst();
      await speakFn(sentence);
    }

    _isSpeaking = false;
  }

  void stop() {
    _sentenceQueue.clear();
    _buffer.clear();
    _isSpeaking = false;
  }
}
