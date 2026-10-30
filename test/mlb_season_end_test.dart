import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_esports_briefing/main.dart';
import 'package:sports_esports_briefing/services/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/features/scores/data/season_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'score_repository_test.dart' show FixtureAdapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> fixture() =>
      jsonDecode(
            File(
              'test/fixtures/mlb_world_series_clinched.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final now = DateTime(2026, 10, 30);
  test(
    'actual World Series clinch overrides stale postseason calendar cutoff',
    () async {
      final dio = Dio()..httpClientAdapter = FixtureAdapter((_) => fixture());
      final result = await ScoreRepository(
        dio,
        clock: () => now,
      ).load(League.mlb, now);
      expect(result.seasonNotice, contains('MLB 2026 시즌 종료'));
      expect(result.seasonNotice, contains('Milwaukee Brewers'));
      expect(result.seasonNotice, contains('확인되지 않았습니다'));
      expect(result.matches, isEmpty);
      expect(result.warning, isNull);
    },
  );
  for (final stage in [
    'AL Championship Series - Game 5',
    'NL Division Series - Game 5',
    'College World Series - Game 5',
  ]) {
    test('$stage does not imply MLB season ended', () {
      final j = fixture();
      j['events'][0]['competitions'][0]['notes'][0]['headline'] = stage;
      expect(SeasonService.worldSeriesChampion(j, 2026, now), isNull);
    });
  }
  test('unfinished or mismatched World Series records do not end season', () {
    for (final change in [
      'series',
      'game',
      'wins',
      'winner',
      'year',
      'future',
    ]) {
      final j = fixture();
      final e = j['events'][0];
      final c = e['competitions'][0];
      switch (change) {
        case 'series':
          c['series']['completed'] = false;
        case 'game':
          c['status']['type']['completed'] = false;
        case 'wins':
          for (final t in c['series']['competitors']) {
            if (t['wins'] == 4) t['wins'] = 3;
          }
        case 'winner':
          for (final t in c['competitors']) {
            t['winner'] = false;
          }
        case 'year':
          e['season']['year'] = 2025;
        case 'future':
          e['date'] = '2026-11-05T00:00Z';
      }
      expect(
        SeasonService.worldSeriesChampion(j, 2026, now),
        isNull,
        reason: change,
      );
    }
  });
  test(
    'monthly calendar finds final when default scoreboard has no games',
    () async {
      final calls = <String?>[];
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          calls.add(r.queryParameters['dates'] as String?);
          if (r.queryParameters['dates'] == '202610') return fixture();
          final j = fixture();
          j['events'] = [];
          return j;
        });
      expect(
        await SeasonService(dio).notice('baseball/mlb', now),
        contains('Milwaukee Brewers'),
      );
      expect(calls, [null, '202610', '2027']);
    },
  );
  test(
    'new cache version ignores old no-notice and manual refresh clears stored state',
    () async {
      SharedPreferences.setMockInitialValues({
        'season_notice_v1:baseball/mlb': jsonEncode({
          'expires': now.add(const Duration(hours: 1)).toIso8601String(),
          'value': null,
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((_) {
          calls++;
          return fixture();
        });
      final repo = ScoreRepository(dio, clock: () => now, preferences: prefs);
      expect(
        (await repo.load(League.mlb, now)).seasonNotice,
        contains('시즌 종료'),
      );
      final first = calls;
      await repo.load(League.mlb, now);
      expect(calls, first);
      repo.clearCache();
      await repo.load(League.mlb, now);
      expect(calls, greaterThan(first));
    },
  );
  testWidgets(
    'phone dashboard displays completed MLB season instead of empty search',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio()..httpClientAdapter = FixtureAdapter((_) => fixture());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            repositoryProvider.overrideWithValue(
              ScoreRepository(dio, clock: () => now),
            ),
            selectedDateProvider.overrideWith((ref) => now),
            selectedLeagueProvider.overrideWith((ref) => League.mlb),
            keyPresentProvider.overrideWith((ref) async => false),
          ],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('MLB 2026 시즌 종료'), findsOneWidget);
      expect(
        find.textContaining('월드시리즈 우승: Milwaukee Brewers'),
        findsOneWidget,
      );
      expect(find.textContaining('14일'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
