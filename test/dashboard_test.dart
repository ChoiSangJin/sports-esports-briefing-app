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

class NoKeys extends ApiKeyStorageService {
  @override
  Future<String?> read() async => null;
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
  Future<String> detail(UnifiedMatchModel match) async =>
      'Verified game report';
}

void main() {
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
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
