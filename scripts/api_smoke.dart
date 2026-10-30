// Run with: flutter test scripts/api_smoke.dart --reporter expanded
// This is an explicit live audit, not part of the offline CI suite.
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/features/scores/data/lol_schedule_service.dart';
import 'package:sports_esports_briefing/features/scores/data/match_adapters.dart';
import 'package:sports_esports_briefing/features/scores/data/season_service.dart';
import 'package:sports_esports_briefing/features/scores/data/kbo_season_service.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';

void main() {
  test(
    'all six live schedule and detail providers',
    () async {
      HttpOverrides.global = null;
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final proxy = Platform.environment['HTTPS_PROXY'];
      if (proxy != null && proxy.isNotEmpty) {
        final uri = Uri.parse(proxy);
        final context = SecurityContext(withTrustedRoots: true);
        final cert = Platform.environment['CODEX_PROXY_CERT'];
        if (cert != null) context.setTrustedCertificates(cert);
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () =>
              HttpClient(context: context)
                ..findProxy = (_) => 'PROXY ${uri.host}:${uri.port}',
        );
      }
      try {
        final repository = ScoreRepository(dio);
        final now = DateTime.now();
        final results = await Future.wait(
          League.values.map(
            (league) =>
                repository.load(league, DateTime(now.year, now.month, now.day)),
          ),
        );
        for (final r in results) {
          stdout.writeln(
            '${r.league.label}: ${r.matches.length} matches; season=${r.seasonNotice != null}; warning=${r.warning ?? "none"}',
          );
        }
        for (final league in [League.mlb, League.nba, League.nfl, League.kbo]) {
          final day = league == League.kbo
              ? DateTime(2026, 10, 26)
              : DateTime(2026, 10, 27);
          final result = await repository.load(league, day);
          expect(
            result.warning,
            isNull,
            reason: '${league.label} archive: ${result.warning}',
          );
          final match = result.matches.firstWhere(
            (m) => m.state == MatchState.finalScore,
          );
          final detail = await repository.details(match);
          stdout.writeln(
            '${league.label} detail: teams=${detail.teams.length}, sections=${detail.sections.length}, plays=${detail.plays.length}, news=${detail.news.length}, notices=${detail.notices.length}',
          );
          expect(
            detail.teams.isNotEmpty || detail.sections.isNotEmpty,
            isTrue,
            reason: '${league.label} verified records missing',
          );
        }
        final lol = await LolScheduleService(dio).load();
        final match = lol.lastWhere((m) => m.state == MatchState.finalScore);
        final detail = await repository.details(match);
        stdout.writeln(
          'LoL detail: ${detail.sections.length} sections, ${detail.notices.length} notices',
        );
        expect(detail.sections, isNotEmpty);
        final response = await dio.get<Json>(
          'https://api.jolpi.ca/ergast/f1/${now.year}.json',
          queryParameters: {'limit': 100},
        );
        final races = JolpicaAdapter.schedule(response.data!)
            .where(
              (m) =>
                  m.startsAt.isBefore(now.subtract(const Duration(hours: 6))),
            )
            .toList();
        final race = races.last;
        final local = race.startsAt.toLocal();
        final f1 = await repository.load(
          League.f1,
          DateTime(local.year, local.month, local.day),
        );
        expect(f1.warning, isNull);
        expect(f1.matches.single.standings, isNotEmpty);
        stdout.writeln(
          'F1 latest completed: ${f1.matches.single.title}, drivers=${f1.matches.single.standings.length}',
        );
        final nbaFinals = await dio.get<Json>(
          'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard',
          queryParameters: {'dates': '202606', 'limit': 100},
        );
        expect(
          SeasonService.championshipWinner(
            nbaFinals.data!,
            2026,
            DateTime(2026, 6, 15),
            'basketball/nba',
          ),
          'New York Knicks',
        );
        final nflFinal = await dio.get<Json>(
          'https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard',
          queryParameters: {'dates': '202602', 'limit': 100},
        );
        expect(
          SeasonService.championshipWinner(
            nflFinal.data!,
            2025,
            DateTime(2026, 2, 10),
            'football/nfl',
          ),
          'Seattle Seahawks',
        );
        expect(
          await KboSeasonService(dio).notice(DateTime(2025, 11, 5)),
          contains('한국시리즈 우승: LG'),
        );
        stdout.writeln(
          'NBA/NFL/KBO historical championship clinches verified from live official/provider responses',
        );
      } finally {
        dio.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
