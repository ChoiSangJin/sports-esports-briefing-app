import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/scores/data/score_repository.dart';
import '../models/unified_match_model.dart';
import 'api_key_storage_service.dart';
import 'ai_summary_service.dart';

final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);
final keyStorageProvider = Provider((ref) => ApiKeyStorageService());
final keyPresentProvider = FutureProvider<bool>((ref) async {
  final key = await ref.watch(keyStorageProvider).read();
  return key != null && key.isNotEmpty;
});
final aiProvider = Provider(
  (ref) => AiSummaryService(
    ref.watch(preferencesProvider),
    ref.watch(keyStorageProvider),
  ),
);
final dioProvider = Provider((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  ref.onDispose(() => dio.close());
  return dio;
});
final repositoryProvider = Provider(
  (ref) => ScoreRepository(ref.watch(dioProvider)),
);
final selectedDateProvider = StateProvider((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});
final selectedLeagueProvider = StateProvider<League?>((ref) => null);
final favoritesProvider = StateNotifierProvider<Favorites, Set<League>>(
  (ref) => Favorites(ref.watch(preferencesProvider)),
);

class Favorites extends StateNotifier<Set<League>> {
  Favorites(this.preferences)
    : super({
        for (final league in League.values)
          if ((preferences.getStringList('favorite_leagues') ?? []).contains(
            league.name,
          ))
            league,
      });
  final SharedPreferences preferences;
  Future<void> toggle(League league) async {
    state = state.contains(league)
        ? ({...state}..remove(league))
        : {...state, league};
    await preferences.setStringList(
      'favorite_leagues',
      state.map((e) => e.name).toList(),
    );
  }
}

final leagueScoresProvider = FutureProvider.family<LeagueResult, League>(
  (ref, league) => ref
      .watch(repositoryProvider)
      .load(league, ref.watch(selectedDateProvider)),
);
