import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/unified_match_model.dart';

class LolScheduleService {
  LolScheduleService(this.dio);
  final Dio dio;
  int _generation = 0;
  final _days =
      <String, ({DateTime fetched, List<UnifiedMatchModel> matches})>{};
  // Public persisted document identifier from the site's published operation
  // manifest (not an API key or credential). Fail visibly if it is retired.
  static const scheduleOperation =
      '7e9af7acad0f697e265c1f2fa49e5ba6bbf409e35cf1700dc2202ff00169f715';

  Future<List<UnifiedMatchModel>> loadDay(DateTime day) async {
    final generation = _generation;
    final key = '${day.year}-${day.month}-${day.day}';
    final cached = _days[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetched).inSeconds < 20) {
      return cached.matches;
    }
    String date(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final start = DateTime(day.year, day.month, day.day).toUtc();
    final end = DateTime(day.year, day.month, day.day + 1).toUtc();
    final found = <String, UnifiedMatchModel>{};
    // The upstream treats mixed states differently; query each explicitly.
    for (final state in ['completed', 'inProgress', 'unstarted']) {
      String? token;
      final seen = <String>{};
      for (var page = 0; page < 10; page++) {
        final response = await dio.post<Map<String, dynamic>>(
          'https://lolesports.com/api/gql',
          options: Options(
            headers: {
              'apollographql-client-name': 'Sports Briefing',
              'apollographql-client-version': '1.8.2',
            },
          ),
          data: {
            'operationName': 'scheduleEvents',
            'variables': {
              'hl': 'ko-KR',
              'sport': ['lol'],
              'eventType': 'match',
              'eventDateStart': date(start.subtract(const Duration(days: 1))),
              'eventDateEnd': date(end.add(const Duration(days: 1))),
              'eventState': [state],
              'pageSize': 100,
              if (token != null) 'pageToken': token,
            },
            'extensions': {
              'persistedQuery': {'version': 1, 'sha256Hash': scheduleOperation},
            },
          },
        );
        final body = response.data;
        if (body == null ||
            (body['errors'] as List? ?? []).isNotEmpty ||
            body['data']?['esports']?['events'] is! List) {
          throw const FormatException(
            'Official date-specific schedule unavailable',
          );
        }
        final data = body['data']['esports'];
        for (final event in data['events'] as List) {
          if (event['type'] != 'match') continue;
          final match = _match(event as Map<String, dynamic>);
          if (sameDay(match.startsAt, day)) _store(found, match);
        }
        token = data['pages']?['older'] as String?;
        if (token == null) break;
        if (!seen.add(token) || page == 9) {
          throw const FormatException('Incomplete official schedule pages');
        }
      }
    }
    final matches = found.values.toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (generation == _generation) {
      _days[key] = (fetched: DateTime.now(), matches: matches);
    }
    return matches;
  }

  Future<List<UnifiedMatchModel>> upcoming(DateTime from) async {
    String date(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final response = await dio.post<Map<String, dynamic>>(
      'https://lolesports.com/api/gql',
      options: Options(
        headers: {
          'apollographql-client-name': 'Sports Briefing',
          'apollographql-client-version': '1.8.2',
        },
      ),
      data: {
        'operationName': 'scheduleEvents',
        'variables': {
          'hl': 'ko-KR',
          'sport': ['lol'],
          'eventType': 'match',
          'eventDateStart': date(
            from.toUtc().subtract(const Duration(days: 1)),
          ),
          'eventDateEnd': date(from.toUtc().add(const Duration(days: 90))),
          'eventState': ['unstarted'],
          'pageSize': 100,
        },
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': scheduleOperation},
        },
      },
    );
    final body = response.data;
    if (body == null ||
        (body['errors'] as List? ?? []).isNotEmpty ||
        body['data']?['esports']?['events'] is! List) {
      throw const FormatException('Official upcoming schedule unavailable');
    }
    return (body['data']['esports']['events'] as List)
        .where((e) => e['type'] == 'match')
        .map((e) => _match(e as Map<String, dynamic>))
        .where(
          (m) =>
              m.startsAt.isAfter(DateTime.now()) &&
              !m.startsAt.toLocal().isBefore(from),
        )
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  List<UnifiedMatchModel>? _cached;
  DateTime? _fetchedAt;
  void clearCache() {
    _generation++;
    _cached = null;
    _fetchedAt = null;
    _days.clear();
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
          _store(matches, match);
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

  static void _store(
    Map<String, UnifiedMatchModel> matches,
    UnifiedMatchModel match,
  ) {
    int rank(MatchState state) => switch (state) {
      MatchState.finalScore || MatchState.cancelled => 3,
      MatchState.live => 2,
      _ => 1,
    };
    final previous = matches[match.id];
    if (previous == null || rank(match.state) >= rank(previous.state)) {
      matches[match.id] = match;
    }
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
