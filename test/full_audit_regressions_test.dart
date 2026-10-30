import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/match_adapters.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/features/scores/presentation/match_card.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'score_repository_test.dart' show FixtureAdapter;

Map<String, dynamic> event({String status = 'STATUS_FINAL'}) => {
  'id': 'x',
  'date': '2026-10-27T12:00:00Z',
  'name': 'A vs B',
  'status': {
    'type': {'name': status, 'state': 'post', 'completed': true},
  },
  'competitions': [
    {
      'competitors': [
        {
          'team': {'displayName': 'A'},
          'score': '0',
          'winner': true,
        },
      ],
    },
  ],
};
void main() {
  for (final status in [
    'STATUS_CANCELED',
    'STATUS_POSTPONED',
    'STATUS_SUSPENDED',
  ]) {
    test('ESPN $status never appears as a final or upcoming game', () {
      final m = EspnAdapter.parse({
        'events': [event(status: status)],
      }, League.mlb).single;
      expect(m.state, MatchState.cancelled);
      expect(m.participants.single.score, isNull);
      expect(m.participants.single.winner, isFalse);
    });
  }
  test(
    'an ESPN failure is not cached when user retries the same date',
    () async {
      var fail = true;
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((_) {
          if (fail) throw const FormatException('temporary failure');
          return {
            'events': [event()],
          };
        });
      final repo = ScoreRepository(dio);
      expect(
        (await repo.load(League.nba, DateTime(2026, 10, 27))).warning,
        isNotNull,
      );
      fail = false;
      final result = await repo.load(League.nba, DateTime(2026, 10, 27));
      expect(result.warning, isNull);
      expect(result.matches.single.id, 'espn:nba:x');
    },
  );
  test(
    'F1 round 20 results are fetched directly rather than truncated year results',
    () async {
      final paths = <String>[];
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          paths.add(r.uri.path);
          final race = <String, dynamic>{
            'season': '2026',
            'round': '20',
            'date': '2026-10-25',
            'time': '20:00:00Z',
            'raceName': 'Late Season GP',
          };
          if (r.uri.path.contains('/20/results')) {
            race['Results'] = [
              for (var i = 1; i <= 22; i++)
                {
                  'position': '$i',
                  'Driver': {'givenName': 'Driver', 'familyName': '$i'},
                  'Constructor': {'name': 'Team'},
                  'status': 'Finished',
                  'points': '0',
                },
            ];
          }
          return {
            'MRData': {
              'RaceTable': {
                'Races': [race],
              },
            },
          };
        });
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 10, 30),
      ).load(League.f1, DateTime(2026, 10, 25));
      expect(result.warning, isNull);
      expect(result.matches.single.standings, hasLength(22));
      expect(paths, contains('/ergast/f1/2026/20/results.json'));
      expect(paths, isNot(contains('/ergast/f1/2026/results.json')));
    },
  );
  testWidgets('F1 long result status wraps on narrow phones with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: MatchCard(
              match: UnifiedMatchModel(
                id: 'f1:2026:20',
                league: League.f1,
                startsAt: DateTime(2026),
                title: 'Grand Prix',
                state: MatchState.finalScore,
                standings: const [
                  RaceStanding(
                    '1',
                    'Very Long Driver Name',
                    'Team',
                    'Collision damage after mechanical failure',
                    '0',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
