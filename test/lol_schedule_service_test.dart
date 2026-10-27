import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/lol_schedule_service.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'support/http_fixture.dart';

void main() {
  late String payload, page;
  setUp(() {
    payload = File('test/fixtures/lol_official_events.json').readAsStringSync();
    // The real official page contains unrelated JS undefined values. They must
    // never be executed or globally replaced to parse the isolated JSON data.
    page =
        '<script>(window.transport ??= []).push({"unrelated":undefined,"esports":$payload})</script>';
  });

  test(
    'official fixture yields completed and future matches across LoL leagues',
    () {
      final matches = LolScheduleService.parse(page);
      expect(matches, hasLength(3));
      expect(matches.every((m) => m.source == 'LoL e스포츠 공식 일정'), isTrue);
      expect(matches.every((m) => m.id.startsWith('lol:riot:')), isTrue);
      final upcoming = matches.singleWhere(
        (m) => m.state == MatchState.scheduled,
      );
      expect(upcoming.participants.every((p) => p.score == null), isTrue);
      final worlds = matches.singleWhere(
        (m) => m.state == MatchState.finalScore && m.title.contains('월드'),
      );
      expect(worlds.participants.where((p) => p.winner), hasLength(1));
      expect(matches.any((m) => m.title.contains('CBLOL')), isTrue);
      expect(
        upcoming.participants.every(
          (p) => p.logo?.startsWith('https://') == true,
        ),
        isTrue,
      );
    },
  );

  test(
    'SSR duplicates do not create duplicate games and quoted braces are safe',
    () {
      final changed = (jsonDecode(payload) as Map<String, dynamic>);
      changed['events'][0]['matchTeams'][0]['name'] = 'Team } "quoted" \\ name';
      final block = '"esports":${jsonEncode(changed)}';
      final matches = LolScheduleService.parse(
        '<script>{$block,$block}</script>',
      );
      expect(matches, hasLength(3));
      expect(
        matches.any(
          (m) => m.participants.first.name == 'Team } "quoted" \\ name',
        ),
        isTrue,
      );
    },
  );

  test('schema errors are distinct from a valid empty schedule', () {
    expect(
      () => LolScheduleService.parse('<html>Maintenance</html>'),
      throwsFormatException,
    );
    expect(LolScheduleService.parse('"esports":{"events":[]}'), isEmpty);
  });

  test(
    'manual refresh clears page cache and repository filters local dates',
    () async {
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((options) {
          requests++;
          return textResponse(page);
        });
      final repository = ScoreRepository(dio);
      final first = LolScheduleService.parse(page).first;
      final local = first.startsAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final feed = await repository.load(League.lol, day);
      expect(feed.warning, isNull);
      expect(feed.matches.every((m) => sameDay(m.startsAt, day)), isTrue);
      await repository.load(League.lol, day);
      expect(requests, 1);
      repository.clearCache();
      await repository.load(League.lol, day);
      expect(requests, 2);
      final outside = await repository.load(League.lol, DateTime(2000));
      expect(outside.warning, contains('범위 밖'));
    },
  );
}
