import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/match_detail.dart';
import '../../../models/unified_match_model.dart';
import '../../../services/report_text.dart';
import 'package:html/parser.dart' as html;

class KboDetailService {
  KboDetailService(this.dio);
  final Dio dio;
  Future<MatchDetail> load(UnifiedMatchModel match) async {
    if (match.state == MatchState.scheduled ||
        match.state == MatchState.cancelled) {
      return MatchDetail(
        article: match.report,
        notices: const ['경기 시작 전 또는 취소된 경기에는 선수별 경기 기록이 없습니다.'],
      );
    }
    final response = await dio.post<String>(
      'https://www.koreabaseball.com/ws/Schedule.asmx/GetBoxScoreScroll',
      data: match.detailParameters,
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Referer':
              'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
    );
    final detail = parse(
      jsonDecode((response.data ?? '').replaceFirst('\uFEFF', '').trim())
          as Map<String, dynamic>,
      match,
    );
    try {
      final response = await dio.get<String>(
        'https://www.koreabaseball.com/MediaNews/News/BreakingNews/List.aspx',
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      return MatchDetail(
        article: detail.article,
        teams: detail.teams,
        sections: detail.sections,
        plays: detail.plays,
        news: parseNews(response.data ?? '', match),
      );
    } catch (_) {
      return MatchDetail(
        article: detail.article,
        teams: detail.teams,
        sections: detail.sections,
        plays: detail.plays,
        notices: const ['공식 관련 기사 조회에 실패했습니다. 경기 기록은 정상 표시합니다.'],
      );
    }
  }

  static List<RelatedArticle> parseNews(String page, UnifiedMatchModel match) {
    final result = <RelatedArticle>[];
    for (final card in html.parse(page).querySelectorAll('.boardPhoto li')) {
      final link = card.querySelector('.txt strong a[href]');
      if (link == null) continue;
      final title = link.text.trim();
      if (!match.participants.any(
        (p) => title.toLowerCase().contains(p.name.toLowerCase()),
      )) {
        continue;
      }
      final uri = Uri.parse(
        'https://www.koreabaseball.com/MediaNews/News/BreakingNews/List.aspx',
      ).resolve(link.attributes['href']!);
      if (uri.scheme != 'https' ||
          uri.host != 'www.koreabaseball.com' ||
          !RegExp(r'^\d+$').hasMatch(uri.queryParameters['bdSe'] ?? '')) {
        continue;
      }
      result.add(
        RelatedArticle(
          '[${card.querySelector('.date')?.text.trim() ?? '날짜 미제공'}] $title',
          'KBO 공식 사이트에 게재된 관련 팀 기사 · 해당 경기 전용 리포트가 아닐 수 있습니다.',
          uri.toString(),
        ),
      );
      if (result.length == 3) break;
    }
    return result;
  }

  static Map<String, dynamic> table(dynamic raw) => raw is String
      ? jsonDecode(raw) as Map<String, dynamic>
      : raw as Map<String, dynamic>;
  static List<List<String>> rows(dynamic data) => [
    for (final row in data as List? ?? [])
      [
        for (final cell in row['row'] as List)
          readableReport('${cell['Text'] ?? ''}').replaceAll('\n', ' '),
      ],
  ];
  static MatchDetail parse(Map<String, dynamic> data, UnifiedMatchModel match) {
    if ('${data['code']}' != '100') {
      throw const FormatException('KBO records unavailable');
    }
    final sections = <RecordSection>[];
    final teams = <TeamStatistics>[];
    const battingHeaders = ['선수', '타수', '안타', '타점', '득점', '타율'];
    final hitters = data['arrHitter'] as List? ?? [];
    final pitchers = data['arrPitcher'] as List? ?? [];
    for (var i = 0; i < hitters.length && i < match.participants.length; i++) {
      final names = rows(table(hitters[i]['table1'])['rows']);
      final batting = table(hitters[i]['table3']);
      final stats = rows(batting['rows']);
      if (names.length != stats.length) {
        throw const FormatException('KBO hitter rows mismatch');
      }
      final entries = <List<String>>[];
      for (var j = 0; j < names.length; j++) {
        if (names[j].length < 3 || stats[j].length != 5) {
          throw const FormatException('KBO hitter schema changed');
        }
        entries.add([names[j][2], ...stats[j]]);
      }
      if (entries.isNotEmpty) {
        sections.add(
          RecordSection(
            '${match.participants[i].name} · 타자 기록',
            battingHeaders,
            entries,
          ),
        );
      }
      final totals = rows(batting['tfoot']);
      if (totals.isNotEmpty && totals.first.length == 5) {
        teams.add(
          TeamStatistics(
            match.participants[i].name,
            {
              for (var k = 0; k < 5; k++)
                battingHeaders[k + 1]: totals.first[k],
            },
            {for (var k = 1; k < 6; k++) battingHeaders[k]: battingHeaders[k]},
          ),
        );
      }
    }
    for (var i = 0; i < pitchers.length && i < match.participants.length; i++) {
      final t = table(pitchers[i]['table']);
      final header = rows(t['headers']);
      final values = rows(t['rows']);
      if (header.length != 1 ||
          values.any((r) => r.length != header.first.length)) {
        throw const FormatException('KBO pitcher schema changed');
      }
      if (values.isNotEmpty) {
        sections.add(
          RecordSection(
            '${match.participants[i].name} · 투수 기록',
            header.first,
            values,
          ),
        );
      }
    }
    final plays = <String>[];
    if (data['tableEtc'] != null) {
      for (final row in rows(table(data['tableEtc'])['rows'])) {
        if (row.length >= 2 && row[1].isNotEmpty) {
          plays.add('${row[0]}: ${row[1]}');
        }
      }
    }
    if (sections.isEmpty) {
      throw const FormatException('KBO detailed records not yet published');
    }
    return MatchDetail(
      article: match.report,
      teams: teams,
      sections: sections,
      plays: plays,
    );
  }
}
