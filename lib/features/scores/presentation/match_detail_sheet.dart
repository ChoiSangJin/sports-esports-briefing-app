import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/report_text.dart';
import '../../../models/unified_match_model.dart';
import '../../../services/ai_summary_service.dart';
import '../../../services/providers.dart';
import '../../../theme/tactical_dark_theme.dart';
import '../../settings/api_key_sheet.dart';
import 'match_card.dart';
import 'source_link.dart';

Future<void> showMatchDetail(BuildContext context, UnifiedMatchModel match) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: MatchDetailSheet(match: match),
      ),
    );

class MatchDetailSheet extends ConsumerStatefulWidget {
  const MatchDetailSheet({super.key, required this.match});
  final UnifiedMatchModel match;
  @override
  ConsumerState<MatchDetailSheet> createState() => _MatchDetailSheetState();
}

class _MatchDetailSheetState extends ConsumerState<MatchDetailSheet> {
  String _report = '';
  String? _summary, _error, _detailError;
  bool _loading = true, _busy = false;
  @override
  void initState() {
    super.initState();
    _summary = ref.read(aiProvider).cached(widget.match);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _detailError = null;
    });
    try {
      final report = await ref.read(repositoryProvider).detail(widget.match);
      if (mounted) {
        setState(() => _report = readableReport(report));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _detailError = '상세 리포트를 가져오지 못했습니다. 스코어만으로 요약할 수 있습니다.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _summarize({bool refresh = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await ref.read(keyStorageProvider).read();
      if (key == null ||
          key.isEmpty ||
          !AiModel.validId(ref.read(aiProvider).model)) {
        if (!mounted) return;
        setState(() => _busy = false);
        await showApiKeySheet(context);
        if (!mounted) return;
        final saved = await ref.read(keyStorageProvider).read();
        if (saved == null || saved.isEmpty) return;
        if (!mounted) return;
        setState(() => _busy = true);
      }
      final result = await ref
          .read(aiProvider)
          .summarize(widget.match, _report, refresh: refresh);
      if (mounted) setState(() => _summary = result);
    } on AiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '요약 또는 기기 저장소에 접근할 수 없습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
    children: [
      Text(widget.match.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      MatchCard(match: widget.match),
      if (widget.match.sourceUrl != null)
        MatchSourceLink(
          label: '${widget.match.source}에서 확인',
          url: widget.match.sourceUrl!,
        ),
      for (final line in widget.match.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line, style: scoreStyle.copyWith(fontSize: 14)),
        ),
      if (widget.match.standings.isNotEmpty)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('순위')),
              DataColumn(label: Text('드라이버 / 팀')),
              DataColumn(label: Text('시간 / 상태')),
              DataColumn(label: Text('포인트')),
            ],
            rows: [
              for (final row in widget.match.standings)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        row.position,
                        style: scoreStyle.copyWith(fontSize: 14),
                      ),
                    ),
                    DataCell(Text('${row.driver}\n${row.team}')),
                    DataCell(
                      Text(row.time, style: scoreStyle.copyWith(fontSize: 14)),
                    ),
                    DataCell(
                      Text(
                        row.points,
                        style: scoreStyle.copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0x338B5CF6), Color(0x333B82F6)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TacticalColors.violet),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '✦ AI 한국어 요약 & 분석',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            if (_summary != null) ...[
              SelectableText(_summary!),
              const SizedBox(height: 8),
              const Text(
                '기기에 저장된 AI 요약 · 사실 확인이 필요합니다.',
                style: TextStyle(fontSize: 11, color: TacticalColors.secondary),
              ),
            ],
            if (widget.match.isExample)
              const Text('실제 경기 데이터가 아닌 예시입니다. AI 요약은 비활성화됩니다.')
            else
              FilledButton.icon(
                onPressed: _busy || _loading
                    ? null
                    : () => _summarize(refresh: _summary != null),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _busy
                      ? '요약 생성 중…'
                      : _summary != null
                      ? '다시 요약 (API 호출)'
                      : 'Gemini AI로 한국어 3줄 요약 & 분석 보기',
                ),
              ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            const Text(
              '요청 시 경기 자료가 Google로 전송됩니다.',
              style: TextStyle(fontSize: 11, color: TacticalColors.secondary),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text('원문 리포트 & 기록', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (_loading)
        const LinearProgressIndicator()
      else if (_detailError != null) ...[
        Text(_detailError!),
        TextButton(onPressed: _load, child: const Text('리포트 다시 시도')),
      ] else
        SelectableText(
          _report.isEmpty ? '제공된 원문 리포트가 없습니다. 확인된 경기 기록만 표시합니다.' : _report,
        ),
    ],
  );
}
