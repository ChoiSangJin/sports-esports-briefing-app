import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../models/unified_match_model.dart';
import 'kbo_season_service.dart';

class KboService {
  KboService(this.dio);
  final Dio dio;

  Future<List<UnifiedMatchModel>> load(DateTime day) async {
    // KBO's public GameCenter AJAX endpoint requires its normal page context.
    // It returns an HTML error page without these headers, even with HTTP 200.
    final start = DateTime(
      day.year,
      day.month,
      day.day,
    ).toUtc().add(const Duration(hours: 9));
    final end = DateTime(day.year, day.month, day.day + 1)
        .toUtc()
        .subtract(const Duration(microseconds: 1))
        .add(const Duration(hours: 9));
    final dates = {
      DateTime.utc(start.year, start.month, start.day),
      DateTime.utc(end.year, end.month, end.day),
    };
    final responses = await Future.wait([
      for (final date in dates) _loadKoreanDay(date),
    ]);
    return [
      for (final games in responses) ...games,
    ].where((m) => sameDay(m.startsAt, day)).toList();
  }

  Future<List<UnifiedMatchModel>> _loadKoreanDay(DateTime date) async {
    final response = await dio.post<String>(
      'https://www.koreabaseball.com/ws/Main.asmx/GetKboGameList',
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Referer':
              'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx',
          'X-Requested-With': 'XMLHttpRequest',
        },
      ),
      data: {'leId': '1', 'srId': '0,1,3,4,5,6,7,8,9', 'date': _date(date)},
    );
    dynamic data = jsonDecode(
      (response.data ?? '').replaceFirst('\uFEFF', '').trim(),
    );
    if (data is Map && data['d'] != null) {
      data = data['d'] is String ? jsonDecode(data['d'] as String) : data['d'];
    }
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid KBO response');
    }
    return parseApi(data, date);
  }

  Future<DateTime?> nextDate(DateTime day) =>
      KboSeasonService(dio).nextDate(day);

  static String _date(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static List<UnifiedMatchModel> parseApi(
    Map<String, dynamic> json,
    DateTime day,
  ) {
    if (json['game'] is! List ||
        (json['code'] != null && json['code'].toString() != '100')) {
      throw const FormatException('KBO games unavailable');
    }
    final result = <UnifiedMatchModel>[];
    final requested = _date(day);
    for (final g in json['game'] as List) {
      final id = g['G_ID']?.toString() ?? '';
      if (g['G_DT'] != requested || !id.startsWith(requested)) {
        throw const FormatException('KBO response date mismatch');
      }
      final home = g['HOME_NM']?.toString() ?? '',
          away = g['AWAY_NM']?.toString() ?? '';
      if (home.isEmpty || away.isEmpty) {
        throw const FormatException('KBO teams missing');
      }
      final cancelled =
          g['GAME_STATE_SC']?.toString() == '4' ||
          (g['CANCEL_SC_ID'] != null && g['CANCEL_SC_ID'].toString() != '0');
      final state = cancelled
          ? MatchState.cancelled
          : g['GAME_STATE_SC']?.toString() == '3' ||
                g['GAME_RESULT_CK']?.toString() == '1'
          ? MatchState.finalScore
          : g['GAME_STATE_SC']?.toString() == '2'
          ? MatchState.live
          : MatchState.scheduled;
      final a = int.tryParse(g['T_SCORE_CN']?.toString() ?? ''),
          h = int.tryParse(g['B_SCORE_CN']?.toString() ?? '');
      final time = g['G_TM']?.toString() ?? '';
      if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(time)) {
        throw const FormatException('KBO game time unavailable');
      }
      final startsAt = DateTime.parse(
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}T$time:00+09:00',
      );
      final label = switch (state) {
        MatchState.finalScore => '종료',
        MatchState.live => '진행 중',
        MatchState.cancelled => g['CANCEL_SC_NM']?.toString() ?? '취소 / 연기',
        _ => '예정',
      };
      result.add(
        UnifiedMatchModel(
          id: 'kbo:$id',
          league: League.kbo,
          startsAt: startsAt,
          title: '$away vs $home',
          state: state,
          status: '$label · ${g['S_NM'] ?? ''} · $time KST',
          source: 'KBO 공식 게임센터',
          detailParameters: {
            'leId': '${g['LE_ID'] ?? 1}',
            'srId': '${g['SR_ID']}',
            'seasonId': '${g['SEASON_ID']}',
            'gameId': id,
          },
          sourceUrl:
              'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate=$requested&gameId=$id',
          participants: [
            Participant(
              name: away,
              score: state == MatchState.live || state == MatchState.finalScore
                  ? a?.toString()
                  : null,
              winner:
                  state == MatchState.finalScore &&
                  a != null &&
                  h != null &&
                  a > h,
            ),
            Participant(
              name: home,
              score: state == MatchState.live || state == MatchState.finalScore
                  ? h?.toString()
                  : null,
              winner:
                  state == MatchState.finalScore &&
                  a != null &&
                  h != null &&
                  h > a,
            ),
          ],
          lines: [
            if (g['GAME_INN_NO'] != null)
              '${g['GAME_INN_NO']}회 ${g['GAME_TB_SC_NM'] ?? ''}',
          ],
          report: [
            if (g['W_PIT_P_NM']?.toString().trim().isNotEmpty == true)
              '승리 투수: ${g['W_PIT_P_NM']}',
            if (g['L_PIT_P_NM']?.toString().trim().isNotEmpty == true)
              '패전 투수: ${g['L_PIT_P_NM']}',
          ].join('\n'),
        ),
      );
    }
    return result;
  }
}
