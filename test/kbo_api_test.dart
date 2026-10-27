import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/kbo_service.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'support/http_fixture.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'KBO official final response produces actual winner and Korean-time game',
    () {
      final match = KboService.parseApi(
        fixture('kbo-final'),
        DateTime(2026, 10, 26),
      ).single;
      expect(match.state, MatchState.finalScore);
      expect(match.participants.first.name, 'KIA');
      expect(match.participants.first.score, '5');
      expect(match.participants.first.winner, isTrue);
      expect(match.participants.last.score, '1');
      expect(match.startsAt.toUtc(), DateTime.utc(2026, 10, 26, 9, 30));
      expect(match.sourceUrl, contains('gameId=20261026HTSS0'));
    },
  );

  test(
    'scheduled and cancelled games cannot display fake zero scores or winners',
    () {
      final data = fixture('kbo-games');
      final scheduled = KboService.parseApi(
        data,
        DateTime(2026, 10, 27),
      ).single;
      expect(scheduled.state, MatchState.scheduled);
      expect(
        scheduled.participants.every((p) => p.score == null && !p.winner),
        isTrue,
      );
      data['game'][0]['GAME_STATE_SC'] = '4';
      data['game'][0]['CANCEL_SC_ID'] = '1';
      data['game'][0]['CANCEL_SC_NM'] = '우천 취소';
      final cancelled = KboService.parseApi(
        data,
        DateTime(2026, 10, 27),
      ).single;
      expect(cancelled.state, MatchState.cancelled);
      expect(cancelled.status, contains('우천 취소'));
      expect(cancelled.participants.every((p) => p.score == null), isTrue);
    },
  );

  test(
    'empty game list is valid, wrong dates and provider failures are rejected',
    () {
      expect(
        KboService.parseApi({'game': [], 'code': '100'}, DateTime(2026)),
        isEmpty,
      );
      expect(
        () => KboService.parseApi(fixture('kbo-final'), DateTime(2026, 10, 27)),
        throwsFormatException,
      );
      expect(
        () => KboService.parseApi({'code': '500'}, DateTime(2026)),
        throwsFormatException,
      );
    },
  );

  test(
    'official request carries AJAX context and form fields, never parses an HTML error as no games',
    () async {
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = HttpFixture((options) {
          requests++;
          expect(options.method, 'POST');
          expect(options.uri.host, 'www.koreabaseball.com');
          expect(options.headers['X-Requested-With'], 'XMLHttpRequest');
          expect(
            options.headers['Referer'],
            contains('/Schedule/GameCenter/Main.aspx'),
          );
          expect(options.contentType, Headers.formUrlEncodedContentType);
          expect((options.data as Map)['leId'], '1');
          return textResponse('<html>temporary error</html>');
        });
      await expectLater(
        KboService(dio).load(DateTime(2026, 10, 27)),
        throwsFormatException,
      );
      expect(requests, greaterThanOrEqualTo(1));
    },
  );
}
