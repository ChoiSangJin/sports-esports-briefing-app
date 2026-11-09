import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/korean_league_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/features/scores/presentation/record_sections.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'support/http_fixture.dart';

dynamic fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());
void main() {
  test('official KBL fixture keeps completed scores, KST and stadium', () {
    final result = KoreanLeagueService.parseKbl(fixture('kbl_schedule.json'));
    final m = result.first;
    expect(m.state, MatchState.finalScore);
    expect(m.startsAt.toUtc(), DateTime.utc(2026, 4, 1, 10));
    expect(m.participants.map((p) => p.score), ['79', '81']);
    expect(m.participants.last.winner, isTrue);
    expect(m.report, contains('tvN SPORTS'));
  });
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
    'past empty day never changes to upcoming; rank failure keeps schedule',
    () async {
      var scheduleCalls = 0;
      final raw = [fixture('kbl_schedule.json').first];
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((o) {
          if (o.path.contains('/match/list')) {
            scheduleCalls++;
            return jsonResponse(raw);
          }
          throw const FormatException('Rank unavailable');
        });
      final repo = ScoreRepository(dio, clock: () => DateTime(2026, 11, 9));
      final result = await repo.load(League.kbl, DateTime(2026, 4, 1));
      expect(result.matches, isNotEmpty);
      expect(result.warning, contains('순위'));
      expect(result.isUpcoming, isFalse);
      final empty = await repo.load(League.kbl, DateTime(2026, 4, 30));
      expect(empty.matches, isEmpty);
      expect(empty.isUpcoming, isFalse);
      // A UTC-local last day also encloses the next KST month.
      expect(scheduleCalls, inInclusiveRange(1, 2));
    },
  );
  test(
    'next-game search is monthly and only uses future scheduled games',
    () async {
      final raw = fixture('kbl_schedule.json');
      final g = raw.first;
      g['gameDate'] = '20261110';
      g['isEnded'] = 0;
      g['isStarted'] = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture(
          (o) => jsonResponse(o.path.contains('/match/list') ? [g] : []),
        );
      final r = await ScoreRepository(
        dio,
        clock: () => DateTime(2026, 11, 9),
      ).load(League.kbl, DateTime(2026, 11, 9));
      expect(r.isUpcoming, isTrue);
      expect(r.matches.single.participants.first.score, isNull);
    },
  );
  testWidgets(
    'current standings fit a narrow phone without sideways scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sections = KoreanLeagueService.parseStandings(
        [
          {'rank': 1, 'tnameF': '대구 한국가스공사 페가수스', 'win': 25, 'loss': 10},
        ],
        League.kbl,
        DateTime(2026, 11, 9),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordSections(sections: sections),
            ),
          ),
        ),
      );
      await tester.tap(find.text(sections.single.title));
      await tester.pumpAndSettle();
      expect(find.text('대구 한국가스공사 페가수스'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
