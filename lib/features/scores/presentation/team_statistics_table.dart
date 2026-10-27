import 'package:flutter/material.dart';
import '../../../models/match_detail.dart';
import '../../../theme/tactical_dark_theme.dart';

class TeamStatisticsTable extends StatelessWidget {
  const TeamStatisticsTable({super.key, required this.detail});
  final MatchDetail detail;
  static const labels = {
    'FG': '필드골',
    'Field Goal %': '야투 성공률',
    '3PT': '3점슛',
    'Three Point %': '3점슛 성공률',
    'FT': '자유투',
    'Free Throw %': '자유투 성공률',
    'Rebounds': '리바운드',
    'Offensive Rebounds': '공격 리바운드',
    'Defensive Rebounds': '수비 리바운드',
    'Assists': '어시스트',
    'Steals': '스틸',
    'Blocks': '블록',
    'Turnovers': '턴오버',
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '팀 기록 비교',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const Text(
        '좌우로 밀어 모든 팀 기록을 확인하세요.',
        style: TextStyle(color: TacticalColors.secondary, fontSize: 12),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 72,
          columnSpacing: 20,
          horizontalMargin: 12,
          columns: [
            const DataColumn(label: Text('항목')),
            for (final team in detail.teams)
              DataColumn(
                label: SizedBox(
                  width: 140,
                  child: Text(
                    team.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
          rows: [
            for (final key in detail.statKeys)
              DataRow(
                cells: [
                  DataCell(
                    Text(labels[detail.label(key)] ?? detail.label(key)),
                  ),
                  for (final team in detail.teams)
                    DataCell(
                      Text(
                        team.values[key] ?? '—',
                        style: scoreStyle.copyWith(fontSize: 15),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    ],
  );
}
