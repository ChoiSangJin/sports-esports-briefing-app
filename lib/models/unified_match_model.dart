enum League { lol, f1, mlb, nba, nfl, kbo }

extension LeagueLabel on League {
  String get label => switch (this) {
    League.lol => 'LoL e스포츠',
    League.f1 => 'F1',
    League.mlb => 'MLB',
    League.nba => 'NBA',
    League.nfl => 'NFL',
    League.kbo => 'KBO',
  };
}

enum MatchState { scheduled, live, finalScore, cancelled }

extension MatchStateLabel on MatchState {
  String get label => switch (this) {
    MatchState.scheduled => '예정',
    MatchState.live => 'LIVE',
    MatchState.finalScore => 'FINAL',
    MatchState.cancelled => '취소 / 연기',
  };
}

class Participant {
  const Participant({
    required this.name,
    this.score,
    this.logo,
    this.winner = false,
  });
  final String name;
  final String? score;
  final String? logo;
  final bool winner;
}

class RaceStanding {
  const RaceStanding(
    this.position,
    this.driver,
    this.team,
    this.time,
    this.points,
  );
  final String position, driver, team, time, points;
}

class UnifiedMatchModel {
  const UnifiedMatchModel({
    required this.id,
    required this.league,
    required this.startsAt,
    required this.title,
    required this.state,
    this.participants = const [],
    this.standings = const [],
    this.status = '',
    this.report = '',
    this.lines = const [],
    this.isExample = false,
    this.source = '',
    this.sourceUrl,
    this.detailParameters = const {},
  });
  final String id, title, status, report;
  final League league;
  final DateTime startsAt;
  final MatchState state;
  final List<Participant> participants;
  final List<RaceStanding> standings;
  final List<String> lines;
  final bool isExample;
  final String source;
  final String? sourceUrl;
  final Map<String, String> detailParameters;

  String get aiContext => [
    'Source: ${league.label}; match: $id; date: ${startsAt.toIso8601String()}',
    title,
    status,
    if (source.isNotEmpty) 'Data provider: $source',
    for (final p in participants) '${p.name}: ${p.score ?? "scheduled"}',
    ...lines,
    for (final r in standings)
      '${r.position}. ${r.driver} (${r.team}) ${r.time}, ${r.points} points',
    report,
  ].join('\n');
}

bool sameDay(DateTime a, DateTime b) {
  final local = a.toLocal();
  return local.year == b.year && local.month == b.month && local.day == b.day;
}
