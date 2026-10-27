import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/models/match_detail.dart';
import 'package:sports_esports_briefing/features/scores/presentation/team_statistics_table.dart';

void main() {
  final detail = MatchDetail.fromEspn({
    'article': {'headline': 'Game recap', 'story': '<p>Article only.</p>'},
    'boxscore': {
      'teams': [
        {
          'team': {'displayName': 'Chicago Bulls'},
          'statistics': [
            {'name': 'rebounds', 'label': 'Rebounds', 'displayValue': '40'},
            {'name': 'assists', 'label': 'Assists', 'displayValue': '20'},
          ],
        },
        {
          'team': {'displayName': 'Other Team'},
          'statistics': [
            {'name': 'assists', 'label': 'Assists', 'displayValue': '30'},
            {'name': 'rebounds', 'label': 'Rebounds', 'displayValue': '50'},
            {'name': 'blocks', 'label': 'Blocks', 'displayValue': '0'},
          ],
        },
      ],
    },
  });
  test(
    'statistics align by key, preserve missing values and stay out of article',
    () {
      expect(detail.statKeys, ['rebounds', 'assists', 'blocks']);
      expect(detail.teams.first.values['blocks'], isNull);
      expect(detail.teams.last.values['blocks'], '0');
      expect(detail.article, isNot(contains('Rebounds')));
      expect(detail.asText, contains('Rebounds: 40'));
    },
  );
  testWidgets('phone table shows both teams without horizontal scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TeamStatisticsTable(detail: detail)),
      ),
    );
    expect(find.byType(Table), findsOneWidget);
    expect(find.text('리바운드'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(
      tester.getBottomRight(find.text('Other Team')).dx,
      lessThanOrEqualTo(393),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Other Team'), findsOneWidget);
  });
}
