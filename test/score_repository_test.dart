import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.respond);
  final Object Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(respond(options)),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'date range encloses local day and filters events by timestamp',
    () async {
      final day = DateTime(2026, 10, 27);
      final dio = Dio()
        ..httpClientAdapter = FixtureAdapter((options) {
          expect([
            '20261026',
            '20261027',
            '20261028',
          ], contains(options.queryParameters['dates']));
          Map<String, dynamic> event(String id, DateTime time) => {
            'id': id,
            'date': time.toUtc().toIso8601String(),
            'name': 'Game $id',
            'status': {
              'type': {'state': 'pre'},
            },
            'competitions': [
              {'competitors': []},
            ],
          };
          return {
            'events': [
              event('in', day.add(const Duration(hours: 1))),
              event('out', day.subtract(const Duration(hours: 1))),
            ],
          };
        });
      final result = await ScoreRepository(dio).load(League.nba, day);
      expect(result.warning, isNull);
      expect(result.matches.single.id, 'espn:nba:in');
    },
  );

  test('one source failure does not discard another source response', () async {
    final dio = Dio()
      ..httpClientAdapter = FixtureAdapter((options) {
        if (options.uri.path.contains('basketball')) {
          throw const FormatException('source changed');
        }
        return {'events': []};
      });
    final repository = ScoreRepository(dio);
    final results = await Future.wait([
      repository.load(League.nba, DateTime(2026)),
      repository.load(League.nfl, DateTime(2026)),
    ]);
    expect(results.first.warning, contains('NBA'));
    expect(results.last.warning, contains('14일'));
    expect(results.last.warning, isNot(contains('데이터를 불러오지 못')));
    expect(results.first.matches, isEmpty);
  });
}
