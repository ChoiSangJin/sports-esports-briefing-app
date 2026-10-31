import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';
import 'package:sports_esports_briefing/services/ai_summary_service.dart';
import 'package:sports_esports_briefing/services/api_key_storage_service.dart';

class MemoryKeys extends ApiKeyStorageService {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> save(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  late SharedPreferences preferences;
  late MemoryKeys keys;
  late UnifiedMatchModel fixture;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'ai_model': 'gemini-test-model'});
    preferences = await SharedPreferences.getInstance();
    keys = MemoryKeys();
    fixture = UnifiedMatchModel(
      id: 'test:1',
      league: League.nba,
      startsAt: DateTime(2026),
      title: 'Final',
      state: MatchState.finalScore,
    );
  });

  test(
    'invalid key is never persisted and provider errors are sanitized',
    () async {
      final service = AiSummaryService(
        preferences,
        keys,
        generate: (_, model, prompt) async =>
            throw Exception('secret provider detail'),
      );
      await expectLater(
        service.validateAndSave(' invalid ', 'gemini-2.5-flash'),
        throwsA(
          isA<AiFailure>().having(
            (e) => e.message.contains('secret'),
            'does not leak error',
            false,
          ),
        ),
      );
      expect(keys.value, isNull);
    },
  );

  test(
    'successful validation trims and saves key only after test response',
    () async {
      final service = AiSummaryService(
        preferences,
        keys,
        generate: (key, model, prompt) async {
          expect(keys.value, isNull);
          expect(key, 'example-test-key');
          return 'OK';
        },
      );
      await service.validateAndSave(' example-test-key ', 'gemini-2.5-pro');
      expect(keys.value, 'example-test-key');
      expect(service.model, 'gemini-2.5-pro');
    },
  );

  test(
    'cache persists across services and works without a key; refresh calls API',
    () async {
      keys.value = 'example-test-key';
      var calls = 0;
      Future<String> generate(String key, String model, String prompt) async =>
          '요약 ${++calls}';
      final service = AiSummaryService(preferences, keys, generate: generate);
      expect(await service.summarize(fixture, 'report'), '요약 1');
      final next = AiSummaryService(preferences, keys, generate: generate);
      keys.value = null;
      expect(await next.summarize(fixture, 'report'), '요약 1');
      expect(calls, 1);
      keys.value = 'example-test-key';
      expect(await next.summarize(fixture, 'report', refresh: true), '요약 2');
      await next.setModel('gemini-2.5-pro');
      expect(next.cached(fixture), isNull);
    },
  );

  test(
    'concurrent taps deduplicate API calls and example data cannot invoke AI',
    () async {
      keys.value = 'example-test-key';
      var calls = 0;
      final service = AiSummaryService(
        preferences,
        keys,
        generate: (_, model, prompt) async {
          calls++;
          return 'summary';
        },
      );
      await Future.wait([
        service.summarize(fixture, ''),
        service.summarize(fixture, ''),
      ]);
      expect(calls, 1);
      final example = UnifiedMatchModel(
        id: 'example',
        league: League.kbo,
        startsAt: DateTime(2026),
        title: 'Example',
        state: MatchState.finalScore,
        isExample: true,
      );
      await expectLater(
        service.summarize(example, ''),
        throwsA(isA<AiFailure>()),
      );
      expect(calls, 1);
    },
  );
  test('pregame summaries are not reused as final game reports', () async {
    keys.value = 'test-key';
    var calls = 0;
    final service = AiSummaryService(
      preferences,
      keys,
      generate: (_, model, prompt) async => 'summary ${++calls}',
    );
    final upcoming = UnifiedMatchModel(
      id: fixture.id,
      league: fixture.league,
      startsAt: fixture.startsAt,
      title: fixture.title,
      state: MatchState.scheduled,
    );
    await service.summarize(upcoming, 'preview only');
    expect(service.cached(fixture), isNull);
    expect(await service.summarize(fixture, 'final records'), 'summary 2');
    expect(calls, 2);
  });
  test(
    'LoL update does not reuse summaries cached without player statistics',
    () async {
      final match = UnifiedMatchModel(
        id: 'lol:riot:1',
        league: League.lol,
        startsAt: DateTime(2026),
        title: 'Final',
        state: MatchState.finalScore,
      );
      await preferences.setString(
        'summary:v2:${match.id}:finalScore:gemini-test-model',
        '{"text":"old missing records","state":"finalScore","savedAt":"2026-10-30T00:00:00Z"}',
      );
      final service = AiSummaryService(preferences, keys);
      expect(service.cached(match), isNull);
    },
  );
}
