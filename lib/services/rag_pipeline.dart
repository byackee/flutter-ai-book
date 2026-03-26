/// Complete RAG pipeline: chunking, embedding, vector search, context injection.
/// See Chapter 7 for the full walkthrough.
library;

import 'dart:math';
import 'package:dio/dio.dart';
import '../core/ai_service.dart';
import '../core/chat_message.dart';

// ──────────────────────────────────────────────
// Embedding Services
// ──────────────────────────────────────────────

class OpenAiEmbeddingService {
  final Dio _dio;

  OpenAiEmbeddingService({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.openai.com/v1',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ));

  Future<List<double>> embed(String text) async {
    final response = await _dio.post('/embeddings', data: {
      'model': 'text-embedding-3-small',
      'input': text,
    });
    final embedding = response.data['data'][0]['embedding'] as List;
    return embedding.cast<double>();
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final response = await _dio.post('/embeddings', data: {
      'model': 'text-embedding-3-small',
      'input': texts,
    });
    final data = response.data['data'] as List;
    return data
        .map((d) => (d['embedding'] as List).cast<double>())
        .toList();
  }
}

class OllamaEmbeddingService {
  final Dio _dio;
  final String model;

  OllamaEmbeddingService({
    String baseUrl = 'http://localhost:11434',
    this.model = 'nomic-embed-text',
  }) : _dio = Dio(BaseOptions(baseUrl: baseUrl));

  Future<List<double>> embed(String text) async {
    final response = await _dio.post('/api/embeddings', data: {
      'model': model,
      'prompt': text,
    });
    return (response.data['embedding'] as List).cast<double>();
  }

  Future<List<List<double>>> embedBatch(List<String> texts) async {
    final results = <List<double>>[];
    for (final text in texts) {
      results.add(await embed(text));
    }
    return results;
  }
}

// ──────────────────────────────────────────────
// Text Chunking
// ──────────────────────────────────────────────

class TextChunk {
  final String id;
  final String text;
  final String? sourceId;
  final int index;
  final int? startWord;
  final int? endWord;
  List<double>? embedding;

  TextChunk({
    required this.id,
    required this.text,
    this.sourceId,
    required this.index,
    this.startWord,
    this.endWord,
    this.embedding,
  });
}

class TextChunker {
  final int chunkSize;
  final int chunkOverlap;

  const TextChunker({this.chunkSize = 500, this.chunkOverlap = 50});

  /// Smart chunking: split on paragraph boundaries first
  List<TextChunk> chunkSmart(String text, {String? sourceId}) {
    final paragraphs = text.split(RegExp(r'\n\n+'));
    final chunks = <TextChunk>[];
    final buffer = StringBuffer();
    int wordCount = 0;

    for (final paragraph in paragraphs) {
      final paraWords = paragraph.split(RegExp(r'\s+')).length;

      if (wordCount + paraWords > chunkSize && buffer.isNotEmpty) {
        chunks.add(TextChunk(
          id: '${sourceId ?? "doc"}_chunk_${chunks.length}',
          text: buffer.toString().trim(),
          sourceId: sourceId,
          index: chunks.length,
        ));
        buffer.clear();
        wordCount = 0;
      }

      buffer.writeln(paragraph);
      buffer.writeln();
      wordCount += paraWords;
    }

    if (buffer.isNotEmpty) {
      chunks.add(TextChunk(
        id: '${sourceId ?? "doc"}_chunk_${chunks.length}',
        text: buffer.toString().trim(),
        sourceId: sourceId,
        index: chunks.length,
      ));
    }

    return chunks;
  }
}

// ──────────────────────────────────────────────
// Vector Store (in-memory)
// ──────────────────────────────────────────────

class VectorEntry {
  final String id;
  final String text;
  final List<double> embedding;
  final Map<String, dynamic> metadata;

  const VectorEntry({
    required this.id,
    required this.text,
    required this.embedding,
    this.metadata = const {},
  });
}

class SearchResult {
  final VectorEntry entry;
  final double score;

  const SearchResult({required this.entry, required this.score});
}

class InMemoryVectorStore {
  final List<VectorEntry> _entries = [];

  void addAll(List<TextChunk> chunks) {
    for (final chunk in chunks) {
      if (chunk.embedding == null) continue;
      _entries.add(VectorEntry(
        id: chunk.id,
        text: chunk.text,
        embedding: chunk.embedding!,
        metadata: {
          'sourceId': chunk.sourceId,
          'index': chunk.index,
        },
      ));
    }
  }

  List<SearchResult> search(
    List<double> queryEmbedding, {
    int topK = 5,
    double minScore = 0.3,
  }) {
    final scored = _entries.map((entry) {
      final score = _cosineSimilarity(queryEmbedding, entry.embedding);
      return SearchResult(entry: entry, score: score);
    }).toList();

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.where((r) => r.score >= minScore).take(topK).toList();
  }

  void removeSource(String sourceId) {
    _entries.removeWhere((e) => e.metadata['sourceId'] == sourceId);
  }

  int get length => _entries.length;

  double _cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length);
    double dotProduct = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denominator = sqrt(normA) * sqrt(normB);
    if (denominator == 0) return 0;
    return dotProduct / denominator;
  }
}

// ──────────────────────────────────────────────
// RAG Pipeline
// ──────────────────────────────────────────────

class RagContext {
  final String question;
  final List<SearchResult> chunks;

  const RagContext({required this.question, required this.chunks});

  String toPromptContext() {
    if (chunks.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('Use the following context to answer the question.');
    buffer.writeln("If the context doesn't contain the answer, say so.");
    buffer.writeln('Cite the source chunks you used by number.');
    buffer.writeln();
    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      buffer.writeln(
          '[Chunk ${i + 1}] (score: ${chunk.score.toStringAsFixed(2)})');
      buffer.writeln(chunk.entry.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  bool get hasContext => chunks.isNotEmpty;
}

class RagPipeline {
  final OpenAiEmbeddingService _embedder;
  final InMemoryVectorStore _vectorStore;
  final TextChunker _chunker;

  RagPipeline({
    required OpenAiEmbeddingService embedder,
    InMemoryVectorStore? vectorStore,
    TextChunker? chunker,
  })  : _embedder = embedder,
        _vectorStore = vectorStore ?? InMemoryVectorStore(),
        _chunker = chunker ?? const TextChunker();

  Future<int> ingest({
    required String text,
    required String sourceId,
    void Function(double progress)? onProgress,
  }) async {
    final chunks = _chunker.chunkSmart(text, sourceId: sourceId);
    if (chunks.isEmpty) return 0;

    const batchSize = 100;
    for (int i = 0; i < chunks.length; i += batchSize) {
      final batch = chunks.sublist(
          i, (i + batchSize).clamp(0, chunks.length));
      final embeddings =
          await _embedder.embedBatch(batch.map((c) => c.text).toList());
      for (int j = 0; j < batch.length; j++) {
        batch[j].embedding = embeddings[j];
      }
      onProgress?.call((i + batch.length) / chunks.length);
    }

    _vectorStore.addAll(chunks);
    return chunks.length;
  }

  Future<RagContext> query(String question, {int topK = 5}) async {
    final queryEmbedding = await _embedder.embed(question);
    final results = _vectorStore.search(queryEmbedding, topK: topK);
    return RagContext(question: question, chunks: results);
  }

  void removeDocument(String sourceId) {
    _vectorStore.removeSource(sourceId);
  }

  int get documentCount => _vectorStore.length;
}

// ──────────────────────────────────────────────
// RAG-augmented AI Service
// ──────────────────────────────────────────────

class RagAiService implements AiService {
  final AiService _inner;
  final RagPipeline _rag;

  RagAiService({required AiService inner, required RagPipeline rag})
      : _inner = inner,
        _rag = rag;

  @override
  String get name => '${_inner.name}+RAG';

  @override
  Future<bool> isAvailable() => _inner.isAvailable();

  @override
  Stream<String> chat({
    required List<ChatMessage> messages,
    String? model,
    double? temperature,
  }) async* {
    final lastUserMsg =
        messages.lastWhere((m) => m.role == MessageRole.user);
    final ragContext = await _rag.query(lastUserMsg.content);

    if (!ragContext.hasContext) {
      yield* _inner.chat(
          messages: messages, model: model, temperature: temperature);
      return;
    }

    final contextMsg = ChatMessage.system(ragContext.toPromptContext());
    final augmentedMessages = [
      contextMsg,
      ...messages.where((m) => m.role != MessageRole.system),
    ];

    yield* _inner.chat(
      messages: augmentedMessages,
      model: model,
      temperature: temperature ?? 0.3,
    );
  }
}
