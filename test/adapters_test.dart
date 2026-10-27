import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/match_adapters.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';

void main() {
  test(
    'ESPN preserves final score, winner, linescores and league-scoped id',
    () {
      final result = EspnAdapter.parse({
        'events': [
          {
            'id': '123',
            'date': '2026-10-27T00:00:00Z',
            'name': 'A vs B',
            'status': {
              'type': {'completed': true, 'state': 'post', 'detail': 'Final'},
            },
            'competitions': [
              {
                'competitors': [
                  {
                    'team': {'displayName': 'A'},
                    'score': '100',
                    'winner': true,
                    'linescores': [
                      {'value': 25},
                    ],
                  },
                  {
                    'team': {'displayName': 'B'},
                    'score': '95',
                    'winner': false,
                  },
                ],
              },
            ],
          },
        ],
      }, League.nba).single;
      expect(result.id, 'espn:nba:123');
      expect(result.state, MatchState.finalScore);
      expect(result.participants.first.winner, isTrue);
      expect(result.participants.last.score, '95');
      expect(result.lines.single, 'A: 25');
    },
  );

  test('scheduled ESPN events never imply a zero score', () {
    final match = EspnAdapter.parse({
      'events': [
        {
          'id': '2',
          'date': '2026-10-27T12:00:00Z',
          'name': 'A vs B',
          'status': {
            'type': {'state': 'pre', 'completed': false},
          },
          'competitions': [
            {
              'competitors': [
                {
                  'team': {'name': 'A'},
                  'score': '0',
                },
              ],
            },
          ],
        },
      ],
    }, League.nfl).single;
    expect(match.state, MatchState.scheduled);
    expect(match.participants.single.score, isNull);
  });

  test('Jolpica retains all classified drivers and retirement status', () {
    final match = JolpicaAdapter.parse({
      'MRData': {
        'RaceTable': {
          'Races': [
            {
              'season': '2026',
              'round': '1',
              'date': '2026-03-08',
              'time': '04:00:00Z',
              'raceName': 'Grand Prix',
              'Results': [
                {
                  'position': '1',
                  'Driver': {'givenName': 'A', 'familyName': 'Driver'},
                  'Constructor': {'name': 'Team'},
                  'Time': {'time': '1:30:00'},
                  'points': '25',
                },
                {
                  'position': '2',
                  'Driver': {'givenName': 'B', 'familyName': 'Driver'},
                  'Constructor': {'name': 'Other'},
                  'status': 'Retired',
                  'points': '0',
                },
              ],
            },
          ],
        },
      },
    }).single;
    expect(match.standings, hasLength(2));
    expect(match.standings.last.time, 'Retired');
    expect(match.id, 'f1:2026:1');
  });
}
