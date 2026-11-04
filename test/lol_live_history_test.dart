import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/main.dart';
import 'package:sports_esports_briefing/services/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/features/scores/data/lol_schedule_service.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'score_repository_test.dart' show FixtureAdapter;

class CountingLiveRepository extends ScoreRepository {
  CountingLiveRepository() : super(Dio());
  int calls = 0;
  @override
  Future<LeagueResult> load(League league, DateTime day) async {
    calls++;
    return LeagueResult(league, const []);
  }
}

Map<String, dynamic> captured() =>
    jsonDecode(File('test/fixtures/lol_live_schedule.json').readAsStringSync())
        as Map<String, dynamic>;
void main() {
  test(
    'official date query includes TES IG live instead of tomorrow GEN LYON',
    () async {
      final data = captured();
      final event = (data['data']['esports']['events'] as List).firstWhere(
        (e) => e['state'] == 'inProgress',
      );
      final local = DateTime.parse(event['startTime']).toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          expect(r.uri.path, '/api/gql');
          expect(r.method, 'POST');
          return data;
        });
      final result = await ScoreRepository(
        dio,
        clock: () => day.add(const Duration(hours: 12)),
      ).load(League.lol, day);
      expect(result.warning, isNull);
      expect(result.isUpcoming, isFalse);
      expect(result.matches.single.state, MatchState.live);
      expect(
        result.matches.single.participants.map((p) => p.name),
        containsAll(['Invictus Gaming', 'TOP ESPORTS']),
      );
      expect(
        result.matches.single.participants.map((p) => p.score),
        everyElement('1'),
      );
    },
  );
  test('past empty LoL date never loads future homepage fixtures', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter((r) {
        calls++;
        expect(r.uri.path, '/api/gql');
        return {
          'data': {
            'esports': {'events': [], 'pages': {}},
          },
        };
      });
    final result = await ScoreRepository(
      dio,
      clock: () => DateTime(2026, 11, 4),
    ).load(League.lol, DateTime(2026, 11, 3));
    expect(result.matches, isEmpty);
    expect(result.isUpcoming, isFalse);
    expect(result.warning, isNull);
    expect(calls, 3);
  });
  test(
    'confirmed final result cannot regress to stale scheduled snapshot',
    () async {
      final event = captured()['data']['esports']['events'][0];
      event['startTime'] = DateTime(2026, 11, 3, 7).toUtc().toIso8601String();
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          final e = jsonDecode(jsonEncode(event));
          final state = (r.data as Map)['variables']['eventState'][0];
          e['state'] = state;
          if (state == 'completed') {
            e['matchTeams'][0]['result'] = {'gameWins': 3, 'outcome': 'win'};
            e['matchTeams'][1]['result'] = {'gameWins': 1, 'outcome': 'loss'};
          }
          return {
            'data': {
              'esports': {
                'events': [e],
                'pages': {},
              },
            },
          };
        });
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 11, 4),
      ).load(League.lol, DateTime(2026, 11, 3));
      expect(result.matches.single.state, MatchState.finalScore);
      expect(result.matches.single.participants.first.score, '3');
    },
  );
  test(
    'official API error never silently falls back to misleading future schedule',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (_) => {
            'errors': [
              {'message': 'operation unavailable'},
            ],
          },
        );
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 11, 4),
      ).load(League.lol, DateTime(2026, 11, 4));
      expect(result.warning, isNotNull);
      expect(result.matches, isEmpty);
      expect(result.isUpcoming, isFalse);
    },
  );
  test('date query cache expires on manual refresh', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter((_) {
        calls++;
        return captured();
      });
    final service = LolScheduleService(dio);
    await service.loadDay(DateTime(2026, 11, 4));
    await service.loadDay(DateTime(2026, 11, 4));
    expect(calls, 3);
    service.clearCache();
    await service.loadDay(DateTime(2026, 11, 4));
    expect(calls, 6);
  });
  testWidgets(
    'today shows TES IG and previous date never shows tomorrow GEN LYON',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final data = captured();
      data['data']['esports']['events'][0]['startTime'] = DateTime(
        2026,
        11,
        4,
        7,
      ).toUtc().toIso8601String();
      final dio = Dio()..httpClientAdapter = FixtureAdapter((_) => data);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            repositoryProvider.overrideWithValue(
              ScoreRepository(dio, clock: () => DateTime(2026, 11, 4, 9)),
            ),
            selectedDateProvider.overrideWith((ref) => DateTime(2026, 11, 4)),
            selectedLeagueProvider.overrideWith((ref) => League.lol),
            keyPresentProvider.overrideWith((ref) async => false),
          ],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TOP ESPORTS'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      await tester.tap(find.byTooltip('이전 날짜'));
      await tester.pumpAndSettle();
      expect(find.text('TOP ESPORTS'), findsNothing);
      expect(find.text('Gen.G Esports'), findsNothing);
      expect(find.textContaining('다음 예정 경기를 표시'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('visible today LoL feed refreshes after thirty seconds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = CountingLiveRepository();
    final now = DateTime.now();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          repositoryProvider.overrideWithValue(repo),
          selectedDateProvider.overrideWith(
            (ref) => DateTime(now.year, now.month, now.day),
          ),
          selectedLeagueProvider.overrideWith((ref) => League.lol),
          keyPresentProvider.overrideWith((ref) async => false),
        ],
        child: const BriefingApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
