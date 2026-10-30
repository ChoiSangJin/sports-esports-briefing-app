import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

/// Korean Series is series ID 7 on KBO's official schedule page.
class KboSeasonService {
  KboSeasonService(this.dio);
  final Dio dio;
  static Options get options => Options(
    responseType: ResponseType.plain,
    contentType: Headers.formUrlEncodedContentType,
    headers: {
      'Referer': 'https://www.koreabaseball.com/Schedule/Schedule.aspx',
      'X-Requested-With': 'XMLHttpRequest',
    },
  );
  static Map<String, dynamic> decode(String raw) {
    dynamic value = jsonDecode(raw.replaceFirst('\uFEFF', '').trim());
    if (value is Map && value['d'] != null) {
      value = value['d'] is String ? jsonDecode(value['d']) : value['d'];
    }
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid KBO calendar');
    }
    return value;
  }

  Future<DateTime?> nextDate(DateTime day) async {
    final korean = day.toUtc().add(const Duration(hours: 9));
    final date = DateTime.utc(korean.year, korean.month, korean.day);
    final response = await dio.post<String>(
      'https://www.koreabaseball.com/ws/Main.asmx/GetKboGameDate',
      options: options,
      data: {'leId': '1', 'srId': '0,1,3,4,5,7,8,9', 'date': _date(date)},
    );
    final data = decode(response.data ?? '');
    if ('${data['code']}' != '100') {
      throw const FormatException('KBO next date unavailable');
    }
    final next = '${data['AFTER_G_DT'] ?? ''}';
    if (next.isEmpty || next == 'null') return null;
    if (!RegExp(r'^\d{8}$').hasMatch(next)) {
      throw const FormatException('KBO next date invalid');
    }
    final result = DateTime.parse(
      '${next.substring(0, 4)}-${next.substring(4, 6)}-${next.substring(6, 8)}T00:00:00+09:00',
    );
    if (!result.isAfter(
      DateTime.parse(
        '${_date(date).substring(0, 4)}-${_date(date).substring(4, 6)}-${_date(date).substring(6, 8)}T00:00:00+09:00',
      ),
    )) {
      throw const FormatException('KBO next date did not advance');
    }
    return result;
  }

  static String _date(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Future<String?> notice(DateTime now) async {
    final korean = now.toUtc().add(const Duration(hours: 9));
    final year = korean.month < 3 ? korean.year - 1 : korean.year;
    final rows = <dynamic>[];
    for (final month in [10, 11]) {
      if (year == korean.year && month > korean.month) continue;
      final r = await dio.post<String>(
        'https://www.koreabaseball.com/ws/Schedule.asmx/GetScheduleList',
        options: options,
        data: {
          'leId': '1',
          'srIdList': '7',
          'seasonId': '$year',
          'gameMonth': '$month',
          'teamId': '',
        },
      );
      final data = decode(r.data ?? '');
      if (data['rows'] is! List) {
        throw const FormatException('KBO series calendar missing');
      }
      rows.addAll(data['rows'] as List);
    }
    final champion = championFromRows(rows, year, now);
    if (champion == null) return null;
    var nextText = '다음 시즌 개막일은 현재 연결된 제공처에서 확인되지 않았습니다.';
    try {
      final next = await nextDate(now);
      if (next != null &&
          next.toUtc().add(const Duration(hours: 9)).year > year) {
        final koreanNext = next.toUtc().add(const Duration(hours: 9));
        nextText =
            '다음 시즌 공개 경기일: ${_date(koreanNext)} (KST)\n시범경기를 포함하며 정규시즌 개막일과 다를 수 있습니다.';
      }
    } catch (_) {
      nextText = '다음 시즌 일정 조회에 실패했습니다. 공식 일정에서 확인해 주세요.';
    }
    return 'KBO $year 시즌 종료\n한국시리즈 우승: $champion\nKBO 공식 한국시리즈 4승 기록으로 확인했습니다.\n\n$nextText\n지난 경기 결과는 이전 날짜를 선택해 확인하세요.';
  }

  static String? championFromRows(List rows, int year, DateTime now) {
    final wins = <String, int>{};
    final games = <String>{};
    for (final item in rows) {
      final cells = item['row'] as List? ?? [];
      final relay = html.parseFragment(
        cells.map((c) => '${c['Text'] ?? ''}').join(' '),
      );
      final review = relay.querySelector('a[href*="section=REVIEW"]');
      final uri = Uri.tryParse(review?.attributes['href'] ?? '');
      final id = uri?.queryParameters['gameId'];
      final date = uri?.queryParameters['gameDate'];
      if (id == null ||
          date == null ||
          !RegExp('^$year[0-9]{4}').hasMatch(id) ||
          !id.startsWith(date) ||
          date.length != 8 ||
          games.contains(id)) {
        continue;
      }
      final played = DateTime.tryParse(
        '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)}T00:00:00+09:00',
      );
      if (played == null || played.isAfter(now)) continue;
      final play = cells.where((c) => c['Class'] == 'play').toList();
      if (play.length != 1) continue;
      final body = html.parseFragment('${play.single['Text']}');
      final teams = body.children.where((e) => e.localName == 'span').toList();
      final scores = body.querySelectorAll('em span');
      final winner = body.querySelectorAll('em .win');
      final loser = body.querySelectorAll('em .lose');
      if (teams.length != 2 ||
          scores.length != 3 ||
          winner.length != 1 ||
          loser.length != 1) {
        continue;
      }
      final winScore = int.tryParse(winner.single.text),
          loseScore = int.tryParse(loser.single.text);
      if (winScore == null || loseScore == null || winScore <= loseScore) {
        continue;
      }
      final side = scores.indexOf(winner.single);
      if (side != 0 && side != 2) continue;
      final name = teams[side == 0 ? 0 : 1].text.trim();
      if (name.isEmpty) continue;
      games.add(id);
      wins[name] = (wins[name] ?? 0) + 1;
    }
    final champions = wins.entries.where((e) => e.value == 4).toList();
    return champions.length == 1 ? champions.single.key : null;
  }
}
