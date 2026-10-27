import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/unified_match_model.dart';

class LolScheduleService {
  LolScheduleService(this.dio);
  final Dio dio;
  List<UnifiedMatchModel>? _cached;
  DateTime? _fetchedAt;
  void clearCache() {
    _cached = null;
    _fetchedAt = null;
  }

  static const scheduleUrl = 'https://lolesports.com/ko-KR/schedule';

  Future<List<UnifiedMatchModel>> load() async {
    if (_cached != null &&
        DateTime.now().difference(_fetchedAt!).inSeconds < 60) {
      return _cached!;
    }
    final response = await dio.get<String>(scheduleUrl);
    final matches = parse(response.data ?? '');
    _cached = matches;
    _fetchedAt = DateTime.now();
    return matches;
  }

  /// Read only JSON objects embedded in the public official schedule page.
  /// Never execute JavaScript or extract/reuse the website's API credentials.
  static List<UnifiedMatchModel> parse(String page) {
    final matches = <String, UnifiedMatchModel>{};
    var start = 0;
    var validPayloads = 0;
    while (true) {
      final marker = page.indexOf('"esports":', start);
      if (marker < 0) break;
      start = marker + 10;
      var objectStart = start;
      while (objectStart < page.length && page[objectStart].trim().isEmpty) {
        objectStart++;
      }
      if (objectStart >= page.length || page[objectStart] != '{') continue;
      final end = _objectEnd(page, objectStart);
      if (end == null) continue;
      start = end;
      try {
        final payload =
            jsonDecode(page.substring(objectStart, end))
                as Map<String, dynamic>;
        if (payload['events'] is! List) continue;
        final parsed = <UnifiedMatchModel>[];
        for (final event in payload['events'] as List) {
          if (event['type'] != 'match') continue;
          final match = _match(event as Map<String, dynamic>);
          parsed.add(match);
        }
        validPayloads++;
        for (final match in parsed) {
          matches[match.id] = match;
        }
      } on FormatException {
        continue;
      }
    }
    if (validPayloads == 0) {
      throw const FormatException('Official LoL schedule schema unavailable');
    }
    return matches.values.toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  static int? _objectEnd(String text, int start) {
    var depth = 0;
    var quoted = false, escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}' && --depth == 0) {
        return i + 1;
      }
    }
    return null;
  }

  static UnifiedMatchModel _match(Map<String, dynamic> event) {
    final id = event['id']?.toString() ?? '';
    final teams = event['matchTeams'] as List? ?? [];
    if (id.isEmpty || teams.length != 2) {
      throw const FormatException('Incomplete LoL event');
    }
    final state = switch (event['state']) {
      'completed' => MatchState.finalScore,
      'inProgress' || 'in_progress' => MatchState.live,
      'canceled' || 'cancelled' || 'postponed' => MatchState.cancelled,
      _ => MatchState.scheduled,
    };
    final league = event['league']?['name']?.toString() ?? 'LoL e스포츠';
    final bestOf = event['match']?['strategy']?['count'];
    final label = switch (state) {
      MatchState.finalScore => '종료',
      MatchState.live => '진행 중',
      MatchState.cancelled => '취소 / 연기',
      _ => '예정',
    };
    return UnifiedMatchModel(
      id: 'lol:riot:$id',
      league: League.lol,
      startsAt: DateTime.parse(event['startTime'] as String),
      title: '$league · ${event['blockName'] ?? ''}',
      state: state,
      status: '$league · $label${bestOf != null ? ' · Bo$bestOf' : ''}',
      source: 'LoL e스포츠 공식 일정',
      detailParameters: {
        'teams': jsonEncode({
          for (final team in teams)
            '${team['teamId']}': '${team['name'] ?? team['code'] ?? '팀'}',
        }),
        'games': jsonEncode(event['match']?['games'] ?? []),
      },
      sourceUrl: scheduleUrl,
      participants: teams
          .map((team) => _participant(team as Map<String, dynamic>, state))
          .toList(),
      lines: [
        for (final game in event['match']?['games'] as List? ?? [])
          '${game['number']}세트: ${switch (game['state']) {
            'completed' => '종료',
            'inProgress' => '진행 중',
            'unneeded' => '미실시',
            'cancelled' || 'canceled' || 'postponed' => '취소 / 연기',
            'unstarted' => '예정',
            _ => '상태 미정',
          }}',
      ],
    );
  }

  static Participant _participant(Map<String, dynamic> team, MatchState state) {
    final result = team['result'] as Map<String, dynamic>?;
    final score = result?['gameWins']?.toString();
    return Participant(
      name: team['name']?.toString() ?? team['code']?.toString() ?? '미정',
      score: state == MatchState.live || state == MatchState.finalScore
          ? score
          : null,
      logo: team['image']?.toString().replaceFirst('http://', 'https://'),
      winner: state == MatchState.finalScore && result?['outcome'] == 'win',
    );
  }
}
