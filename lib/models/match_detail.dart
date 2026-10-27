import '../services/report_text.dart';

class TeamStatistics {
  const TeamStatistics(this.name, this.values, this.labels);
  final String name;
  final Map<String, String> values, labels;
}

class MatchDetail {
  const MatchDetail({this.article = '', this.teams = const []});
  final String article;
  final List<TeamStatistics> teams;
  List<String> get statKeys =>
      {for (final team in teams) ...team.values.keys}.toList();
  String label(String key) {
    for (final team in teams) {
      if (team.labels.containsKey(key)) return team.labels[key]!;
    }
    return key;
  }

  String get asText => [
    article,
    for (final team in teams) ...[
      team.name,
      for (final key in team.values.keys)
        '${team.labels[key] ?? key}: ${team.values[key]}',
    ],
  ].where((s) => s.isNotEmpty).join('\n');

  factory MatchDetail.fromEspn(Map<String, dynamic> data) {
    final article = data['article'] as Map<String, dynamic>?;
    return MatchDetail(
      article: readableReport(
        '${article?['headline'] ?? ''}\n${article?['story'] ?? ''}',
      ),
      teams: [
        for (final row in data['boxscore']?['teams'] as List? ?? [])
          TeamStatistics(
            row['team']?['displayName']?.toString() ?? '팀',
            {
              for (final stat in row['statistics'] as List? ?? [])
                if (stat['displayValue'] != null &&
                    (stat['name'] ?? stat['label']) != null)
                  (stat['name'] ?? stat['label']).toString():
                      stat['displayValue'].toString(),
            },
            {
              for (final stat in row['statistics'] as List? ?? [])
                if ((stat['name'] ?? stat['label']) != null)
                  (stat['name'] ?? stat['label']).toString():
                      (stat['label'] ?? stat['name']).toString(),
            },
          ),
      ],
    );
  }
}
