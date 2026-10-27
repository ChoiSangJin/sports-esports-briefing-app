import 'package:flutter/material.dart';
import '../../../models/match_detail.dart';
import 'compact_table.dart';

class RecordSections extends StatelessWidget {
  const RecordSections({super.key, required this.sections});
  final List<RecordSection> sections;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final section in sections)
        ExpansionTile(
          title: Text(section.title),
          children: section.headers.length <= 4
              ? [CompactTable(headers: section.headers, rows: section.rows)]
              : [
                  for (final row in section.rows)
                    ExpansionTile(
                      title: Text(row.first),
                      children: [
                        CompactTable(
                          headers: const ['항목', '기록'],
                          rows: [
                            for (var i = 1; i < section.headers.length; i++)
                              [section.headers[i], row[i]],
                          ],
                        ),
                      ],
                    ),
                ],
        ),
    ],
  );
}
