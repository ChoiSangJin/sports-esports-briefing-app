import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/features/scores/data/match_adapters.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/features/scores/data/season_service.dart';
import 'package:sports_esports_briefing/features/scores/presentation/team_statistics_table.dart';
import 'package:sports_esports_briefing/main.dart';
import 'package:sports_esports_briefing/models/match_detail.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'package:sports_esports_briefing/services/providers.dart';
import 'score_repository_test.dart' show FixtureAdapter;

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual EPL scores, winning team and league scoped IDs are preserved',
    () {
      final games = EspnAdapter.parse(fixture('epl_scoreboard'), League.epl);
      expect(games, hasLength(4));
      expect(games.first.id, 'espn:epl:401879256');
      expect(games.first.participants.first.name, 'Aston Villa');
      expect(games.first.participants.first.score, '2');
      expect(games.first.participants.last.score, '1');
    },
  );
  test('EPL draw displays equal scores without declaring a winner', () {
    final j = fixture('epl_scoreboard');
    final c = j['events'][0]['competitions'][0]['competitors'];
    c[0]['score'] = '1';
    c[1]['score'] = '1';
    final match = EspnAdapter.parse(j, League.epl).first;
    expect(match.status, contains('무승부'));
    expect(match.participants.any((p) => p.winner), isFalse);
  });
  test('actual EPL report, team metrics and timed goals are parsed', () {
    final detail = MatchDetail.fromEspn(fixture('epl_summary'));
    expect(detail.teams, hasLength(2));
    expect(detail.teams.first.values['possessionPct'], '36.8');
    expect(detail.article, contains('Jackson'));
    expect(detail.plays, hasLength(3));
    expect(detail.plays.first, contains("6'"));
  });
  test(
    'EPL 38 games for all clubs ends season; early title clinch does not',
    () {
      final j = fixture('epl_final_table');
      expect(SeasonService.eplChampion(j, 2025), 'Arsenal');
      j['children'][0]['standings']['entries'][1]['stats'][0]['value'] = 37;
      expect(SeasonService.eplChampion(j, 2025), isNull);
    },
  );
  test(
    'EPL summer rollover checks previous final table without hiding new season',
    () async {
      final previous = fixture('epl_final_table');
      final current = fixture('epl_final_table');
      current['season']['year'] = 2026;
      current['children'][0]['standings']['season'] = 2026;
      for (final e in current['children'][0]['standings']['entries']) {
        e['stats'][0]['value'] = 0;
      }
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          if (r.uri.path.endsWith('/standings')) {
            return r.queryParameters['season'] == 2025 ? previous : current;
          }
          return {
            'leagues': [
              {
                'season': {'year': 2026},
              },
            ],
            'events': [],
          };
        });
      expect(
        await SeasonService(dio).notice('soccer/eng.1', DateTime(2026, 6, 10)),
        contains('EPL 2025/2026 시즌 종료'),
      );
      current['children'][0]['standings']['entries'][0]['stats'][0]['value'] =
          1;
      expect(
        await SeasonService(dio).notice('soccer/eng.1', DateTime(2026, 8, 20)),
        isNull,
      );
    },
  );
  test(
    'EPL repository connects scoreboard and soccer summary endpoint',
    () async {
      final paths = <String>[];
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          paths.add(r.uri.path);
          return r.uri.path.endsWith('/summary')
              ? fixture('epl_summary')
              : fixture('epl_scoreboard');
        });
      final repo = ScoreRepository(dio, clock: () => DateTime(2026, 10, 30));
      final result = await repo.load(League.epl, DateTime(2026, 10, 24));
      final detail = await repo.details(result.matches.first);
      expect(result.warning, isNull);
      expect(detail.plays, isNotEmpty);
      expect(paths, contains('/apis/site/v2/sports/soccer/eng.1/summary'));
    },
  );
  testWidgets(
    'EPL chip filters phone dashboard and football table fits 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((_) => fixture('epl_scoreboard'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            repositoryProvider.overrideWithValue(
              ScoreRepository(dio, clock: () => DateTime(2026, 10, 30)),
            ),
            selectedDateProvider.overrideWith((ref) => DateTime(2026, 10, 24)),
            selectedLeagueProvider.overrideWith((ref) => League.epl),
            keyPresentProvider.overrideWith((ref) async => false),
          ],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('EPL'), findsWidgets);
      expect(find.text('Aston Villa'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: TeamStatisticsTable(
                  detail: MatchDetail.fromEspn(fixture('epl_summary')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('점유율 (%)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'EPL long break finds next monthly fixture beyond fourteen days',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          if (r.queryParameters['dates'] == '202611') {
            final j = fixture('epl_scoreboard');
            j['events'] = [j['events'][0]];
            j['events'][0]['date'] = '2026-11-28T12:00:00Z';
            j['events'][0]['status']['type'] = {
              'state': 'pre',
              'completed': false,
            };
            return j;
          }
          return {'events': []};
        });
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 10, 30),
      ).load(League.epl, DateTime(2026, 10, 30));
      expect(result.warning, isNull);
      expect(result.isUpcoming, isTrue);
      expect(result.matches.single.startsAt.day, 28);
      expect(
        result.matches.single.participants.every((p) => p.score == null),
        isTrue,
      );
    },
  );
  test(
    'EPL live new-season games override stale zero-played summer table',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          expect(r.uri.path.endsWith('/scoreboard'), isTrue);
          return {
            'leagues': [
              {
                'season': {'year': 2026},
              },
            ],
            'events': [
              {
                'season': {'year': 2026},
                'status': {
                  'type': {'state': 'in'},
                },
              },
            ],
          };
        });
      expect(
        await SeasonService(dio).notice('soccer/eng.1', DateTime(2026, 8, 20)),
        isNull,
      );
    },
  );
  test(
    'EPL opening-day scheduled fixture is not hidden by previous season notice',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          expect(r.uri.path.endsWith('/scoreboard'), isTrue);
          return {
            'leagues': [
              {
                'season': {'year': 2026},
              },
            ],
            'events': [
              {
                'season': {'year': 2026},
                'date': '2026-08-20T20:00:00Z',
                'status': {
                  'type': {'state': 'pre'},
                },
              },
            ],
          };
        });
      expect(
        await SeasonService(
          dio,
        ).notice('soccer/eng.1', DateTime(2026, 8, 20, 8)),
        isNull,
      );
    },
  );
}
