// Optional read-only live check. Run: dart run scripts/check_korean_sources.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sports_esports_briefing/features/scores/data/korean_league_service.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  final now = DateTime.now();
  for (final league in [League.kbl, League.kleague1]) {
    final service = KoreanLeagueService(dio);
    try {
      final matches = await service.month(league, now);
      stdout.writeln('${league.label}: matches=${matches.length}');
    } on DioException catch (e) {
      stdout.writeln(
        '${league.label}: transport failed (${e.response?.statusCode ?? e.type.name})',
      );
    } catch (_) {
      stdout.writeln('${league.label}: schema validation failed');
    }
  }
  dio.close();
}
