/// Routes queries to local or cloud based on task complexity.
/// A local 14B model handles 60-70% of typical queries.
/// See Chapter 5 for the full hybrid strategy.
library;

import '../core/ai_service.dart';
import '../core/chat_message.dart';

enum TaskComplexity { simple, moderate, complex }

class HybridAiService implements AiService {
  final AiService localService;
  final AiService cloudService;
  final TaskClassifier _classifier;

  HybridAiService({
    required this.localService,
    required this.cloudService,
  }) : _classifier = TaskClassifier();

  @override
  String get name => 'Hybrid(${localService.name} + ${cloudService.name})';

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    final lastMessage = messages.last.content;
    final complexity = _classifier.classify(lastMessage);

    final service = switch (complexity) {
      TaskComplexity.simple => localService,
      TaskComplexity.moderate => localService,
      TaskComplexity.complex => cloudService,
    };

    try {
      yield* service.chat(
        messages: messages,
        model: model,
        temperature: temperature,
      );
    } catch (_) {
      final fallback =
          service == localService ? cloudService : localService;
      yield* fallback.chat(
        messages: messages,
        model: model,
        temperature: temperature,
      );
    }
  }

  @override
  Future<bool> isAvailable() async {
    return await localService.isAvailable() ||
        await cloudService.isAvailable();
  }
}

/// Heuristic classifier — intentionally simple.
/// Refine based on actual usage patterns.
class TaskClassifier {
  TaskComplexity classify(String input) {
    final wordCount = input.split(RegExp(r'\s+')).length;
    final hasCode = input.contains('```') ||
        RegExp(r'(function|class|def |import |const |var )').hasMatch(input);
    final hasAnalysis = RegExp(
      r'(compare|analyze|explain why|pros and cons|trade.?offs)',
      caseSensitive: false,
    ).hasMatch(input);
    final hasCreative = RegExp(
      r'(write a |create a |design a |build a |generate)',
      caseSensitive: false,
    ).hasMatch(input);

    if (wordCount > 200 || (hasCode && hasAnalysis)) {
      return TaskComplexity.complex;
    }
    if (hasCreative && wordCount > 50) {
      return TaskComplexity.complex;
    }
    if (hasAnalysis || (hasCode && wordCount > 30)) {
      return TaskComplexity.moderate;
    }
    return TaskComplexity.simple;
  }
}
