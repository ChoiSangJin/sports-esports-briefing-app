import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/lol_detail_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'package:sports_esports_briefing/models/match_detail.dart';
import 'support/http_fixture.dart';

void main() {
  test(
    'recent LoL final never requests future timestamp and returns real players',
    () async {
      final data =
          jsonDecode(
                File('test/fixtures/lol_final_window.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final now = DateTime.utc(2026, 10, 31, 0, 30);
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((r) {
          calls++;
          if (calls == 1) {
            final initial = jsonDecode(jsonEncode(data));
            for (final frame in initial['frames']) {
              frame['rfc460Timestamp'] = '2026-10-30T20:01:00Z';
              frame['gameState'] = 'in_game';
            }
            return jsonResponse(initial);
          }
          final requested = DateTime.parse(
            r.queryParameters['startingTime'] as String,
          );
          if (requested.isAfter(now.subtract(const Duration(seconds: 30)))) {
            return jsonResponse({}, status: 400);
          }
          return jsonResponse(data);
        });
      final match = UnifiedMatchModel(
        id: 'lol:riot:${data['esportsMatchId']}',
        league: League.lol,
        startsAt: DateTime(2026),
        title: 'Final',
        state: MatchState.finalScore,
        detailParameters: {
          'games': jsonEncode([
            {'id': data['esportsGameId'], 'number': 1, 'state': 'completed'},
          ]),
        },
      );
      final detail = await LolDetailService(dio, clock: () => now).load(match);
      expect(calls, 2);
      expect(detail.notices, isEmpty);
      expect(
        detail.sections.where((s) => s.headers.contains('챔피언')),
        hasLength(2),
      );
    },
  );
  test('ESPN preview recent games are separate verified sections', () {
    final d = MatchDetail.fromEspn({
      'lastFiveGames': [
        {
          'team': {'displayName': 'Chelsea'},
          'events': [
            {
              'gameDate': '2026-10-20T12:00Z',
              'opponent': {'displayName': 'Arsenal'},
              'gameResult': 'D',
              'score': '1-1',
            },
          ],
        },
      ],
    });
    expect(d.article, isEmpty);
    expect(d.sections.single.rows.single, contains('무'));
    expect(d.asText, contains('최근 경기'));
    expect(d.asText, contains('Arsenal'));
  });
  test(
    'scheduled KBO supplies explicit search and official links without inventing article',
    () async {
      final match = UnifiedMatchModel(
        id: 'kbo:20261101',
        league: League.kbo,
        startsAt: DateTime.utc(2026, 11, 1, 9),
        title: 'KIA vs 삼성',
        state: MatchState.scheduled,
        source: 'KBO',
        sourceUrl:
            'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx',
        participants: const [
          Participant(name: 'KIA'),
          Participant(name: '삼성'),
        ],
      );
      final d = await ScoreRepository(Dio()).details(match);
      expect(d.article, isEmpty);
      expect(d.news, hasLength(2));
      expect(
        Uri.parse(d.news.first.url).queryParameters['query'],
        contains('KIA 삼성 2026.11.01'),
      );
      expect(d.asText, isNot(contains('뉴스 검색')));
      expect(d.asText, isNot(contains('검색 결과')));
    },
  );
}
