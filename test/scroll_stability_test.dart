import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/main.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'package:sports_esports_briefing/services/providers.dart';

class RefreshRepository extends ScoreRepository {
  RefreshRepository() : super(Dio());
  final calls = <League, int>{};
  Completer<LeagueResult>? refresh;
  LeagueResult result(League league) => LeagueResult(league, [
    for (var i = 0; i < 3; i++)
      UnifiedMatchModel(
        id: '${league.name}:$i',
        league: league,
        startsAt: DateTime.now(),
        title: '${league.label} $i',
        state: MatchState.live,
        participants: [
          Participant(name: '${league.label} 홈 $i', score: '2'),
          Participant(name: '${league.label} 원정 $i', score: '1'),
        ],
      ),
  ]);
  @override
  Future<LeagueResult> load(League league, DateTime day) async {
    calls[league] = (calls[league] ?? 0) + 1;
    if (league == League.lol && refresh != null) return refresh!.future;
    return result(league);
  }
}

void main() {
  testWidgets(
    'scrolling never reloads offscreen leagues; background refresh preserves position and cards',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'favorite_leagues': ['kleague2', 'kbl', 'kleague1'],
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = RefreshRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            repositoryProvider.overrideWithValue(repo),
            keyPresentProvider.overrideWith((ref) async => false),
          ],
          child: const BriefingApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('현재 순위'), findsNothing);
      expect(find.text('K리그 2'), findsNothing);
      expect(find.text('KBL'), findsNothing);
      final scroll = find.byType(SingleChildScrollView).last;
      await tester.drag(scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      final state = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      final before = state.position.pixels;
      expect(before, greaterThan(0));
      final calls = Map<League, int>.of(repo.calls);
      await tester.drag(scroll, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(repo.calls, calls);
      final offset = state.position.pixels;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(repo.calls, calls); // Automatic refresh is paused while reading.
      expect(state.position.pixels, closeTo(offset, 0.1));
      repo.refresh = Completer<LeagueResult>();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(BriefingApp)),
      );
      container.invalidate(leagueScoresProvider(League.lol));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('K리그 1 홈 0'), findsOneWidget);
      expect(state.position.pixels, closeTo(offset, 0.1));
      repo.refresh!.complete(repo.result(League.lol));
      await tester.pumpAndSettle();
      expect(state.position.pixels, closeTo(offset, 0.1));
      state.position.jumpTo(0);
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(repo.calls[League.lol], 3); // Resumes after returning to the top.
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
