import 'package:dio/dio.dart';
import '../../../models/unified_match_model.dart';

/// Official public web endpoints; schemas cross-checked against k-skill docs.
/// No embedded provider keys or third-party proxy is required.
class KoreanLeagueService {
  KoreanLeagueService(this.dio);
  final Dio dio;
  final _months = <String, Future<List<UnifiedMatchModel>>>{};
  void clearCache() => _months.clear();
  static bool supports(League league) =>
      [League.kbl, League.kleague1].contains(league);
  static String officialUrl(League league) => league == League.kbl
      ? 'https://www.kbl.or.kr/game/schedule-list'
      : 'https://www.kleague.com/schedule.do';
  static String source(League league) => '${league.label} 공식 일정·기록';

  Future<List<UnifiedMatchModel>> month(League league, DateTime month) async {
    final key = '${league.name}:${month.year}:${month.month}';
    try {
      return await _months.putIfAbsent(key, () async {
        if (league == League.kbl) {
          String compact(DateTime d) =>
              '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
          final response = await dio.get<dynamic>(
            'https://api.kbl.or.kr/match/list',
            queryParameters: {
              'fromDate': compact(DateTime(month.year, month.month)),
              'toDate': compact(DateTime(month.year, month.month + 1, 0)),
              'tcodeList': 'all',
              'seasonGrade': 1,
            },
            options: Options(
              headers: const {
                'channel': 'WEB',
                'teamcode': 'XX',
                'lang': 'ko',
                'x-requested-with': 'XMLHttpRequest',
              },
            ),
          );
          return parseKbl(response.data);
        }
        final response = await dio.post<dynamic>(
          'https://www.kleague.com/getScheduleList.do',
          data: {
            'year': '${month.year}',
            'month': month.month.toString().padLeft(2, '0'),
            'leagueId': 1,
          },
          options: Options(contentType: 'application/json;charset=utf-8'),
        );
        return parseKleague(response.data, league);
      });
    } catch (_) {
      _months.remove(key);
      rethrow;
    }
  }

  Future<List<UnifiedMatchModel>> day(League league, DateTime day) async {
    // A device-local day can cross a Korean month boundary.
    final start = day.toUtc().add(const Duration(hours: 9));
    final end = DateTime(day.year, day.month, day.day + 1)
        .toUtc()
        .subtract(const Duration(microseconds: 1))
        .add(const Duration(hours: 9));
    final months = {
      DateTime(start.year, start.month),
      DateTime(end.year, end.month),
    };
    final responses = await Future.wait([
      for (final m in months) month(league, m),
    ]);
    return {
      for (final list in responses)
        for (final m in list)
          if (sameDay(m.startsAt, day)) m.id: m,
    }.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  static DateTime _kst(String date, String time) {
    final digits = date.replaceAll(RegExp(r'[^0-9]'), '');
    final t = time.replaceAll(':', '');
    if (!RegExp(r'^\d{8}$').hasMatch(digits) ||
        !RegExp(r'^\d{4}$').hasMatch(t)) {
      throw const FormatException('Official kickoff time unavailable');
    }
    return DateTime.parse(
      '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}T${t.substring(0, 2)}:${t.substring(2)}:00+09:00',
    );
  }

  static List<UnifiedMatchModel> parseKbl(dynamic raw) {
    if (raw is! List) {
      throw const FormatException('KBL schedule schema changed');
    }
    return [
      for (final g in raw)
        if (g is Map && '${g['seasonGrade'] ?? 1}' == '1')
          _match(
            League.kbl,
            '${g['gmkey'] ?? ''}',
            _kst('${g['gameDate']}', '${g['gameStart']}'),
            '${g['tnameFH'] ?? g['tnameH'] ?? ''}',
            '${g['tnameFA'] ?? g['tnameA'] ?? ''}',
            '${g['isEnded']}' == '1'
                ? MatchState.finalScore
                : '${g['isStarted']}' == '1'
                ? MatchState.live
                : MatchState.scheduled,
            g['scoreH'],
            g['scoreA'],
            '${g['stadiumnameF'] ?? g['stadiumname'] ?? ''}',
            '${g['tv'] ?? ''}',
            officialUrl(League.kbl),
          ),
    ];
  }

  static List<UnifiedMatchModel> parseKleague(dynamic raw, League league) {
    final data = raw is Map ? raw['data'] ?? raw : null;
    if (data is! Map || data['scheduleList'] is! List) {
      throw const FormatException('K League schedule schema changed');
    }
    final clubs = {
      for (final c in data['clubList'] as List? ?? [])
        '${c['teamId']}':
            '${c['teamNameShort'] ?? c['teamName'] ?? c['teamNameFull']}',
    };
    return [
      for (final g in data['scheduleList'] as List)
        if (g['leagueId'] == null || '${g['leagueId']}' == '1')
          _match(
            league,
            '${g['year'] ?? ''}:${g['meetSeq'] ?? ''}:${g['gameId'] ?? ''}',
            _kst('${g['gameDate']}', '${g['gameTime']}'),
            clubs['${g['homeTeam']}'] ?? '${g['homeTeamName'] ?? ''}',
            clubs['${g['awayTeam']}'] ?? '${g['awayTeamName'] ?? ''}',
            switch (g['gameStatus'] ?? (g['endYn'] == 'Y' ? 'FE' : 'NS')) {
              'FE' => MatchState.finalScore,
              'LIVE' || 'IN' || 'HT' => MatchState.live,
              'PP' || 'CAN' => MatchState.cancelled,
              _ => MatchState.scheduled,
            },
            g['homeGoal'],
            g['awayGoal'],
            '${g['fieldNameFull'] ?? g['fieldName'] ?? ''}',
            '${g['broadcastName'] ?? ''}',
            g['gameId'] != null && g['meetSeq'] != null
                ? Uri.https('www.kleague.com', '/match.do', {
                    'year': '${g['year']}',
                    'leagueId': '1',
                    'gameId': '${g['gameId']}',
                    'meetSeq': '${g['meetSeq']}',
                  }).toString()
                : officialUrl(league),
          ),
    ];
  }

  static UnifiedMatchModel _match(
    League league,
    String id,
    DateTime at,
    String home,
    String away,
    MatchState state,
    dynamic h,
    dynamic a,
    String venue,
    String tv,
    String url,
  ) {
    if (home.isEmpty || away.isEmpty || id.isEmpty) {
      throw const FormatException('Official match identity missing');
    }
    final hs = int.tryParse('$h'), awayScore = int.tryParse('$a');
    final scored = state == MatchState.live || state == MatchState.finalScore;
    return UnifiedMatchModel(
      id: '${league.name}:$id',
      league: league,
      startsAt: at,
      title: '$away vs $home',
      state: state,
      source: source(league),
      sourceUrl: url,
      status: '${state.label}${venue.isEmpty ? '' : ' · $venue'}',
      participants: [
        Participant(
          name: away,
          score: scored ? awayScore?.toString() : null,
          winner:
              state == MatchState.finalScore &&
              awayScore != null &&
              hs != null &&
              awayScore > hs,
        ),
        Participant(
          name: home,
          score: scored ? hs?.toString() : null,
          winner:
              state == MatchState.finalScore &&
              awayScore != null &&
              hs != null &&
              hs > awayScore,
        ),
      ],
      report: [
        if (venue.isNotEmpty) '경기장: $venue',
        if (tv.isNotEmpty) '중계: $tv',
      ].join('\n'),
    );
  }
}
