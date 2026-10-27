import 'package:html/parser.dart' as html;
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

class LeaguepediaAdapter {
  static List<UnifiedMatchModel> parse(Json json) => [
    for (final row in (json['cargoquery'] as List? ?? []))
      _match(row['title'] as Json),
  ];

  static UnifiedMatchModel _match(Json row) {
    String value(String key) =>
        html.parseFragment('${row[key] ?? ''}').text ?? '';
    final time = value('DateTime UTC').isEmpty
        ? value('DateTime_UTC')
        : value('DateTime UTC');
    final winner = value('Winner');
    return UnifiedMatchModel(
      id: 'lol:${value('MatchId')}',
      league: League.lol,
      startsAt: DateTime.parse('${time.replaceFirst(' ', 'T')}Z'),
      title: value('ShownName'),
      state: winner.isNotEmpty ? MatchState.finalScore : MatchState.scheduled,
      status: winner.isNotEmpty
          ? 'FINAL · ${value('Tab')}'
          : '예정 · ${value('Tab')}',
      participants: [
        for (var i = 1; i <= 2; i++)
          Participant(
            name: value('Team$i'),
            score: value('Team${i}Score').isEmpty
                ? null
                : value('Team${i}Score'),
            winner: winner == '$i' || winner == value('Team$i'),
          ),
      ],
    );
  }
}
