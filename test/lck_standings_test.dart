import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/lck_standings_service.dart';
import 'support/http_fixture.dart';

void main() {
  final display =
      (jsonDecode(File('test/fixtures/lck_standings.json').readAsStringSync())
              as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
  test('official LCK groups and brackets remain separately labelled', () {
    final sections = LckStandingsService.parse(display, DateTime(2026, 11, 9));
    expect(sections.where((s) => s.title.contains('그룹 순위')), hasLength(2));
    expect(sections.where((s) => s.title.contains('단계별 공식 배치')), isNotEmpty);
    expect(sections.first.rows.first, ['1', 'Gen.G Esports', '5', '3']);
    expect(sections.every((s) => s.title.contains('선택일 당시 순위 아님')), isTrue);
  });
  test(
    'current season IDs resolved by time and LCK only; cache reuses result',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((o) {
          calls++;
          expect(o.headers.containsKey('x-api-key'), isFalse);
          final body = o.data as Map;
          switch (body['operationName']) {
            case 'GetGprSeasons':
              return jsonResponse({
                'data': {
                  'seasons': [
                    {
                      'id': 'old',
                      'startTime': '2025-01-01T00:00:00Z',
                      'endTime': '2025-12-31T23:59:59Z',
                    },
                    {
                      'id': 'current',
                      'startTime': '2026-01-01T00:00:00Z',
                      'endTime': '2026-12-31T23:59:59Z',
                    },
                  ],
                },
              });
            case 'GetSeasonForNavigation':
              expect(body['variables']['seasonId'], ['current']);
              return jsonResponse({
                'data': {
                  'seasons': [
                    {
                      'splits': [
                        {
                          'tournaments': [
                            {
                              'id': 'future',
                              'league': {'name': 'LCK'},
                              'startTime': '2026-12-01T00:00:00Z',
                            },
                            {
                              'id': 'other',
                              'league': {'name': 'LPL'},
                              'startTime': '2026-10-01T00:00:00Z',
                            },
                            {
                              'id': 'lck',
                              'league': {'name': 'LCK'},
                              'startTime': '2026-07-01T00:00:00Z',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              });
            case 'GetSeasonTournamentDisplay':
              expect(body['variables']['tournamentId'], ['lck']);
              return jsonResponse({'data': display});
            default:
              throw StateError('Unexpected operation');
          }
        });
      final service = LckStandingsService(dio);
      expect(await service.load(DateTime(2026, 11, 9)), isNotEmpty);
      await service.load(DateTime(2026, 11, 9, 0, 1));
      expect(calls, 3);
      service.clearCache();
      await service.load(DateTime(2026, 11, 9, 0, 1));
      expect(calls, 6);
    },
  );
}
