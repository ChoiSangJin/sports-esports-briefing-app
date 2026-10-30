import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'match_adapters.dart';

/// Season boundaries include the postseason. Empty scoreboards are never proof
/// that a season ended. Cache the metadata separately from live match data.
class SeasonService {
  SeasonService(this.dio, {this.preferences});
  final SharedPreferences? preferences;
  final _boundaries = <String, DateTime>{};
  final Dio dio;
  final _cache = <String, ({DateTime expires, String? value})>{};
  final _pending = <String, Future<String?>>{};

  Future<String?> notice(String path, DateTime now) async {
    final key = 'season_notice_v1:$path';
    if (!_cache.containsKey(path)) {
      try {
        final stored = jsonDecode(preferences?.getString(key) ?? 'null');
        if (stored is Map) {
          _cache[path] = (
            expires: DateTime.parse(stored['expires'] as String),
            value: stored['value'] as String?,
          );
        }
      } catch (_) {
        /* A corrupt optional cache must not block scores. */
      }
    }
    final cached = _cache[path];
    if (cached != null && now.isBefore(cached.expires)) return cached.value;
    return _pending.putIfAbsent(path, () async {
      try {
        final value = path == 'f1' ? await _f1(now) : await _load(path, now);
        var expires = value == null
            ? now.add(const Duration(hours: 1))
            : DateTime(now.year, now.month, now.day + 1);
        final boundary = _boundaries[path];
        if (boundary != null &&
            boundary.isAfter(now) &&
            boundary.isBefore(expires)) {
          expires = boundary;
        }
        _cache[path] = (expires: expires, value: value);
        try {
          await preferences?.setString(
            key,
            jsonEncode({'expires': expires.toIso8601String(), 'value': value}),
          );
        } catch (_) {
          /* Disk cache failure does not discard source data. */
        }
        return value;
      } catch (_) {
        // A failed metadata lookup must not hide normal match retrieval.
        return null;
      } finally {
        _pending.remove(path);
      }
    });
  }

  Future<Map<String, dynamic>?> _season(String path, [int? year]) async {
    final response = await dio.get<Map<String, dynamic>>(
      'https://site.api.espn.com/apis/site/v2/sports/$path/scoreboard',
      queryParameters: {if (year != null) 'dates': '$year', 'limit': 1},
    );
    final leagues = response.data?['leagues'];
    if (leagues is! List || leagues.isEmpty) return null;
    final season = leagues.first['season'];
    return season is Map<String, dynamic> ? season : null;
  }

  Future<String?> _load(String path, DateTime now) async {
    final season = await _season(path);
    if (season == null) return null;
    final year = int.tryParse('${season['year']}');
    final end = DateTime.tryParse('${season['endDate']}');
    final start = DateTime.tryParse('${season['startDate']}');
    if (year == null || end == null || start == null || !end.isAfter(start)) {
      return null;
    }
    _boundaries[path] = now.isBefore(start) ? start : end;
    if (now.isBefore(start)) {
      return '$year 시즌 일정 시작 예정\n${_date(start)} · ${_days(start, now)}일 남음\n프리시즌을 포함한 제공처 시즌 달력 기준입니다.';
    }
    final phase = season['type'];
    final offseason =
        phase is Map &&
        '${phase['type'] ?? phase['id']}' == '4' &&
        '${phase['name']}'
            .toLowerCase()
            .replaceAll(' ', '')
            .contains('offseason');
    if (!now.isAfter(end) && !offseason) return null;
    var text = '$year 시즌 일정 종료\n정규시즌과 포스트시즌을 포함한 ESPN 시즌 달력 기준입니다.';
    try {
      final next = await _season(path, year + 1);
      final nextStart = DateTime.tryParse('${next?['startDate']}');
      // The default endpoint may lag behind a published season rollover.
      if (next?['year'] == year + 1 &&
          nextStart != null &&
          !nextStart.isAfter(now)) {
        return null;
      }
      if (next?['year'] == year + 1 &&
          nextStart != null &&
          nextStart.isAfter(now)) {
        _boundaries[path] = nextStart;
        text +=
            '\n\n${year + 1} 시즌 일정 시작: ${_date(nextStart)}\n${_days(nextStart, now)}일 남음 · 프리시즌 포함';
      } else {
        text += '\n\n다음 시즌 개막일은 현재 제공처에서 확인되지 않았습니다.';
      }
    } catch (_) {
      text += '\n\n다음 시즌 일정 조회에 실패했습니다. 나중에 다시 확인해 주세요.';
    }
    return '$text\n\n지난 경기 결과는 이전 날짜를 선택해 확인하세요.';
  }

  Future<String?> _f1(DateTime now) async {
    Future<List<Map<String, dynamic>>> races(String suffix) async {
      final r = await dio.get<Json>(
        'https://api.jolpi.ca/ergast/f1/$suffix.json',
        queryParameters: {'limit': 100},
      );
      return (r.data?['MRData']['RaceTable']['Races'] as List)
          .cast<Map<String, dynamic>>();
    }

    final calendar = await races('${now.year}');
    if (calendar.isEmpty) return null;
    DateTime time(Map<String, dynamic> r) =>
        DateTime.parse("${r['date']}T${r['time'] ?? '00:00:00Z'}");
    calendar.sort((a, b) => time(a).compareTo(time(b)));
    if (now.isBefore(time(calendar.first))) {
      _boundaries['f1'] = time(calendar.first);
      return 'F1 ${now.year} 시즌 개막 예정\n${calendar.first['raceName']} · ${_date(time(calendar.first))}\n${_days(time(calendar.first), now)}일 남음 · Jolpica 공개 달력 기준';
    }
    if (!now.isAfter(time(calendar.last))) return null;
    final finalRace = calendar.last;
    final results = await races('${now.year}/${finalRace['round']}/results');
    if (results.isEmpty ||
        results.first['season'] != '${now.year}' ||
        results.first['round'] != finalRace['round'] ||
        (results.first['Results'] as List? ?? []).isEmpty) {
      return null;
    }
    var text = 'F1 ${now.year} 시즌 종료\n공개 달력의 최종 라운드 결과가 확인되었습니다.';
    try {
      final next = await races('${now.year + 1}');
      next.sort((a, b) => time(a).compareTo(time(b)));
      if (next.isNotEmpty &&
          next.first['season'] == '${now.year + 1}' &&
          time(next.first).isAfter(now)) {
        _boundaries['f1'] = time(next.first);
        text +=
            '\n\n다음 시즌 개막: ${_date(time(next.first))}\n${next.first['raceName']} · ${_days(time(next.first), now)}일 남음';
      } else {
        text += '\n\n다음 시즌 개막 일정은 현재 제공처에서 확인되지 않았습니다.';
      }
    } catch (_) {
      text += '\n\n다음 시즌 일정 조회에 실패했습니다.';
    }
    return '$text\n\n지난 경기 결과는 이전 날짜를 선택해 확인하세요.';
  }

  static int _days(DateTime date, DateTime now) {
    final local = date.toLocal();
    final today = now.toLocal();
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }

  static String _date(DateTime date) {
    final d = date.toLocal();
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }
}
