import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../../../models/unified_match_model.dart';

class KboScraperService {
  KboScraperService(this.dio);
  final Dio dio;

  Future<List<UnifiedMatchModel>> load(DateTime day) async {
    final response = await dio.get<String>(
      'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx',
      queryParameters: {
        'gameDate':
            '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}',
      },
    );
    return parse(response.data ?? '', day);
  }

  static List<UnifiedMatchModel> parse(String page, DateTime day) {
    final document = html.parse(page);
    final games = document.querySelectorAll('[gameid]');
    final result = <UnifiedMatchModel>[];
    for (final game in games) {
      final teams = game.querySelectorAll('.team');
      final scores = game.querySelectorAll('.score');
      final id = game.attributes['gameid'] ?? '';
      // Refuse a response for another date; this site may ignore query parameters.
      final requested =
          '${day.year}${day.month.toString().padLeft(2, '0')}${day.day.toString().padLeft(2, '0')}';
      if (teams.length != 2 || !id.startsWith(requested)) continue;
      final status = game.querySelector('.staus, .status')?.text.trim() ?? '';
      final finalScore = status.contains('종료');
      final values = scores.map((e) => int.tryParse(e.text.trim())).toList();
      result.add(
        UnifiedMatchModel(
          id: 'kbo:$id',
          league: League.kbo,
          startsAt: day,
          title: '${teams[0].text.trim()} vs ${teams[1].text.trim()}',
          state: finalScore
              ? MatchState.finalScore
              : status.contains('진행')
              ? MatchState.live
              : MatchState.scheduled,
          status: status,
          participants: [
            for (var i = 0; i < 2; i++)
              Participant(
                name: teams[i].text.trim(),
                score: values.length == 2 ? values[i]?.toString() : null,
                winner:
                    finalScore &&
                    values.length == 2 &&
                    values[i] != null &&
                    values[1 - i] != null &&
                    values[i]! > values[1 - i]!,
              ),
          ],
        ),
      );
    }
    if (result.isEmpty) {
      throw const FormatException(
        'KBO page has no verified games for this date',
      );
    }
    return result;
  }

  static UnifiedMatchModel example(DateTime day) => UnifiedMatchModel(
    id: 'example:kbo',
    league: League.kbo,
    startsAt: day,
    title: 'KBO 화면 예시 · 실제 경기 아님',
    state: MatchState.finalScore,
    status: '예시 데이터',
    isExample: true,
    participants: const [
      Participant(name: '홈팀 예시', score: '5', winner: true),
      Participant(name: '원정팀 예시', score: '3'),
    ],
  );
}
