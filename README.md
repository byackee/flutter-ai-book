# 📘 Build AI-Powered Flutter Apps — A Developer's Handbook

Complete source code for the book **"Build AI-Powered Flutter Apps"**.

## What's Inside

| Chapter | Topic | Key Code |
|---------|-------|----------|
| 2 | Architecture Patterns | `AiService`, `FallbackAiService`, `ChatMessage` |
| 3 | Chat UI from Scratch | `MessageBubble`, `StreamingMarkdown`, `ChatScreen` |
| 4 | OpenAI / Anthropic API | `OpenAiService`, `AnthropicService`, SSE parsers, `RetryAiService` |
| 5 | Local LLM with Ollama | `OllamaService`, `HybridAiService`, `TaskClassifier` |
| 6 | AI Gateway | `GatewayAiService`, `ModelPicker`, `GatewayHealthCheck` |
| 7 | RAG in Flutter | `RagPipeline`, `InMemoryVectorStore`, `TextChunker` |
| 8 | Image Generation & Vision | `ImageGenerationService`, `VisionAnalyzer` |
| 9 | Voice ↔ AI | `VoiceAssistant`, `StreamingTtsService` |
| 10 | Production Checklist | `RateLimiter`, `CachedAiService`, `ModerationService`, `CostController` |

## Getting Started

1. Clone this repo
2. Copy `.env.example` to `.env` and add your API keys
3. Run `flutter pub get`
4. Open any chapter's code and drop it into your project

## Requirements

- Flutter 3.19+
- Dart 3.3+
- For local LLM: [Ollama](https://ollama.ai) installed

## License

MIT — use this code however you want.

## Book

Get the full book with detailed explanations, architecture diagrams, and production tips:
**[Build AI-Powered Flutter Apps](https://gumroad.com/)** *(link coming soon)*
