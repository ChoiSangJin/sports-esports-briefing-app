import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/korean_league_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'support/http_fixture.dart';

dynamic fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());
void main() {
  test(
    'official K League fixture maps clubs, completed score and official link',
    () {
      final m = KoreanLeagueService.parseKleague(
        fixture('kleague_schedule.json'),
        League.kleague1,
      ).first;
      expect(m.state, MatchState.finalScore);
      expect(m.participants.first.name, '부천');
      expect(m.participants.first.score, '3');
      expect(m.sourceUrl, contains('gameId=4'));
      expect(m.startsAt.toUtc(), DateTime.utc(2026, 3, 1, 5));
    },
  );
  test(
    'scheduled zeros hidden; halftime and postponement retain explicit state',
    () {
      final raw = fixture('kleague_schedule.json');
      final g = raw['data']['scheduleList'].first;
      raw['data']['scheduleList'] = [g];
      for (final entry in {
        'NS': MatchState.scheduled,
        'HT': MatchState.live,
        'PP': MatchState.cancelled,
        'CAN': MatchState.cancelled,
      }.entries) {
        g['gameStatus'] = entry.key;
        final m = KoreanLeagueService.parseKleague(raw, League.kleague1).single;
        expect(m.state, entry.value);
        if (entry.value != MatchState.live) {
          expect(m.participants.first.score, isNull);
        }
      }
    },
  );
  test(
    'past empty day never changes to upcoming; no rank API requested',
    () async {
      var scheduleCalls = 0;
      final raw = fixture('kleague_schedule.json');
      raw['data']['scheduleList'] = [raw['data']['scheduleList'].first];
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((o) {
          if (o.path.contains('/getScheduleList.do')) {
            scheduleCalls++;
            return jsonResponse(raw);
          }
          throw const FormatException('Rank unavailable');
        });
      final repo = ScoreRepository(dio, clock: () => DateTime(2026, 11, 9));
      final result = await repo.load(League.kleague1, DateTime(2026, 3, 1));
      expect(result.matches, isNotEmpty);
      expect(result.warning, isNull);
      expect(result.isUpcoming, isFalse);
      final empty = await repo.load(League.kleague1, DateTime(2026, 3, 31));
      expect(empty.matches, isEmpty);
      expect(empty.isUpcoming, isFalse);
      // A UTC-local last day also encloses the next KST month.
      expect(scheduleCalls, inInclusiveRange(1, 2));
    },
  );
  test(
    'next-game search is monthly and only uses future scheduled games',
    () async {
      final raw = fixture('kleague_schedule.json');
      final g = raw['data']['scheduleList'].first;
      raw['data']['scheduleList'] = [g];
      g['gameDate'] = '2026.11.10';
      g['gameStatus'] = 'NS';
      g['endYn'] = 'N';
      final dio = Dio()
        ..httpClientAdapter = HttpFixture(
          (o) =>
              jsonResponse(o.path.contains('/getScheduleList.do') ? raw : {}),
        );
      final r = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 11, 9),
      ).load(League.kleague1, DateTime(2026, 11, 9));
      expect(r.isUpcoming, isTrue);
      expect(r.matches.single.participants.first.score, isNull);
    },
  );
}
