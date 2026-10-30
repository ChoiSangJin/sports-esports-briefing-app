import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/season_service.dart';
import 'package:sports_esports_briefing/features/scores/data/kbo_season_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'score_repository_test.dart' show FixtureAdapter;
import 'support/http_fixture.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;
void main() {
  test(
    'actual NBA finals clinch identifies champion while conference finals do not',
    () {
      final j = fixture('nba_championship');
      expect(
        SeasonService.championshipWinner(
          j,
          2026,
          DateTime(2026, 6, 15),
          'basketball/nba',
        ),
        'New York Knicks',
      );
      j['events'][0]['competitions'][0]['notes'][0]['headline'] =
          'Eastern Conference Finals - Game 5';
      expect(
        SeasonService.championshipWinner(
          j,
          2026,
          DateTime(2026, 6, 15),
          'basketball/nba',
        ),
        isNull,
      );
    },
  );
  test(
    'NFL Super Bowl belongs to previous season year and Pro Bowl never ends season',
    () {
      final j = fixture('nfl_championship');
      expect(
        SeasonService.championshipWinner(
          j,
          2025,
          DateTime(2026, 2, 10),
          'football/nfl',
        ),
        'Seattle Seahawks',
      );
      expect(
        SeasonService.championshipWinner(
          j,
          2026,
          DateTime(2026, 2, 10),
          'football/nfl',
        ),
        isNull,
      );
      j['events'][0]['competitions'][0]['notes'][0]['headline'] =
          'Pro Bowl Games';
      expect(
        SeasonService.championshipWinner(
          j,
          2025,
          DateTime(2026, 2, 10),
          'football/nfl',
        ),
        isNull,
      );
    },
  );
  for (final sport in ['nba', 'nfl']) {
    test(
      '$sport actual championship overrides later calendar cutoff',
      () async {
        final j = fixture('${sport}_championship');
        final year = sport == 'nba' ? 2026 : 2025;
        j['leagues'] = [
          {
            'season': {
              'year': year,
              'startDate': '$year-08-01',
              'endDate': '${year + 1}-07-01',
              'type': {'type': 3, 'name': 'Postseason'},
            },
          },
        ];
        // NBA spans the preceding calendar year.
        if (sport == 'nba') {
          j['leagues'][0]['season']['startDate'] = '2025-08-01';
        }
        final dio = Dio()..httpClientAdapter = FixtureAdapter((_) => j);
        final now = sport == 'nba'
            ? DateTime(2026, 6, 15)
            : DateTime(2026, 2, 10);
        final path = sport == 'nba' ? 'basketball/nba' : 'football/nfl';
        expect(await SeasonService(dio).notice(path, now), contains('시즌 종료'));
      },
    );
  }
  test('KBO actual Korean Series requires four distinct completed wins', () {
    final rows = fixture('kbo_korean_series')['rows'] as List;
    expect(
      KboSeasonService.championFromRows(rows, 2025, DateTime(2025, 11, 5)),
      'LG',
    );
    expect(
      KboSeasonService.championFromRows(
        rows.take(3).toList(),
        2025,
        DateTime(2025, 11, 5),
      ),
      isNull,
    );
    expect(
      KboSeasonService.championFromRows(
        [...rows.take(3), ...rows.take(3)],
        2025,
        DateTime(2025, 11, 5),
      ),
      isNull,
    );
    expect(
      KboSeasonService.championFromRows(rows, 2026, DateTime(2026, 11, 5)),
      isNull,
    );
    expect(
      KboSeasonService.championFromRows(rows, 2025, DateTime(2025, 10, 26)),
      isNull,
    );
  });
  test(
    'KBO uses official next date to find games beyond fourteen days',
    () async {
      final game =
          (fixture('kbo-final')['game'] as List).first as Map<String, dynamic>;
      game.addAll({
        'G_ID': '20261120HTSS0',
        'G_DT': '20261120',
        'GAME_STATE_SC': '1',
        'GAME_RESULT_CK': 0,
      });
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          if (r.uri.path.endsWith('GetScheduleList')) return {'rows': []};
          if (r.uri.path.endsWith('GetKboGameDate')) {
            return {'code': '100', 'AFTER_G_DT': '20261120'};
          }
          final date = (r.data as Map)['date'];
          return {
            'code': '100',
            'game': date == '20261120' ? [game] : [],
          };
        });
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 10, 30),
      ).load(League.kbo, DateTime(2026, 10, 30));
      expect(result.warning, isNull);
      expect(result.isUpcoming, isTrue);
      expect(result.matches.single.id, 'kbo:20261120HTSS0');
    },
  );
  test(
    'KBO unpublished next date is an information notice rather than a network error',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          if (r.uri.path.endsWith('GetScheduleList')) return {'rows': []};
          if (r.uri.path.endsWith('GetKboGameDate')) {
            return {'code': '100', 'AFTER_G_DT': ''};
          }
          return {'code': '100', 'game': []};
        });
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 10, 30),
      ).load(League.kbo, DateTime(2026, 10, 30));
      expect(result.warning, isNull);
      expect(result.seasonNotice, contains('아직 공개되지'));
    },
  );
  test(
    'LoL outside published schedule is never called entire season ended',
    () async {
      final payload = File(
        'test/fixtures/lol_official_events.json',
      ).readAsStringSync();
      final dio = Dio()
        ..httpClientAdapter = HttpFixture(
          (_) => textResponse('"esports":$payload'),
        );
      final result = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 10, 30),
      ).load(League.lol, DateTime(2030));
      expect(result.warning, isNull);
      expect(result.seasonNotice, contains('전체 시즌 종료를 뜻하지 않습니다'));
    },
  );
  test(
    'F1 January without a new calendar verifies previous season final results',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          final race = <String, dynamic>{
            'season': '2026',
            'round': '24',
            'date': '2026-12-06',
            'time': '12:00:00Z',
            'raceName': 'Final GP',
          };
          if (r.uri.path.contains('/24/results')) {
            race['Results'] = [
              {'position': '1'},
            ];
          }
          return {
            'MRData': {
              'RaceTable': {
                'Races': r.uri.path.contains('/2026') ? [race] : [],
              },
            },
          };
        });
      expect(
        await SeasonService(dio).notice('f1', DateTime(2027, 1, 10)),
        contains('F1 2026 시즌 종료'),
      );
    },
  );
  test(
    'KBO winter uses previous Korean Series and published next-season date',
    () async {
      final rows = fixture('kbo_korean_series')['rows'];
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          if (r.uri.path.endsWith('GetKboGameDate')) {
            return {'code': '100', 'AFTER_G_DT': '20260310'};
          }
          expect((r.data as Map)['seasonId'], '2025');
          return {'rows': (r.data as Map)['gameMonth'] == '10' ? rows : []};
        });
      final notice = await KboSeasonService(dio).notice(DateTime(2026, 1, 10));
      expect(notice, contains('KBO 2025 시즌 종료'));
      expect(notice, contains('20260310'));
      expect(notice, contains('시범경기'));
    },
  );
}
