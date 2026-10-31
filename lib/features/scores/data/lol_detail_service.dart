import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/match_detail.dart';
import '../../../models/unified_match_model.dart';

class LolDetailService {
  LolDetailService(this.dio, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;
  final DateTime Function() _now;
  final Dio dio;
  Future<MatchDetail> load(UnifiedMatchModel match) async {
    final games = jsonDecode(match.detailParameters['games'] ?? '[]') as List;
    final teamNames =
        jsonDecode(match.detailParameters['teams'] ?? '{}') as Map;
    final sections = <RecordSection>[];
    final notices = <String>[];
    final videos = <RelatedArticle>[];
    if (games.isNotEmpty) {
      sections.add(
        RecordSection(
          '세트별 진행 상태',
          const ['세트', '상태'],
          [
            for (final g in games) ['${g['number']}세트', state('${g['state']}')],
          ],
        ),
      );
    }
    final requests = <Future<void>>[];
    for (final game in games) {
      final allVods = (game['vods'] as List? ?? [])
          .where((v) => v['provider'] == 'youtube')
          .toList();
      final korean = allVods
          .where((v) => '${v['mediaLocale']?['locale']}'.startsWith('ko'))
          .toList();
      final english = allVods
          .where((v) => '${v['mediaLocale']?['locale']}'.startsWith('en'))
          .toList();
      for (final vod
          in (korean.isNotEmpty
                  ? korean
                  : english.isNotEmpty
                  ? english
                  : allVods)
              .take(1)) {
        final id = vod['parameter']?.toString() ?? '';
        if (vod['provider'] == 'youtube' &&
            RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
          videos.add(
            RelatedArticle(
              '공식 ${game['number']}세트 영상 · ${vod['mediaLocale']?['translatedName'] ?? ''}',
              'LoL e스포츠 공식 일정에서 제공한 경기 영상',
              'https://www.youtube.com/watch?v=$id${vod['startMillis'] is num ? '&t=${(vod['startMillis'] as num).toInt() ~/ 1000}' : ''}',
            ),
          );
        }
      }
      if (!['completed', 'inProgress'].contains(game['state'])) continue;
      final id = '${game['id']}';
      if (!RegExp(r'^\d+$').hasMatch(id)) {
        notices.add('${game['number']}세트: 유효한 경기 ID가 없습니다.');
        continue;
      }
      requests.add(() async {
        try {
          final response = await dio.get<Map<String, dynamic>>(
            'https://feed.lolesports.com/livestats/v1/window/$id',
            options: Options(receiveTimeout: const Duration(seconds: 8)),
          );
          final raw = response.data!;
          if ('${raw['esportsGameId']}' != id ||
              '${raw['esportsMatchId']}' != match.id.split(':').last) {
            throw const FormatException('LoL game identity mismatch');
          }
          final frames = raw['frames'] as List? ?? [];
          if (frames.isEmpty) {
            throw const FormatException('LoL frames unavailable');
          }
          final initial = DateTime.parse(
            frames.last['rfc460Timestamp'] as String,
          );
          final availableUntil = _now().toUtc().subtract(
            const Duration(seconds: 30),
          );
          final requested = game['state'] == 'completed'
              ? initial.add(const Duration(hours: 6))
              : availableUntil;
          final point = requested.isAfter(availableUntil)
              ? availableUntil
              : requested;
          final aligned = DateTime.fromMillisecondsSinceEpoch(
            point.millisecondsSinceEpoch ~/ 10000 * 10000,
            isUtc: true,
          );
          final finalResponse = await dio.get<Map<String, dynamic>>(
            'https://feed.lolesports.com/livestats/v1/window/$id',
            queryParameters: {'startingTime': aligned.toIso8601String()},
            options: Options(receiveTimeout: const Duration(seconds: 8)),
          );
          if ('${finalResponse.data?['esportsGameId']}' != id ||
              '${finalResponse.data?['esportsMatchId']}' !=
                  match.id.split(':').last) {
            throw const FormatException('LoL final game identity mismatch');
          }
          sections.addAll(
            parseWindow(
              finalResponse.data!,
              teamNames,
              '${game['number']}세트',
              completed: game['state'] == 'completed',
            ),
          );
        } catch (_) {
          notices.add(
            '${game['number']}세트: 공식 상세 피드를 조회할 수 없습니다. 과거 경기 보관 기간·접근 제한 또는 연결 상태에 따라 선수 지표가 제공되지 않을 수 있습니다.',
          );
        }
      }());
    }
    await Future.wait(requests);
    final stateSection = sections.where((s) => s.title == '세트별 진행 상태').toList();
    final detailSections =
        sections.where((s) => s.title != '세트별 진행 상태').toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    return MatchDetail(
      article: match.report,
      sections: [...stateSection, ...detailSections],
      news: videos,
      notices: notices,
      teams: [
        for (final p in match.participants)
          TeamStatistics(
            p.name,
            {if (p.score != null) '세트 승수': p.score!},
            const {'세트 승수': '세트 승수'},
          ),
      ],
    );
  }

  static String state(String value) => switch (value) {
    'completed' => '종료',
    'inProgress' => '진행 중',
    'unneeded' => '미실시',
    'unstarted' => '예정',
    _ => '취소 또는 상태 미정',
  };
  static List<RecordSection> parseWindow(
    Map<String, dynamic> data,
    Map names,
    String title, {
    required bool completed,
  }) {
    final frames = data['frames'] as List? ?? [];
    if (frames.isEmpty) throw const FormatException('No LoL frames');
    final sorted = [...frames]
      ..sort(
        (a, b) =>
            '${a['rfc460Timestamp']}'.compareTo('${b['rfc460Timestamp']}'),
      );
    final frame = sorted.last;
    if (completed && frame['gameState'] != 'finished') {
      throw const FormatException('Final frame unavailable');
    }
    String value(dynamic v) => v == null ? '—' : '$v';
    final result = <RecordSection>[];
    for (final side in ['blue', 'red']) {
      final metadata = data['gameMetadata']?['${side}TeamMetadata'];
      final stats = frame['${side}Team'];
      if (metadata is! Map || stats is! Map) {
        throw const FormatException('Incomplete LoL team data');
      }
      final team =
          names['${metadata['esportsTeamId']}']?.toString() ??
          '${side == 'blue' ? '블루' : '레드'} 팀';
      final people = {
        for (final p in metadata['participantMetadata'] as List? ?? [])
          '${p['participantId']}': p,
      };
      final rows = <List<String>>[];
      for (final player in stats['participants'] as List? ?? []) {
        final p = people['${player['participantId']}'];
        if (p == null) {
          throw const FormatException('Player metadata unavailable');
        }
        rows.add([
          value(p['summonerName']),
          value(p['championId']),
          '${value(player['kills'])}/${value(player['deaths'])}/${value(player['assists'])}',
          value(player['creepScore']),
          value(player['totalGold']),
          value(player['level']),
        ]);
      }
      if (rows.isEmpty) {
        throw const FormatException('Player statistics unavailable');
      }
      result.add(
        RecordSection(
          '$title · $team · ${value(frame['rfc460Timestamp'])}',
          const ['선수', '챔피언', 'K/D/A', 'CS', '골드', '레벨'],
          rows,
        ),
      );
      result.add(
        RecordSection(
          '$title · $team 팀 기록',
          const ['항목', '기록'],
          [
            ['킬', value(stats['totalKills'])],
            ['골드', value(stats['totalGold'])],
            ['타워', value(stats['towers'])],
            ['바론', value(stats['barons'])],
            [
              '드래곤',
              stats['dragons'] is List
                  ? (stats['dragons'] as List).join(', ')
                  : '—',
            ],
          ],
        ),
      );
    }
    return result;
  }
}
