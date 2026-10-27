import 'package:sports_esports_briefing/models/match_detail.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/main.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'package:sports_esports_briefing/services/api_key_storage_service.dart';
import 'package:sports_esports_briefing/services/providers.dart';
import 'package:sports_esports_briefing/services/ai_summary_service.dart';
import 'package:sports_esports_briefing/services/gemini_api.dart';
import 'support/http_fixture.dart';

class NoKeys extends ApiKeyStorageService {
  @override
  Future<String?> read() async => null;
}

class SavedKeys extends ApiKeyStorageService {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> save(String value) async {
    this.value = value;
  }
}

class FixtureRepository extends ScoreRepository {
  FixtureRepository() : super(Dio());
  @override
  Future<LeagueResult> load(League league, DateTime day) async => LeagueResult(
    league,
    league == League.nba
        ? [
            UnifiedMatchModel(
              id: 'espn:nba:1',
              league: league,
              startsAt: day,
              title: 'A vs B',
              state: MatchState.finalScore,
              participants: const [
                Participant(name: 'Alpha', score: '100', winner: true),
                Participant(name: 'Beta', score: '90'),
              ],
            ),
          ]
        : [],
  );
  @override
  Future<MatchDetail> details(UnifiedMatchModel match) async =>
      MatchDetail(article: await detail(match));
  @override
  Future<String> detail(UnifiedMatchModel match) async =>
      'Verified game report';
}

void main() {
  testWidgets(
    'Google model list can select and validate a newer model on a phone-sized settings sheet',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final keys = SavedKeys();
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((options) {
          calls++;
          if (options.method == 'GET') {
            return jsonResponse({
              'models': [
                {
                  'name': 'models/gemini-3.8-flash',
                  'displayName': 'Gemini 3.8 Flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
            });
          }
          expect(
            options.uri.path,
            contains('gemini-3.8-flash:generateContent'),
          );
          return jsonResponse({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'OK'},
                  ],
                },
              },
            ],
          });
        });
      final service = AiSummaryService(preferences, keys, api: GeminiApi(dio));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(preferences),
            repositoryProvider.overrideWithValue(FixtureRepository()),
            keyStorageProvider.overrideWithValue(keys),
            aiProvider.overrideWithValue(service),
          ],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('API Key & 설정'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, ' fixture-key ');
      final load = find.text('사용 가능 모델 불러오기');
      await tester.ensureVisible(load);
      await tester.tap(load);
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gemini 3.8 Flash · gemini-3.8-flash').last);
      await tester.pumpAndSettle();
      final save = find.text('연결 테스트 및 암호화 저장');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(keys.value, 'fixture-key');
      expect(preferences.getString('ai_model'), 'gemini-3.8-flash');
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'filter opens match detail and missing key leads to registration',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            repositoryProvider.overrideWithValue(FixtureRepository()),
            keyStorageProvider.overrideWithValue(NoKeys()),
          ],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'NBA'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'NBA'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Verified game report'), findsOneWidget);
      final button = find.text('Gemini AI로 한국어 3줄 요약 & 분석 보기');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('연결 테스트 및 암호화 저장'), findsOneWidget);
      expect(find.text('Gemini API 키'), findsOneWidget);
      expect(find.text('사용 가능 모델 불러오기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
