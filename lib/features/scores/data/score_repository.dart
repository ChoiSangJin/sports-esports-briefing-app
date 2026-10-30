import '../../../models/match_detail.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/unified_match_model.dart';
import 'match_adapters.dart';
import 'kbo_service.dart';
import 'lol_schedule_service.dart';
import 'kbo_detail_service.dart';
import 'lol_detail_service.dart';
import 'season_service.dart';

class LeagueResult {
  const LeagueResult(
    this.league,
    this.matches, [
    this.warning,
    this.source = '',
    this.isUpcoming = false,
    this.seasonNotice,
  ]);
  final League league;
  final List<UnifiedMatchModel> matches;
  final String? warning;
  final String source;
  final bool isUpcoming;
  final String? seasonNotice;
}

class ScoreRepository {
  ScoreRepository(
    this.dio, {
    DateTime Function()? clock,
    SharedPreferences? preferences,
  }) : _now = clock ?? DateTime.now,
       _lol = LolScheduleService(dio),
       _seasons = SeasonService(dio, preferences: preferences);
  final DateTime Function() _now;
  final SeasonService _seasons;
  final Dio dio;
  final LolScheduleService _lol;
  final _espn = <String, Future<List<UnifiedMatchModel>>>{};
  DateTime _cachedAt = DateTime.now();
  void clearCache({bool includeSeasons = true}) {
    if (includeSeasons) _seasons.clearCache();
    _lol.clearCache();
    _espn.clear();
    _cachedAt = DateTime.now();
  }

  static const paths = {
    League.nfl: 'football/nfl',
    League.nba: 'basketball/nba',
    League.mlb: 'baseball/mlb',
    League.epl: 'soccer/eng.1',
  };

  Future<LeagueResult> load(League league, DateTime day) async {
    if (DateTime.now().difference(_cachedAt).inSeconds >= 60) {
      clearCache(includeSeasons: false);
    }
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    // Historical dates keep their records; current/future empty days may show
    // a verified season boundary instead of scanning fourteen empty dates.
    String? season;
    if (!day.isBefore(today) &&
        (paths.containsKey(league) ||
            league == League.f1 ||
            league == League.kbo)) {
      season = await _seasons.notice(paths[league] ?? league.name, now);
    }
    if (season != null && sameDay(day, today)) {
      return LeagueResult(
        league,
        const [],
        null,
        league == League.f1
            ? 'Jolpica 시즌 일정'
            : league == League.kbo
            ? 'KBO 공식 일정'
            : 'ESPN 시즌 일정',
        false,
        season,
      );
    }
    final selected = await _loadDay(league, day);
    if (selected.matches.isNotEmpty ||
        selected.warning != null ||
        selected.seasonNotice != null) {
      return selected;
    }
    if (season != null) {
      return LeagueResult(
        league,
        const [],
        null,
        league == League.f1
            ? 'Jolpica 시즌 일정'
            : league == League.kbo
            ? 'KBO 공식 일정'
            : 'ESPN 시즌 일정',
        false,
        season,
      );
    }
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
        null,
        selected.source,
        false,
        'LoL 공개 일정 안내\n현재 공개된 다음 경기가 없습니다. 여러 리그가 별도로 진행되므로 전체 시즌 종료를 뜻하지 않습니다. 공식 일정에서 확인해 주세요.',
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
    if (league == League.kbo) {
      try {
        var cursor = day.isBefore(today) ? today : day;
        final service = KboService(dio);
        for (var attempt = 0; attempt < 4; attempt++) {
          final nextDate = await service.nextDate(cursor);
          if (nextDate == null) {
            return LeagueResult(
              league,
              const [],
              null,
              selected.source,
              false,
              'KBO 공개 일정 안내\n다음 경기일이 아직 공개되지 않았습니다. 일정 공백만으로 시즌 종료를 판단하지 않습니다.',
            );
          }
          final local = nextDate.toLocal();
          final candidates = <UnifiedMatchModel>[];
          // KST midnight may belong to the preceding local date. Enclose both
          // local dates to retain Korean evening games on overseas devices.
          for (var offset = 0; offset <= 1; offset++) {
            final date = DateTime(local.year, local.month, local.day + offset);
            final found = await _loadDay(league, date);
            if (found.warning != null) {
              throw const FormatException('KBO next game failed');
            }
            candidates.addAll(
              found.matches.where(
                (m) =>
                    m.state == MatchState.scheduled &&
                    m.startsAt.isAfter(now) &&
                    !m.startsAt.toLocal().isBefore(
                      day.isBefore(today) ? today : day,
                    ),
              ),
            );
          }
          if (candidates.isNotEmpty) {
            final unique = {for (final m in candidates) m.id: m}.values.toList()
              ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
            return LeagueResult(league, unique, null, selected.source, true);
          }
          cursor = nextDate.add(const Duration(hours: 12));
        }
        return LeagueResult(
          league,
          const [],
          null,
          selected.source,
          false,
          'KBO 공식 다음 일정에 취소·변경 경기가 포함돼 있습니다. 다음 예정 경기는 공식 일정에서 확인해 주세요.',
        );
      } catch (_) {
        return LeagueResult(
          league,
          const [],
          'KBO 다음 경기일 조회에 실패했습니다. 다시 시도하거나 공식 일정에서 확인해 주세요.',
          selected.source,
        );
      }
    }
    if (league == League.epl) {
      try {
        for (var offset = 0; offset < 3; offset++) {
          final month = DateTime(start.year, start.month + offset);
          final response = await dio.get<Json>(
            'https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard',
            queryParameters: {
              'dates': '${month.year}${month.month.toString().padLeft(2, '0')}',
              'limit': 100,
            },
          );
          final next =
              EspnAdapter.parse(response.data!, league)
                  .where(
                    (m) =>
                        m.state == MatchState.scheduled &&
                        m.startsAt.isAfter(now) &&
                        !m.startsAt.toLocal().isBefore(start),
                  )
                  .toList()
                ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          if (next.isNotEmpty) {
            return LeagueResult(
              league,
              next
                  .where(
                    (m) => sameDay(m.startsAt, next.first.startsAt.toLocal()),
                  )
                  .toList(),
              null,
              'ESPN EPL',
              true,
            );
          }
        }
        return LeagueResult(
          league,
          const [],
          null,
          'ESPN EPL',
          false,
          'EPL 공개 일정 안내\n현재부터 3개월 범위에서 다음 경기가 확인되지 않았습니다. 공식 일정이 발표되면 표시됩니다.',
        );
      } catch (_) {
        return LeagueResult(
          league,
          const [],
          'EPL 다음 일정 조회에 실패했습니다. 다시 시도해 주세요.',
          'ESPN EPL',
        );
      }
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
        // Jolpica clamps year-wide results to 100 driver entries, truncating
        // later rounds. Resolve the selected race from the full calendar and
        // request each round separately (at most the grid size).
        final calendar = await dio.get<Json>(
          'https://api.jolpi.ca/ergast/f1/${day.year}.json',
          queryParameters: {'limit': 100},
        );
        final races = JolpicaAdapter.schedule(
          calendar.data!,
        ).where((race) => sameDay(race.startsAt, day));
        matches = [];
        for (final race in races) {
          if (race.startsAt.isAfter(_now())) {
            matches.add(race);
            continue;
          }
          final round = race.id.split(':').last;
          final result = await dio.get<Json>(
            'https://api.jolpi.ca/ergast/f1/${day.year}/$round/results.json',
            queryParameters: {'limit': 100},
          );
          final completed = JolpicaAdapter.parse(result.data!);
          if (completed.isEmpty) {
            return LeagueResult(
              league,
              const [],
              '선택한 F1 경기 결과가 아직 제공되지 않았습니다.',
              'Jolpica F1',
            );
          }
          matches.addAll(completed);
        }
        source = 'Jolpica F1';
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
              null,
              source,
              false,
              'LoL 공개 일정 안내\n선택한 날짜는 공식 일정의 공개 범위 밖입니다. 다음 일정은 아직 확인되지 않았으며 전체 시즌 종료를 뜻하지 않습니다.',
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
      _espn.removeWhere((key, value) => key.startsWith('${league.name}:'));
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
    if (match.league == League.lol) return LolDetailService(dio).load(match);
    if (match.league == League.kbo) {
      try {
        return await KboDetailService(dio).load(match);
      } catch (_) {
        return MatchDetail(
          article: match.report,
          notices: const [
            'KBO 상세 기록이 아직 게시되지 않았거나 조회에 실패했습니다. 공식 게임센터에서 확인해 주세요.',
          ],
        );
      }
    }
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
