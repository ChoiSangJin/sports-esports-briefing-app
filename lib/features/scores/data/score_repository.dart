import '../../../models/match_detail.dart';
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
    this.isUpcoming = false,
  ]);
  final League league;
  final List<UnifiedMatchModel> matches;
  final String? warning;
  final String source;
  final bool isUpcoming;
}

class ScoreRepository {
  ScoreRepository(this.dio) : _lol = LolScheduleService(dio);
  final Dio dio;
  final LolScheduleService _lol;
  final _espn = <String, Future<List<UnifiedMatchModel>>>{};
  DateTime _cachedAt = DateTime.now();
  void clearCache() {
    _lol.clearCache();
    _espn.clear();
    _cachedAt = DateTime.now();
  }

  static const paths = {
    League.nfl: 'football/nfl',
    League.nba: 'basketball/nba',
    League.mlb: 'baseball/mlb',
  };

  Future<LeagueResult> load(League league, DateTime day) async {
    if (DateTime.now().difference(_cachedAt).inSeconds >= 60) clearCache();
    final selected = await _loadDay(league, day);
    if (selected.matches.isNotEmpty || selected.warning != null) {
      return selected;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (league == League.lol) {
      final all = await _lol.load();
      final next =
          all
              .where(
                (m) =>
                    m.state == MatchState.scheduled &&
                    m.startsAt.isAfter(now) &&
                    !m.startsAt.toLocal().isBefore(day),
              )
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      if (next.isNotEmpty) {
        return LeagueResult(
          league,
          next
              .where((m) => sameDay(m.startsAt, next.first.startsAt.toLocal()))
              .toList(),
          null,
          selected.source,
          true,
        );
      }
      return LeagueResult(
        league,
        const [],
        '선택일 경기가 없으며 공식 페이지에 공개된 다음 예정 경기도 없습니다.',
        selected.source,
      );
    }
    final start = day.isBefore(today)
        ? today
        : DateTime(day.year, day.month, day.day + 1);
    if (league == League.f1) {
      try {
        for (
          var year = (day.isBefore(today) ? today : day).year;
          year <= (day.isBefore(today) ? today : day).year + 1;
          year++
        ) {
          final response = await dio.get<Json>(
            'https://api.jolpi.ca/ergast/f1/$year.json',
            queryParameters: {'limit': 100},
          );
          final races =
              JolpicaAdapter.schedule(response.data!)
                  .where(
                    (m) =>
                        m.startsAt.isAfter(now) &&
                        !m.startsAt.toLocal().isBefore(
                          day.isBefore(today) ? today : day,
                        ),
                  )
                  .toList()
                ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          if (races.isNotEmpty) {
            return LeagueResult(
              league,
              [races.first],
              null,
              'Jolpica F1 일정',
              !sameDay(races.first.startsAt, day),
            );
          }
        }
      } catch (_) {
        return LeagueResult(
          league,
          const [],
          '선택일 경기는 없으며 F1 예정 일정 조회에 실패했습니다.',
        );
      }
      return LeagueResult(league, const [], '공개된 F1 달력에서 다음 예정 경기를 찾지 못했습니다.');
    }
    for (var offset = 0; offset < 14; offset++) {
      final date = DateTime(start.year, start.month, start.day + offset);
      final next = await _loadDay(league, date);
      if (next.warning != null) {
        return LeagueResult(
          league,
          const [],
          '선택일 경기는 없으며 예정 경기 조회를 완료하지 못했습니다. ${next.warning}',
          next.source,
        );
      }
      final upcoming =
          next.matches
              .where(
                (m) =>
                    m.state == MatchState.scheduled && m.startsAt.isAfter(now),
              )
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      if (upcoming.isNotEmpty) {
        return LeagueResult(league, upcoming, null, next.source, true);
      }
    }
    return LeagueResult(
      league,
      const [],
      '선택일 경기가 없고, 검색 시작일부터 14일 내 공개된 예정 경기를 찾지 못했습니다.',
      selected.source,
    );
  }

  Future<LeagueResult> _loadDay(League league, DateTime day) async {
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
            _espn.putIfAbsent(
              '${league.name}:${date(DateTime(day.year, day.month, day.day + offset))}',
              () async {
                final response = await dio.get<Json>(
                  'https://site.api.espn.com/apis/site/v2/sports/${paths[league]}/scoreboard',
                  queryParameters: {
                    'dates': date(
                      DateTime(day.year, day.month, day.day + offset),
                    ),
                    'limit': 100,
                  },
                );
                return EspnAdapter.parse(response.data!, league);
              },
            ),
        ]);
        matches = {
          for (final r in responses)
            for (final match in r) match.id: match,
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

          final last = dateOnly(matches.last.startsAt);
          if (day.isAfter(last)) {
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

  Future<String> detail(UnifiedMatchModel match) async =>
      (await details(match)).asText;

  Future<MatchDetail> details(UnifiedMatchModel match) async {
    if (!paths.containsKey(match.league)) {
      return MatchDetail(article: match.report);
    }
    final id = match.id.split(':').last;
    final response = await dio.get<Json>(
      'https://site.api.espn.com/apis/site/v2/sports/${paths[match.league]}/summary',
      queryParameters: {'event': id},
    );
    return MatchDetail.fromEspn(response.data!);
  }
}
