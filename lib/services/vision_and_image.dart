/// Image generation (DALL-E 3) and vision (GPT-4o / Claude) services.
/// See Chapter 8 for camera integration, compression, and multimodal chat.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'openai_service.dart';

// ──────────────────────────────────────────────
// Image Generation
// ──────────────────────────────────────────────

enum ImageSize {
  square('1024x1024'),
  landscape('1792x1024'),
  portrait('1024x1792');

  final String value;
  const ImageSize(this.value);
}

enum ImageQuality {
  standard('standard'),
  hd('hd');

  final String value;
  const ImageQuality(this.value);
}

class GeneratedImage {
  final String url;
  final String? revisedPrompt;
  const GeneratedImage({required this.url, this.revisedPrompt});
}

class ImageGenerationService {
  final Dio _dio;

  ImageGenerationService({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.openai.com/v1',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ));

  Future<GeneratedImage> generate({
    required String prompt,
    ImageSize size = ImageSize.square,
    ImageQuality quality = ImageQuality.standard,
  }) async {
    final response = await _dio.post('/images/generations', data: {
      'model': 'dall-e-3',
      'prompt': prompt,
      'n': 1,
      'size': size.value,
      'quality': quality.value,
      'response_format': 'url',
    });

    final data = response.data['data'][0];
    return GeneratedImage(
      url: data['url'] as String,
      revisedPrompt: data['revised_prompt'] as String?,
    );
  }
}

// ──────────────────────────────────────────────
// Vision (Image Understanding)
// ──────────────────────────────────────────────

abstract class VisionAnalyzer {
  Stream<String> analyze({
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
  });
}

class OpenAiVisionAnalyzer implements VisionAnalyzer {
  final Dio _dio;

  OpenAiVisionAnalyzer({required String apiKey})
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://api.openai.com/v1',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ));

  @override
  Stream<String> analyze({
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
  }) async* {
    final base64Image = base64Encode(imageBytes);

    final response = await _dio.post<ResponseBody>(
      '/chat/completions',
      data: {
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,$base64Image',
                  'detail': 'high',
                },
              },
            ],
          }
        ],
        'stream': true,
        'max_tokens': 4096,
      },
      options: Options(responseType: ResponseType.stream),
    );

    yield* OpenAiService.parseSseStream(response.data!.stream);
  }
}

class GatewayVisionAnalyzer implements VisionAnalyzer {
  final Dio _dio;
  final String _model;

  GatewayVisionAnalyzer({
    required String gatewayUrl,
    String? authToken,
    String model = 'smart',
  })  : _model = model,
        _dio = Dio(BaseOptions(
          baseUrl: gatewayUrl,
          headers: {
            'Content-Type': 'application/json',
            if (authToken != null) 'Authorization': 'Bearer $authToken',
          },
        ));

  @override
  Stream<String> analyze({
    required Uint8List imageBytes,
    required String prompt,
    String mimeType = 'image/jpeg',
  }) async* {
    final base64Image = base64Encode(imageBytes);

    final response = await _dio.post<ResponseBody>(
      '/v1/chat/completions',
      data: {
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,$base64Image',
                },
              },
            ],
          }
        ],
        'stream': true,
        'max_tokens': 4096,
      },
      options: Options(responseType: ResponseType.stream),
    );

    yield* OpenAiService.parseSseStream(response.data!.stream);
  }
}
