import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/unified_match_model.dart';
import '../../../services/providers.dart';
import '../../../theme/tactical_dark_theme.dart';
import '../../settings/api_key_sheet.dart';
import '../data/kbo_scraper_service.dart';
import 'match_card.dart';
import 'match_detail_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedDateProvider);
    final selected = ref.watch(selectedLeagueProvider);
    final favorites = ref.watch(favoritesProvider);
    final leagues = [...League.values]
      ..sort((a, b) {
        final favored =
            (favorites.contains(b) ? 1 : 0) - (favorites.contains(a) ? 1 : 0);
        return favored != 0 ? favored : a.index.compareTo(b.index);
      });
    final keyStatus = ref.watch(keyPresentProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TACTICAL SPORTS',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '스포츠 & e스포츠 브리핑',
              style: TextStyle(fontSize: 11, color: TacticalColors.secondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'API Key & 설정',
            onPressed: () => showApiKeySheet(context),
            icon: Badge(
              backgroundColor: keyStatus.hasError
                  ? Colors.amber
                  : keyStatus.valueOrNull == true
                  ? Colors.greenAccent
                  : Colors.redAccent,
              smallSize: 8,
              child: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '이전 날짜',
                  onPressed: () =>
                      ref.read(selectedDateProvider.notifier).state = DateTime(
                        day.year,
                        day.month,
                        day.day - 1,
                      ),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      ref.read(selectedDateProvider.notifier).state = picked;
                    }
                  },
                  child: Text(
                    '${day.year}.${day.month.toString().padLeft(2, '0')}.${day.day.toString().padLeft(2, '0')}',
                    style: scoreStyle.copyWith(fontSize: 18),
                  ),
                ),
                IconButton(
                  tooltip: '다음 날짜',
                  onPressed: () =>
                      ref.read(selectedDateProvider.notifier).state = DateTime(
                        day.year,
                        day.month,
                        day.day + 1,
                      ),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () {
                    final now = DateTime.now();
                    ref.read(selectedDateProvider.notifier).state = DateTime(
                      now.year,
                      now.month,
                      now.day,
                    );
                  },
                  child: const Text('오늘'),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '기기 현지 날짜 기준 · 아래로 당겨 새로고침',
                style: TextStyle(color: TacticalColors.secondary, fontSize: 11),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('ALL'),
                      selected: selected == null,
                      onSelected: (_) =>
                          ref.read(selectedLeagueProvider.notifier).state =
                              null,
                    ),
                  ),
                  for (final league in League.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(league.label),
                        selected: selected == league,
                        selectedColor: TacticalColors.league(
                          league,
                        ).withValues(alpha: 0.15),
                        side: selected == league
                            ? BorderSide(color: TacticalColors.league(league))
                            : null,
                        onSelected: (_) =>
                            ref.read(selectedLeagueProvider.notifier).state =
                                league,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final targets = selected == null ? leagues : [selected];
                  for (final league in targets) {
                    ref.invalidate(leagueScoresProvider(league));
                  }
                  await Future.wait(
                    targets.map(
                      (league) => ref.read(leagueScoresProvider(league).future),
                    ),
                  );
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    for (final league
                        in (selected == null ? leagues : [selected]))
                      _LeagueSection(league: league),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '공개 제공처 데이터 · 지연 또는 누락될 수 있습니다.\nAI 요약은 Google에 경기 자료를 전송하며 오류가 있을 수 있습니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: TacticalColors.secondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeagueSection extends ConsumerWidget {
  const _LeagueSection({required this.league});
  final League league;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(leagueScoresProvider(league));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 8),
          child: Text(
            league.label,
            style: TextStyle(
              color: TacticalColors.league(league),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        result.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: LinearProgressIndicator(),
          ),
          error: (_, stack) => const Text('데이터를 불러오지 못했습니다.'),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.warning != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.warning!,
                        style: const TextStyle(color: TacticalColors.secondary),
                      ),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () =>
                                ref.invalidate(leagueScoresProvider(league)),
                            child: const Text('다시 시도'),
                          ),
                          if (league == League.kbo)
                            TextButton(
                              onPressed: () => showMatchDetail(
                                context,
                                KboScraperService.example(
                                  ref.read(selectedDateProvider),
                                ),
                              ),
                              child: const Text('예시 화면 보기 (실제 경기 아님)'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (data.warning == null && data.matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    '이 날짜에 제공된 경기가 없습니다.',
                    style: TextStyle(color: TacticalColors.secondary),
                  ),
                ),
              for (final match in data.matches)
                MatchCard(
                  match: match,
                  onTap: () => showMatchDetail(context, match),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
