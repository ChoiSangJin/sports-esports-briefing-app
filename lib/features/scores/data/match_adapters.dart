import '../../../models/unified_match_model.dart';

typedef Json = Map<String, dynamic>;

class EspnAdapter {
  static List<UnifiedMatchModel> parse(Json json, League league) => [
    for (final event in (json['events'] as List? ?? []))
      _event(event as Json, league),
  ];

  static UnifiedMatchModel _event(Json e, League league) {
    final competition = (e['competitions'] as List).first as Json;
    final status = (e['status'] ?? competition['status']) as Json;
    final type = status['type'] as Json;
    final competitors = competition['competitors'] as List;
    return UnifiedMatchModel(
      id: 'espn:${league.name}:${e['id']}',
      league: league,
      startsAt: DateTime.parse(e['date'] as String),
      title: (e['name'] ?? e['shortName'] ?? league.label).toString(),
      state: type['completed'] == true
          ? MatchState.finalScore
          : type['state'] == 'in'
          ? MatchState.live
          : MatchState.scheduled,
      status: (type['detail'] ?? type['description'] ?? '').toString(),
      participants: [
        for (final c in competitors)
          Participant(
            name: (c['team']['displayName'] ?? c['team']['name']).toString(),
            score: type['state'] == 'pre' ? null : c['score']?.toString(),
            logo: c['team']['logo'] as String?,
            winner: c['winner'] == true,
          ),
      ],
      lines: [
        for (final c in competitors)
          if ((c['linescores'] as List? ?? []).isNotEmpty)
            '${c['team']['displayName']}: ${(c['linescores'] as List).map((s) => s['displayValue'] ?? s['value']).join(' | ')}',
      ],
    );
  }
}

class JolpicaAdapter {
  static List<UnifiedMatchModel> schedule(Json json) => [
    for (final race in json['MRData']['RaceTable']['Races'] as List)
      UnifiedMatchModel(
        id: 'f1:${race['season']}:${race['round']}',
        league: League.f1,
        startsAt: DateTime.parse(
          '${race['date']}T${race['time'] ?? '00:00:00Z'}',
        ),
        title: race['raceName'].toString(),
        state: MatchState.scheduled,
        status: '${race['raceName']} · 예정 · Round ${race['round']}',
        source: 'Jolpica F1 일정',
      ),
  ];
  static List<UnifiedMatchModel> parse(Json json) => [
    for (final race in (json['MRData']['RaceTable']['Races'] as List))
      UnifiedMatchModel(
        id: 'f1:${race['season']}:${race['round']}',
        league: League.f1,
        startsAt: DateTime.parse(
          '${race['date']}T${race['time'] ?? '00:00:00Z'}',
        ),
        title: race['raceName'].toString(),
        state: MatchState.finalScore,
        status: 'FINAL · Round ${race['round']}',
        standings: [
          for (final r in race['Results'])
            RaceStanding(
              r['position'].toString(),
              '${r['Driver']['givenName']} ${r['Driver']['familyName']}',
              r['Constructor']['name'].toString(),
              (r['Time']?['time'] ?? r['status']).toString(),
              r['points'].toString(),
            ),
        ],
      ),
  ];
}
