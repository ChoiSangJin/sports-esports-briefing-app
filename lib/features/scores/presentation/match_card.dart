import 'package:flutter/material.dart';
import '../../../models/unified_match_model.dart';
import '../../../theme/tactical_dark_theme.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, this.onTap});
  final UnifiedMatchModel match;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final color = TacticalColors.league(match.league);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: TacticalColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TacticalColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      match.league.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (match.state == MatchState.live)
                      const Icon(
                        Icons.circle,
                        size: 8,
                        color: Colors.redAccent,
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        match.isExample ? '예시 · 실제 경기 아님' : match.state.label,
                        style: TextStyle(color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (match.league == League.f1) ...[
                  Text(
                    match.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (final row in match.standings.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            row.position,
                            style: scoreStyle.copyWith(fontSize: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(row.driver)),
                          Text(
                            row.time,
                            style: scoreStyle.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ] else ...[
                  for (final p in match.participants)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          if (p.logo != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Image.network(
                                p.logo!,
                                width: 30,
                                height: 30,
                                errorBuilder: (_, error, stack) =>
                                    const Icon(Icons.shield_outlined, size: 30),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 17,
                                color:
                                    match.state == MatchState.finalScore &&
                                        !p.winner
                                    ? TacticalColors.muted
                                    : Colors.white,
                                fontWeight: p.winner
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            p.score ?? '—',
                            style: scoreStyle.copyWith(
                              color:
                                  match.state == MatchState.finalScore &&
                                      !p.winner
                                  ? TacticalColors.muted
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Text(
                  match.status,
                  style: scoreStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: TacticalColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
