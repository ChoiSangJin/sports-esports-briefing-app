import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'support/http_fixture.dart';

void main() {
  test(
    'F1 selected future race on December 31 is not skipped into the next year',
    () async {
      final year = DateTime.now().year + 1;
      final day = DateTime(year, 12, 31);
      final dio = Dio()
        ..httpClientAdapter = HttpFixture(
          (o) => jsonResponse({
            'MRData': {
              'RaceTable': {
                'Races': o.uri.path.endsWith('/$year.json')
                    ? [
                        {
                          'season': '$year',
                          'round': '1',
                          'date': '$year-12-31',
                          'time': '12:00:00Z',
                          'raceName': 'Future GP',
                        },
                      ]
                    : [],
              },
            },
          }),
        );
      final result = await ScoreRepository(dio).load(League.f1, day);
      expect(result.matches.single.title, 'Future GP');
      expect(result.matches.single.state, MatchState.scheduled);
      expect(result.isUpcoming, isFalse);
    },
  );
  test(
    'empty selected day shows only scheduled matches on the nearest future day',
    () async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day + 3);
      final next = DateTime(day.year, day.month, day.day + 2, 12);
      String date(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((o) {
          calls++;
          return jsonResponse({
            'events': o.queryParameters['dates'] == date(next)
                ? [
                    {
                      'id': 'next',
                      'date': next.toUtc().toIso8601String(),
                      'name': 'Next game',
                      'status': {
                        'type': {'state': 'pre'},
                      },
                      'competitions': [
                        {'competitors': []},
                      ],
                    },
                  ]
                : [],
          });
        });
      final result = await ScoreRepository(dio).load(League.nba, day);
      expect(result.isUpcoming, isTrue);
      expect(result.warning, isNull);
      expect(result.matches.single.startsAt, next.toUtc());
      expect(result.matches.single.state, MatchState.scheduled);
      expect(calls, lessThanOrEqualTo(5));
    },
  );
}
