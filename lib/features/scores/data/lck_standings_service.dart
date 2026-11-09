import 'package:dio/dio.dart';
import '../../../models/match_detail.dart';

/// Public persisted query document IDs published by lolesports.com.
/// These identify queries, not credentials. No website API key is copied.
class LckStandingsService {
  LckStandingsService(this.dio);
  final Dio dio;
  Future<List<RecordSection>>? _cached;
  DateTime? _cachedAt;
  void clearCache() {
    _cached = null;
    _cachedAt = null;
  }

  Future<Map<String, dynamic>> _query(
    String name,
    String hash,
    Map<String, dynamic> variables,
  ) async {
    final response = await dio.post<Map<String, dynamic>>(
      'https://lolesports.com/api/gql',
      data: {
        'operationName': name,
        'variables': {'hl': 'ko-KR', ...variables},
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': hash},
        },
      },
      options: Options(
        headers: const {
          'apollographql-client-name': 'Sports Briefing',
          'apollographql-client-version': '1.9.0',
        },
      ),
    );
    if (response.data?['errors'] != null ||
        response.data?['data'] is! Map<String, dynamic>) {
      throw const FormatException('LCK standings query failed');
    }
    return response.data!['data'] as Map<String, dynamic>;
  }

  Future<List<RecordSection>> load(DateTime now) async {
    if (_cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!).inMinutes < 10) {
      return _cached!;
    }
    _cachedAt = now;
    final pending = _load(now);
    _cached = pending;
    try {
      return await pending;
    } catch (_) {
      if (identical(_cached, pending)) clearCache();
      rethrow;
    }
  }

  Future<List<RecordSection>> _load(DateTime now) async {
    final data = await _query(
      'GetGprSeasons',
      'c749e5ac23bd1614867cd86a8fc0eefec4b448bd986b2614e1ed7f85dfa2107f',
      {'sport': 'lol'},
    );
    final seasons = (data['seasons'] as List? ?? []).where((s) {
      final start = DateTime.tryParse('${s['startTime']}'),
          end = DateTime.tryParse('${s['endTime']}');
      return start != null &&
          end != null &&
          !now.isBefore(start) &&
          !now.isAfter(end);
    }).toList();
    if (seasons.isEmpty) return [];
    final navigation = await _query(
      'GetSeasonForNavigation',
      '95d223c34f0430e50cd602245d94b83ffec8b713076974a73fd6aa7d7166a91f',
      {
        'seasonId': [for (final s in seasons) s['id']],
      },
    );
    final tournaments = [
      for (final s in navigation['seasons'] as List? ?? [])
        for (final split in s['splits'] as List? ?? [])
          for (final t in split['tournaments'] as List? ?? [])
            if (t['league']?['name'] == 'LCK' &&
                DateTime.tryParse('${t['startTime']}') != null &&
                !DateTime.parse('${t['startTime']}').isAfter(now))
              t,
    ]..sort((a, b) => '${b['startTime']}'.compareTo('${a['startTime']}'));
    if (tournaments.isEmpty) return [];
    final display = await _query(
      'GetSeasonTournamentDisplay',
      '708d9dedda96c2a21518f4bf7a548b40e750f96394dc72135c2cace7086babfd',
      {
        'tournamentId': [tournaments.first['id']],
      },
    );
    return parse(display, now);
  }

  static List<RecordSection> parse(
    Map<String, dynamic> data,
    DateTime queriedAt,
  ) {
    final result = <RecordSection>[];
    for (final tournament in data['tournaments'] as List? ?? []) {
      for (final stage in tournament['stages'] as List? ?? []) {
        for (final section in stage['sections'] as List? ?? []) {
          final standings = section['standings'] as List? ?? [];
          if (standings.isEmpty) continue;
          // Bracket placements are separate from regular-season group ranks.
          final bracket = section['type'] == 'bracket';
          result.add(
            RecordSection(
              'LCK · ${tournament['name']} · ${stage['name']} · ${section['name']} (${bracket ? '단계별 공식 배치' : '그룹 순위'})\n${queriedAt.toLocal().year}.${queriedAt.toLocal().month}.${queriedAt.toLocal().day} 조회 · 선택일 당시 순위 아님',
              const ['배치', '팀', '승', '패'],
              [
                for (final standing in standings)
                  [
                    '${standing['placement'] ?? '—'}',
                    '${standing['team']?['name'] ?? '미제공'}',
                    '${standing['team']?['record']?['wins'] ?? '—'}',
                    '${standing['team']?['record']?['losses'] ?? '—'}',
                  ],
              ],
            ),
          );
        }
      }
    }
    return result;
  }
}
