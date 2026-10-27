import 'package:dio/dio.dart';

class AiFailure implements Exception {
  const AiFailure(this.message);
  final String message;
}

class AiModel {
  const AiModel(this.id, this.label);
  final String id, label;
  Map<String, String> toJson() => {'id': id, 'label': label};
  static bool validId(String id) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$').hasMatch(id);
}

/// Uses the current Gemini REST contract without a hardcoded model catalog.
class GeminiApi {
  GeminiApi([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 45),
            ),
          );
  final Dio _dio;
  void close() => _dio.close();
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  Options _options(String key) => Options(headers: {'x-goog-api-key': key});

  Future<List<AiModel>> listModels(String key) async {
    if (key.trim().isEmpty) throw const AiFailure('API 키를 입력해 주세요.');
    final found = <String, AiModel>{};
    final seen = <String>{};
    String? token;
    try {
      for (var page = 0; page < 20; page++) {
        final response = await _dio.get<Map<String, dynamic>>(
          '$_base/models',
          queryParameters: {
            'pageSize': 100,
            if (token != null) 'pageToken': token,
          },
          options: _options(key.trim()),
        );
        final data = response.data!;
        for (final row in data['models'] as List? ?? []) {
          final name = row['name']?.toString() ?? '';
          final id = name.startsWith('models/') ? name.substring(7) : name;
          final lower = id.toLowerCase();
          final methods = row['supportedGenerationMethods'] as List? ?? [];
          if (!AiModel.validId(id) ||
              !methods.contains('generateContent') ||
              [
                'embedding',
                'image',
                'tts',
                'audio',
                'robotics',
              ].any(lower.contains)) {
            continue;
          }
          found[id] = AiModel(id, row['displayName']?.toString() ?? id);
        }
        token = data['nextPageToken'] as String?;
        if (token == null || token.isEmpty) {
          if (found.isEmpty) {
            throw const AiFailure(
              '이 키로 조회된 텍스트 생성 모델이 없습니다. 모델 ID 직접 입력 또는 계정 권한을 확인하세요.',
            );
          }
          return found.values.toList()
            ..sort((a, b) => a.label.compareTo(b.label));
        }
        if (!seen.add(token)) break;
      }
      throw const AiFailure('모델 목록 전체를 가져오지 못했습니다. 다시 시도해 주세요.');
    } on AiFailure {
      rethrow;
    } on DioException catch (e) {
      throw failure(e.response?.statusCode);
    } catch (_) {
      throw failure(null);
    }
  }

  Future<String> generate(String key, String model, String prompt) async {
    if (!AiModel.validId(model)) {
      throw const AiFailure('사용할 모델을 선택하거나 모델 ID를 입력해 주세요.');
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_base/models/$model:generateContent',
        options: _options(key),
        data: {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'maxOutputTokens': 8192},
        },
      );
      final candidates = response.data?['candidates'] as List? ?? [];
      if (candidates.isEmpty) {
        throw const AiFailure('모델이 응답을 생성하지 않았습니다. 안전 필터 또는 모델 지원 여부를 확인하세요.');
      }
      final parts = candidates.first['content']?['parts'] as List? ?? [];
      final text = parts
          .where((p) => p['thought'] != true && p['text'] is String)
          .map((p) => p['text'] as String)
          .join('\n')
          .trim();
      if (text.isEmpty) {
        throw const AiFailure('텍스트 응답이 없습니다. 텍스트 생성 모델을 선택하거나 다시 시도해 주세요.');
      }
      return text;
    } on AiFailure {
      rethrow;
    } on DioException catch (e) {
      throw failure(e.response?.statusCode);
    } catch (_) {
      throw failure(null);
    }
  }

  static AiFailure failure(int? status) => AiFailure(switch (status) {
    400 => '요청을 처리하지 못했습니다. API 키와 선택 모델의 지원 여부를 확인하세요.',
    401 || 403 => 'API 키의 인증·지역·모델 접근 권한을 확인하세요.',
    404 => '해당 모델을 사용할 수 없습니다. 사용 가능 모델 목록을 새로 불러와 선택하세요.',
    429 => 'Google API 할당량 또는 사용 한도에 도달했습니다. 계정의 요금·할당량을 확인하세요.',
    500 ||
    502 ||
    503 ||
    504 => 'Google AI 서비스가 일시적으로 응답하지 않습니다. 잠시 후 다시 시도하세요.',
    _ => 'Google AI 요청에 실패했습니다. 네트워크와 API 키를 확인하세요.',
  });
}
