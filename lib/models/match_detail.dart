import '../services/report_text.dart';

class TeamStatistics {
  const TeamStatistics(this.name, this.values, this.labels);
  final String name;
  final Map<String, String> values, labels;
}

class MatchDetail {
  const MatchDetail({
    this.article = '',
    this.teams = const [],
    this.news = const [],
    this.plays = const [],
    this.sections = const [],
    this.notices = const [],
  });
  final String article;
  final List<TeamStatistics> teams;
  final List<RelatedArticle> news;
  final List<String> plays;
  final List<RecordSection> sections;
  final List<String> notices;
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
    if (plays.isNotEmpty) '제공처의 주요 경기 기록:',
    ...plays,
    for (final section in sections) ...[
      section.title,
      section.headers.join(' | '),
      for (final row in section.rows) row.join(' | '),
    ],
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
      news: [
        for (final item
            in (data['news'] is Map ? data['news']['articles'] : data['news'])
                    as List? ??
                [])
          if (item['type'] == 'Story' &&
              item['links']?['web']?['href'] is String &&
              Uri.tryParse(item['links']['web']['href'])?.scheme == 'https')
            RelatedArticle(
              item['headline']?.toString() ?? '관련 기사',
              readableReport(item['description']?.toString() ?? ''),
              item['links']['web']['href'] as String,
            ),
      ],
      plays: [
        for (final play
            in ((data['plays'] as List? ?? []).isNotEmpty
                        ? data['plays']
                        : data['keyEvents'])
                    as List? ??
                [])
          if (play['scoringPlay'] == true && play['text'] is String)
            readableReport(
              '${play['clock']?['displayValue'] != null && data['keyEvents'] != null ? '${play['clock']['displayValue']} · ' : ''}${play['text']}',
            ),
      ].take(12).toList(),
      teams: [
        for (final row in data['boxscore']?['teams'] as List? ?? [])
          _statistics(row as Map<String, dynamic>),
      ],
    );
  }

  static TeamStatistics _statistics(Map<String, dynamic> row) {
    final values = <String, String>{}, labels = <String, String>{};
    void read(List items, String prefix, String group) {
      for (final stat in items) {
        final name = (stat['name'] ?? stat['label'] ?? stat['displayName'])
            ?.toString();
        if (name == null) continue;
        final id = '$prefix$name';
        final label = (stat['label'] ?? stat['displayName'] ?? name).toString();
        if (stat['displayValue'] != null) {
          values[id] = stat['displayValue'].toString();
          labels[id] = group.isEmpty ? label : '$group · $label';
        }
        final nested = stat['stats'] ?? stat['statistics'];
        if (nested is List) {
          read(nested, '$id/', group.isEmpty ? label : '$group · $label');
        }
      }
    }

    read(row['statistics'] as List? ?? [], '', '');
    return TeamStatistics(
      row['team']?['displayName']?.toString() ?? '팀',
      values,
      labels,
    );
  }
}

class RecordSection {
  const RecordSection(this.title, this.headers, this.rows);
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
}

class RelatedArticle {
  const RelatedArticle(this.title, this.description, this.url);
  final String title, description, url;
}
