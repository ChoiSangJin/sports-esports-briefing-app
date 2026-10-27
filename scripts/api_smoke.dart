import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:sports_esports_briefing/features/scores/data/score_repository.dart';
import 'package:sports_esports_briefing/models/unified_match_model.dart';

Future<void> main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  final proxy = Platform.environment['HTTPS_PROXY'];
  if (proxy != null && proxy.isNotEmpty) {
    final uri = Uri.parse(proxy);
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        return HttpClient()..findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
      },
    );
  }
  final repository = ScoreRepository(dio);
  final results = await Future.wait(
    League.values.map((league) => repository.load(league, DateTime.now())),
  );
  for (final r in results) {
    stdout.writeln(
      '${r.league.label}: ${r.warning ?? '${r.matches.length} matches'}',
    );
    if (r.source.isNotEmpty) stdout.writeln('  source: ${r.source}');
    if (r.league == League.lol || r.league == League.kbo) {
      for (final match in r.matches.take(3)) {
        stdout.writeln(
          '  ${match.startsAt.toLocal().toIso8601String()} ${match.status} ${match.participants.map((p) => '${p.name} ${p.score ?? "—"}').join(' vs ')}',
        );
      }
    }
    if (r.matches.isNotEmpty && ScoreRepository.paths.containsKey(r.league)) {
      try {
        final detail = await repository.detail(r.matches.first);
        stdout.writeln(
          '  detail: ${detail.isEmpty ? 'no report provided' : '${detail.length} characters'}',
        );
      } catch (_) {
        stdout.writeln('  detail unavailable');
      }
    }
  }
  dio.close();
}
