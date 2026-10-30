import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/season_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'score_repository_test.dart' show FixtureAdapter;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, Object> season(int year, String start, String end) => {
    'leagues': [
      {
        'season': {'year': year, 'startDate': start, 'endDate': end},
      },
    ],
    'events': <Object>[],
  };
  test('postseason stays active even with no games', () async {
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter(
        (_) => season(2026, '2026-02-19', '2026-11-12'),
      );
    expect(
      await SeasonService(dio).notice('baseball/mlb', DateTime(2026, 10, 30)),
      isNull,
    );
  });
  test(
    'ended season reports verified next calendar and caches for a day',
    () async {
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          calls++;
          return r.queryParameters['dates'] == '2027'
              ? season(2027, '2027-02-20', '2027-11-12')
              : season(2026, '2026-02-19', '2026-11-12');
        });
      final service = SeasonService(dio);
      final notice = await service.notice('baseball/mlb', DateTime(2026, 12));
      expect(notice, contains('2026 시즌 일정 종료'));
      expect(notice, contains('2027.02.20'));
      expect(notice, contains('프리시즌 포함'));
      await service.notice('baseball/mlb', DateTime(2026, 12, 1, 12));
      expect(calls, 2);
      await service.notice('baseball/mlb', DateTime(2026, 12, 2));
      expect(calls, 4);
    },
  );
  test('repeated old year is not an announced next opening', () async {
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter(
        (_) => season(2025, '2025-02-19', '2025-11-12'),
      );
    expect(
      await SeasonService(dio).notice('baseball/mlb', DateTime(2026)),
      contains('확인되지 않았습니다'),
    );
  });
  test(
    'metadata errors and missing boundaries never imply season ended',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((_) => {'events': []});
      expect(
        await SeasonService(dio).notice('baseball/mlb', DateTime(2026)),
        isNull,
      );
    },
  );
  test('verified offseason skips daily match scan', () async {
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter((_) {
        calls++;
        return season(2025, '2025-02-19', '2025-11-12');
      });
    final result = await ScoreRepository(dio).load(League.mlb, DateTime.now());
    expect(result.seasonNotice, contains('시즌 일정 종료'));
    expect(result.warning, isNull);
    expect(calls, 2);
  });
  test(
    'historical records are retrieved even when current season ended',
    () async {
      var metadataCalls = 0;
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((r) {
          if (r.queryParameters['dates'] == null) metadataCalls++;
          return {'events': []};
        });
      await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 12),
      ).load(League.mlb, DateTime(2026, 10, 27));
      expect(metadataCalls, 0);
    },
  );
  test(
    'F1 requires final round results before claiming season ended',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (r) => {
            'MRData': {
              'RaceTable': {
                'Races': r.uri.path.contains('/results')
                    ? []
                    : [
                        {
                          'season': '2026',
                          'round': '24',
                          'date': '2026-12-06',
                          'time': '12:00:00Z',
                          'raceName': 'Final GP',
                        },
                      ],
              },
            },
          },
        );
      expect(
        await SeasonService(dio).notice('f1', DateTime(2026, 12, 10)),
        isNull,
      );
    },
  );
  test('F1 confirmed final round links to the next opening', () async {
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter(
        (r) => {
          'MRData': {
            'RaceTable': {
              'Races': [
                if (r.uri.path.contains('2027'))
                  {
                    'season': '2027',
                    'round': '1',
                    'date': '2027-03-07',
                    'time': '12:00:00Z',
                    'raceName': 'Opening GP',
                  }
                else
                  {
                    'season': '2026',
                    'round': '24',
                    'date': '2026-12-06',
                    'time': '12:00:00Z',
                    'raceName': 'Final GP',
                    if (r.uri.path.contains('/results'))
                      'Results': [
                        {'position': '1'},
                      ],
                  },
              ],
            },
          },
        },
      );
    final notice = await SeasonService(
      dio,
    ).notice('f1', DateTime(2026, 12, 10));
    expect(notice, contains('시즌 종료'));
    expect(notice, contains('2027.03.07'));
  });
  test('daily season cache survives repository restart', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    var calls = 0;
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter((_) {
        calls++;
        return season(2025, '2025-02-19', '2025-11-12');
      });
    await SeasonService(
      dio,
      preferences: preferences,
    ).notice('baseball/mlb', DateTime(2026));
    final firstCalls = calls;
    expect(
      await SeasonService(
        dio,
        preferences: preferences,
      ).notice('baseball/mlb', DateTime(2026, 1, 1, 12)),
      contains('시즌 일정 종료'),
    );
    expect(calls, firstCalls);
  });
  test(
    'opening boundary expires cache so live scores are not hidden',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (_) => season(2026, '2026-03-01T12:00:00', '2026-11-12'),
        );
      final service = SeasonService(dio);
      expect(
        await service.notice('baseball/mlb', DateTime(2026, 3, 1, 10)),
        contains('시작 예정'),
      );
      expect(
        await service.notice('baseball/mlb', DateTime(2026, 3, 1, 13)),
        isNull,
      );
    },
  );
  test(
    'published next season already underway overrides old season metadata',
    () async {
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter(
          (r) => r.queryParameters['dates'] == '2026'
              ? season(2026, '2026-02-19', '2026-11-12')
              : season(2025, '2025-02-19', '2025-11-12'),
        );
      expect(
        await SeasonService(dio).notice('baseball/mlb', DateTime(2026, 4)),
        isNull,
      );
    },
  );
  test(
    'explicit offseason phase is respected before calendar cutoff',
    () async {
      final payload = season(2026, '2026-02-19', '2026-11-12');
      final league = (payload['leagues'] as List).first as Map;
      (league['season'] as Map)['type'] = {'type': 4, 'name': 'Off Season'};
      final dio = Dio()..httpClientAdapter = FixtureAdapter((_) => payload);
      expect(
        await SeasonService(dio).notice('baseball/mlb', DateTime(2026, 11, 5)),
        contains('시즌 일정 종료'),
      );
    },
  );
}
