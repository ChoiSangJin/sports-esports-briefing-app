import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/models/match_detail.dart';
import 'package:sports_esports_briefing/features/scores/presentation/compact_table.dart';

void main() {
  test(
    'MLB and NFL nested categories preserve same-name stats independently',
    () {
      final detail = MatchDetail.fromEspn({
        'boxscore': {
          'teams': [
            {
              'team': {'displayName': 'Team'},
              'statistics': [
                {
                  'name': 'batting',
                  'displayName': 'Batting',
                  'stats': [
                    {
                      'name': 'hits',
                      'displayName': 'Hits',
                      'displayValue': '16',
                    },
                  ],
                },
                {
                  'name': 'pitching',
                  'displayName': 'Pitching',
                  'stats': [
                    {
                      'name': 'hits',
                      'displayName': 'Hits',
                      'displayValue': '3',
                    },
                  ],
                },
                {
                  'name': 'passing',
                  'displayName': 'Passing',
                  'statistics': [
                    {'name': 'yards', 'label': 'Yards', 'displayValue': '250'},
                  ],
                },
              ],
            },
          ],
        },
      });
      expect(detail.teams.single.values, {
        'batting/hits': '16',
        'pitching/hits': '3',
        'passing/yards': '250',
      });
      expect(detail.label('pitching/hits'), 'Pitching · Hits');
    },
  );
  test(
    'news links stay distinct from recap and are excluded from AI game evidence',
    () {
      final detail = MatchDetail.fromEspn({
        'news': {
          'articles': [
            {
              'type': 'Story',
              'headline': 'Related story',
              'description': 'Not this game',
              'links': {
                'web': {'href': 'https://www.espn.com/story'},
              },
            },
            {
              'type': 'Story',
              'headline': 'unsafe',
              'links': {
                'web': {'href': 'javascript:bad'},
              },
            },
          ],
        },
        'plays': [
          {'scoringPlay': true, 'text': 'A scored.'},
          {'scoringPlay': false, 'text': 'Other play'},
        ],
      });
      expect(detail.article, isEmpty);
      expect(detail.news.single.title, 'Related story');
      expect(detail.asText, contains('A scored.'));
      expect(detail.asText, isNot(contains('Not this game')));
    },
  );
  testWidgets(
    '320px table wraps long labels and team names at enlarged text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: CompactTable(
                  headers: const [
                    '아주 긴 통계 항목 이름',
                    'Minnesota Timberwolves',
                    'Tampa Bay Rays',
                  ],
                  rows: const [
                    ['OffensiveReboundsLongLabel', '12345678901234567890', '0'],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(Table)).width, 320);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
