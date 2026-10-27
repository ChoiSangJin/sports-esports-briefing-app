import 'package:dio/dio.dart';
import '../../../models/unified_match_model.dart';
import 'match_adapters.dart';
import 'kbo_scraper_service.dart';

class LeagueResult {
  const LeagueResult(this.league, this.matches, [this.warning]);
  final League league;
  final List<UnifiedMatchModel> matches;
  final String? warning;
}

class ScoreRepository {
  ScoreRepository(this.dio);
  final Dio dio;
  static const paths = {
    League.nfl: 'football/nfl',
    League.nba: 'basketball/nba',
    League.mlb: 'baseball/mlb',
  };

  Future<LeagueResult> load(League league, DateTime day) async {
    try {
      List<UnifiedMatchModel> matches;
      if (paths.containsKey(league)) {
        String date(DateTime d) =>
            '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
        // ESPN groups games by US dates. Enclose the device-local day so Korean
        // morning games are not lost, then filter on the actual event timestamp.
        final responses = await Future.wait([
          for (var offset = -1; offset <= 1; offset++)
            dio.get<Json>(
              'https://site.api.espn.com/apis/site/v2/sports/${paths[league]}/scoreboard',
              queryParameters: {
                'dates': date(DateTime(day.year, day.month, day.day + offset)),
                'limit': 100,
              },
            ),
        ]);
        matches = {
          for (final r in responses)
            for (final match in EspnAdapter.parse(r.data!, league))
              match.id: match,
        }.values.toList();
      } else if (league == League.f1) {
        final r = await dio.get<Json>(
          'https://api.jolpi.ca/ergast/f1/${day.year}/results.json',
          queryParameters: {'limit': 2000},
        );
        matches = JolpicaAdapter.parse(r.data!);
      } else if (league == League.lol) {
        // Query a UTC window enclosing the selected local day, then filter locally.
        final start = DateTime(day.year, day.month, day.day).toUtc();
        final end = DateTime(day.year, day.month, day.day + 1).toUtc();
        String cargoDate(DateTime d) =>
            d.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
        final r = await dio.get<Json>(
          'https://lol.fandom.com/api.php',
          queryParameters: {
            'action': 'cargoquery',
            'format': 'json',
            'tables': 'MatchSchedule',
            'fields':
                'Team1,Team2,Team1Score,Team2Score,Winner,DateTime_UTC,Tab,ShownName,MatchId',
            'where':
                "(ShownName LIKE '%LCK%' OR ShownName LIKE '%Worlds%' OR ShownName LIKE '%MSI%') AND DateTime_UTC >= '${cargoDate(start)}' AND DateTime_UTC < '${cargoDate(end)}'",
            'order_by': 'DateTime_UTC ASC',
            'limit': 100,
          },
        );
        if (r.data?.containsKey('error') == true) {
          throw const FormatException('Cargo error');
        }
        matches = LeaguepediaAdapter.parse(r.data!);
      } else {
        matches = await KboScraperService(dio).load(day);
      }
      return LeagueResult(
        league,
        matches.where((m) => sameDay(m.startsAt, day)).toList(),
      );
    } catch (_) {
      return LeagueResult(
        league,
        const [],
        '${league.label} 데이터를 불러오지 못했습니다. 연결 또는 제공처 변경을 확인하고 다시 시도하세요.',
      );
    }
  }

  Future<String> detail(UnifiedMatchModel match) async {
    if (!paths.containsKey(match.league)) return match.report;
    final id = match.id.split(':').last;
    final r = await dio.get<Json>(
      'https://site.api.espn.com/apis/site/v2/sports/${paths[match.league]}/summary',
      queryParameters: {'event': id},
    );
    final data = r.data!;
    final article = data['article'] as Json?;
    final text = StringBuffer();
    if (article != null) {
      text.writeln(article['headline'] ?? '');
      text.writeln(article['story'] ?? '');
    }
    for (final team in (data['boxscore']?['teams'] as List? ?? [])) {
      text.writeln(team['team']?['displayName'] ?? '');
      for (final stat in (team['statistics'] as List? ?? [])) {
        text.writeln(
          '${stat['label'] ?? stat['name']}: ${stat['displayValue']}',
        );
      }
    }
    return text.toString();
  }
}
