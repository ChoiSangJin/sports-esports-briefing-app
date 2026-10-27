import 'package:flutter/material.dart';
import '../../../theme/tactical_dark_theme.dart';

class CompactTable extends StatelessWidget {
  const CompactTable({super.key, required this.headers, required this.rows});
  final List<String> headers;
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) => Table(
    defaultColumnWidth: const FlexColumnWidth(),
    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
    border: const TableBorder(
      horizontalInside: BorderSide(color: TacticalColors.border),
    ),
    children: [
      for (var row = 0; row <= rows.length; row++)
        TableRow(
          decoration: row == 0
              ? const BoxDecoration(color: TacticalColors.card)
              : null,
          children: [
            for (final value in row == 0 ? headers : rows[row - 1])
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Text(
                  value,
                  softWrap: true,
                  style: scoreStyle.copyWith(
                    fontSize: row == 0 ? 13 : 14,
                    fontWeight: row == 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
    ],
  );
}
