import 'package:dio/dio.dart';
import '../../../models/unified_match_model.dart';
import 'match_adapters.dart';
import 'kbo_service.dart';
import 'lol_schedule_service.dart';

class LeagueResult {
  const LeagueResult(
    this.league,
    this.matches, [
    this.warning,
    this.source = '',
  ]);
  final League league;
  final List<UnifiedMatchModel> matches;
  final String? warning;
  final String source;
}

class ScoreRepository {
  ScoreRepository(this.dio) : _lol = LolScheduleService(dio);
  final Dio dio;
  final LolScheduleService _lol;
  void clearCache() => _lol.clearCache();
  static const paths = {
    League.nfl: 'football/nfl',
    League.nba: 'basketball/nba',
    League.mlb: 'baseball/mlb',
  };

  Future<LeagueResult> load(League league, DateTime day) async {
    try {
      List<UnifiedMatchModel> matches;
      var source = '';
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
        matches = await _lol.load();
        source = 'LoL e스포츠 공식 일정';
        if (matches.isNotEmpty) {
          DateTime dateOnly(DateTime d) {
            final local = d.toLocal();
            return DateTime(local.year, local.month, local.day);
          }

          final first = dateOnly(matches.first.startsAt),
              last = dateOnly(matches.last.startsAt);
          if (day.isBefore(first) || day.isAfter(last)) {
            return LeagueResult(
              league,
              const [],
              '선택한 날짜는 공식 페이지가 제공한 일정 범위 밖입니다. 공식 일정에서 확인해 주세요.',
              source,
            );
          }
        }
      } else {
        matches = await KboService(dio).load(day);
        source = 'KBO 공식 게임센터';
      }
      return LeagueResult(
        league,
        matches.where((m) => sameDay(m.startsAt, day)).toList(),
        null,
        source,
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
