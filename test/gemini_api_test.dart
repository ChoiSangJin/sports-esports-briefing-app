import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/services/gemini_api.dart';
import 'package:sports_esports_briefing/services/ai_summary_service.dart';
import 'package:sports_esports_briefing/services/api_key_storage_service.dart';
import 'support/http_fixture.dart';

void main() {
  test(
    'model discovery follows pagination, accepts newer models and excludes non-text models',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((options) {
          calls++;
          expect(options.headers['x-goog-api-key'], 'fixture-key');
          expect(options.uri.toString(), isNot(contains('fixture-key')));
          if (calls == 1) {
            return jsonResponse({
              'models': [
                {
                  'name': 'models/gemini-3.8-flash',
                  'displayName': 'Gemini 3.8 Flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/gemini-3.8-flash-tts',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/gemini-image',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/text-embedding',
                  'supportedGenerationMethods': ['embedContent'],
                },
                {
                  'name': 'models/../../bad',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
              'nextPageToken': 'next',
            });
          }
          expect(options.queryParameters['pageToken'], 'next');
          return jsonResponse({
            'models': [
              {
                'name': 'models/gemini-4-argon',
                'displayName': 'Gemini 4 Argon',
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
          });
        });
      final models = await GeminiApi(dio).listModels(' fixture-key ');
      expect(models.map((m) => m.id), ['gemini-3.8-flash', 'gemini-4-argon']);
      expect(calls, 2);
    },
  );

  test(
    'generateContent uses selected model, no legacy whitelist, and returns visible text only',
    () async {
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((options) {
          expect(options.method, 'POST');
          expect(
            options.uri.path,
            '/v1beta/models/gemini-new-release:generateContent',
          );
          expect(
            (options.data as Map)['contents'][0]['parts'][0]['text'],
            'report',
          );
          return jsonResponse({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'private reasoning', 'thought': true},
                    {'text': '한국어 요약'},
                    {'text': '통계 분석'},
                  ],
                },
              },
            ],
          });
        });
      expect(
        await GeminiApi(
          dio,
        ).generate('fixture-key', 'gemini-new-release', 'report'),
        '한국어 요약\n통계 분석',
      );
    },
  );

  test(
    'quota and unavailable model errors are actionable and never disclose provider payload',
    () async {
      for (final status in [429, 404, 403]) {
        final dio = Dio()
          ..httpClientAdapter = HttpFixture(
            (_) => jsonResponse({
              'error': {'message': 'DO-NOT-LEAK fixture-key'},
            }, status: status),
          );
        await expectLater(
          GeminiApi(dio).generate('fixture-key', 'gemini-test', 'test'),
          throwsA(
            isA<AiFailure>().having(
              (e) => e.message,
              'safe message',
              allOf(
                isNot(contains('DO-NOT-LEAK')),
                isNot(contains('fixture-key')),
                contains(switch (status) {
                  429 => '할당량',
                  404 => '모델',
                  _ => '권한',
                }),
              ),
            ),
          ),
        );
      }
    },
  );

  test(
    'repeated pagination is an error and cannot cache a misleading partial catalog',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final dio = Dio()
        ..httpClientAdapter = HttpFixture(
          (_) => jsonResponse({'models': [], 'nextPageToken': 'same'}),
        );
      final service = AiSummaryService(
        preferences,
        ApiKeyStorageService(),
        api: GeminiApi(dio),
      );
      await expectLater(
        service.discoverModels('fixture-key'),
        throwsA(isA<AiFailure>()),
      );
      expect(preferences.getString('ai_models'), isNull);
    },
  );

  test(
    'successful model catalog persists without key and survives service restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final dio = Dio()
        ..httpClientAdapter = HttpFixture(
          (_) => jsonResponse({
            'models': [
              {
                'name': 'models/gemini-future',
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
          }),
        );
      final service = AiSummaryService(
        preferences,
        ApiKeyStorageService(),
        api: GeminiApi(dio),
      );
      await service.discoverModels('fixture-key');
      expect(
        preferences.getString('ai_models'),
        isNot(contains('fixture-key')),
      );
      expect(jsonDecode(preferences.getString('ai_models')!), hasLength(1));
      final next = AiSummaryService(preferences, ApiKeyStorageService());
      expect(next.availableModels.single.id, 'gemini-future');
      await next.setModel('gemini-future');
      expect(next.model, 'gemini-future');
    },
  );
}
