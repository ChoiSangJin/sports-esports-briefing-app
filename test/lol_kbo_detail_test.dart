import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/kbo_detail_service.dart';
import 'package:sports_esports_briefing/features/scores/data/lol_detail_service.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'support/http_fixture.dart';
import 'package:flutter/material.dart';
import 'package:sports_esports_briefing/models/match_detail.dart';
import 'package:sports_esports_briefing/features/scores/presentation/record_sections.dart';

void main() {
  testWidgets('wide player records expand into phone-width two-column tables', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordSections(
              sections: [
                RecordSection(
                  'KIA · 투수 기록',
                  ['선수', '이닝', '삼진', '실점', '자책', '평균자책점'],
                  [
                    ['아주 긴 선수 이름', '9', '10', '0', '0', '0.00'],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('KIA · 투수 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('아주 긴 선수 이름'));
    await tester.pumpAndSettle();
    expect(find.text('평균자책점'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'LoL detail seeks a final window and never labels initial zero frames as final',
    () async {
      final finalData =
          jsonDecode(
                File('test/fixtures/lol_final_window.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      var calls = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((options) {
          calls++;
          if (calls == 1) {
            final initial = jsonDecode(jsonEncode(finalData));
            initial['frames'][0]['gameState'] = 'in_game';
            return jsonResponse(initial);
          }
          expect(options.queryParameters['startingTime'], isNotNull);
          return jsonResponse(finalData);
        });
      final match = UnifiedMatchModel(
        id: 'lol:riot:${finalData['esportsMatchId']}',
        league: League.lol,
        startsAt: DateTime(2026),
        title: 'Final',
        state: MatchState.finalScore,
        detailParameters: {
          'games': jsonEncode([
            {
              'id': finalData['esportsGameId'],
              'number': 1,
              'state': 'completed',
            },
          ]),
        },
      );
      final detail = await LolDetailService(dio).load(match);
      expect(calls, 2);
      expect(detail.notices, isEmpty);
      expect(detail.sections, hasLength(5));
    },
  );
  test(
    'official KBO news links are team-related and remain separate from game evidence',
    () {
      final match = UnifiedMatchModel(
        id: 'kbo:1',
        league: League.kbo,
        startsAt: DateTime(2026),
        title: 'KIA',
        state: MatchState.finalScore,
        participants: const [Participant(name: 'KIA')],
      );
      final news = KboDetailService.parseNews(
        '<ul class="boardPhoto"><li><div class="txt"><strong><a href="View.aspx?bdSe=1">KIA 승리</a></strong><span class="date">2026.10.26</span></div></li><li><div class="txt"><strong><a href="https://bad.example/View.aspx?bdSe=2">KIA other</a></strong></div></li></ul>',
        match,
      );
      expect(news, hasLength(1));
      expect(news.single.url, startsWith('https://www.koreabaseball.com/'));
      expect(news.single.title, contains('2026.10.26'));
    },
  );
  test('verified official final LoL frame provides real player results', () {
    final data =
        jsonDecode(
              File('test/fixtures/lol_final_window.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final sections = LolDetailService.parseWindow(
      data,
      {'111692118851466302': 'Karmine Corp', '98767991877340524': 'Cloud9'},
      '1세트',
      completed: true,
    );
    expect(sections.first.rows.first.take(5).toList(), [
      'KC Canna',
      'Rumble',
      '0/4/0',
      '304',
      '11514',
    ]);
    expect(sections.first.title, contains('Karmine Corp'));
  });
  test(
    'actual KBO boxscore parses hitters, pitchers, totals and decisive plays',
    () {
      final match = UnifiedMatchModel(
        id: 'kbo:20261026HTSS0',
        league: League.kbo,
        startsAt: DateTime(2026, 10, 26),
        title: 'KIA vs 삼성',
        state: MatchState.finalScore,
        participants: const [
          Participant(name: 'KIA'),
          Participant(name: '삼성'),
        ],
      );
      final detail = KboDetailService.parse(
        jsonDecode(File('test/fixtures/kbo_boxscore.json').readAsStringSync())
            as Map<String, dynamic>,
        match,
      );
      expect(detail.teams, hasLength(2));
      expect(detail.teams.first.values['득점'], '5');
      expect(detail.sections, hasLength(4));
      expect(detail.sections.first.rows.first.first, '박정우');
      expect(detail.sections.last.headers, contains('자책'));
      expect(detail.plays.any((p) => p.startsWith('결승타:')), isTrue);
      expect(detail.asText, contains('네일'));
    },
  );
  Map<String, dynamic> window() => {
    'gameMetadata': {
      for (final side in ['blue', 'red'])
        '${side}TeamMetadata': {
          'esportsTeamId': side,
          'participantMetadata': [
            {
              'participantId': side,
              'summonerName': '$side player',
              'championId': 'Ahri',
            },
          ],
        },
    },
    'frames': [
      {
        'rfc460Timestamp': '2026-10-26T12:00:00Z',
        'gameState': 'finished',
        for (final side in ['blue', 'red'])
          '${side}Team': {
            'totalKills': 1,
            'totalGold': 50000,
            'towers': 3,
            'barons': 0,
            'dragons': ['cloud'],
            'participants': [
              {
                'participantId': side,
                'kills': 1,
                'deaths': 0,
                'assists': 2,
                'creepScore': 200,
                'totalGold': 10000,
                'level': 15,
              },
            ],
          },
      },
    ],
  };
  test(
    'LoL feed player mapping follows side metadata rather than series order',
    () {
      final sections = LolDetailService.parseWindow(
        window(),
        {'blue': 'T1', 'red': 'GEN'},
        '1세트',
        completed: true,
      );
      expect(sections.first.title, contains('T1'));
      expect(sections.first.rows.first[2], '1/0/2');
      expect(sections[2].title, contains('GEN'));
      final data = window();
      data['frames'][0]['gameState'] = 'in_game';
      expect(
        () => LolDetailService.parseWindow(data, {}, '1세트', completed: true),
        throwsFormatException,
      );
    },
  );
  test(
    'unavailable LoL detailed feed keeps set records and reports missing data',
    () async {
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((_) => jsonResponse({}, status: 404));
      final match = UnifiedMatchModel(
        id: 'lol:riot:1',
        league: League.lol,
        startsAt: DateTime(2026),
        title: 'Final',
        state: MatchState.finalScore,
        detailParameters: {
          'games': jsonEncode([
            {'id': '123', 'number': 1, 'state': 'completed'},
          ]),
        },
      );
      final detail = await LolDetailService(dio).load(match);
      expect(detail.sections.single.rows.single, ['1세트', '종료']);
      expect(detail.notices.single, contains('조회할 수 없습니다'));
      expect(detail.asText, isNot(contains('K/D/A')));
    },
  );
}
