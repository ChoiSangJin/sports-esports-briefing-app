import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/main.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'package:sports_esports_briefing/services/providers.dart';
import 'dashboard_test.dart' show FixtureRepository, NoKeys;

class LongReportRepository extends FixtureRepository {
  @override
  Future<String> detail(UnifiedMatchModel match) async =>
      List.filled(80, 'Long report paragraph.').join('\n');
}

void main() {
  for (final inset in [24.0, 48.0]) {
    testWidgets(
      'last report line stays above Android navigation inset $inset',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = FakeViewPadding(bottom: inset);
        tester.view.viewPadding = FakeViewPadding(bottom: inset);
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              preferencesProvider.overrideWithValue(preferences),
              repositoryProvider.overrideWithValue(LongReportRepository()),
              keyStorageProvider.overrideWithValue(NoKeys()),
            ],
            child: const BriefingApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'NBA'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'NBA'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).last, const Offset(0, -20000));
        await tester.pumpAndSettle();
        expect(
          tester.getBottomRight(find.byType(SelectableText).last).dy,
          lessThanOrEqualTo(852 - inset),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
