import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/unified_match_model.dart';
import '../../services/ai_summary_service.dart';
import '../../services/providers.dart';

Future<void> showApiKeySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        child: ApiKeySheet(),
      ),
    );

class ApiKeySheet extends ConsumerStatefulWidget {
  const ApiKeySheet({super.key});
  @override
  ConsumerState<ApiKeySheet> createState() => _ApiKeySheetState();
}

class _ApiKeySheetState extends ConsumerState<ApiKeySheet> {
  final _controller = TextEditingController();
  final _modelController = TextEditingController();
  bool _obscure = true, _busy = false;
  String? _message;
  late List<AiModel> _models;
  @override
  void initState() {
    super.initState();
    _modelController.text = ref.read(aiProvider).model;
    _models = ref.read(aiProvider).availableModels;
  }

  @override
  void dispose() {
    _controller.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final stored = _controller.text.trim().isEmpty
          ? await ref.read(keyStorageProvider).read()
          : null;
      await ref
          .read(aiProvider)
          .validateAndSave(
            stored ?? _controller.text,
            _modelController.text.trim().replaceFirst(RegExp(r'^models/'), ''),
          );
      ref.invalidate(keyPresentProvider);
      _controller.clear();
      if (mounted) setState(() => _message = '연결 확인 및 암호화 저장 완료');
    } on AiFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) setState(() => _message = '기기 보안 저장소를 사용할 수 없습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final key = _controller.text.trim().isNotEmpty
          ? _controller.text.trim()
          : await ref.read(keyStorageProvider).read() ?? '';
      final models = await ref.read(aiProvider).discoverModels(key);
      if (!mounted) return;
      setState(() {
        _models = models;
        if (!models.any((m) => m.id == _modelController.text.trim())) {
          _modelController.clear();
        }
        _message = '${models.length}개 모델을 조회했습니다. 모델을 선택하고 연결 테스트 후 저장하세요.';
      });
    } on AiFailure catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = '모델 목록을 불러오지 못했습니다. 모델 ID를 직접 입력할 수 있습니다.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(keyStorageProvider).delete();
      ref.invalidate(keyPresentProvider);
      _controller.clear();
      if (mounted) setState(() => _message = '저장된 키를 삭제했습니다.');
    } catch (_) {
      if (mounted) setState(() => _message = '키를 삭제하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openStudio() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://aistudio.google.com/app/apikey'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(
          () => _message = '브라우저에서 aistudio.google.com/app/apikey를 열어 주세요.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = '외부 브라우저를 열 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final present = ref.watch(keyPresentProvider).valueOrNull ?? false;
    final favorites = ref.watch(favoritesProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'API Key & 설정',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              '키는 Android 보안 저장소에 보관됩니다. 연결 테스트와 요약은 Google로 전송되며 계정의 할당량 또는 비용이 적용될 수 있습니다.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: _obscure,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: present
                    ? '새 Gemini API 키 (비우면 기존 키 사용)'
                    : 'Gemini API 키',
                suffixIcon: IconButton(
                  tooltip: _obscure ? '키 표시' : '키 숨기기',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openStudio,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Google AI Studio에서 API 키 발급받기'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Google 모델 목록을 조회합니다. 실제 접근 권한과 할당량은 연결 테스트에서 확인합니다. 모델별 요금은 다를 수 있습니다.',
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _loadModels,
              icon: const Icon(Icons.refresh),
              label: const Text('사용 가능 모델 불러오기'),
            ),
            if (_models.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  '${_models.map((m) => m.id).join(',')}:${_modelController.text}',
                ),
                isExpanded: true,
                initialValue: _models.any((m) => m.id == _modelController.text)
                    ? _modelController.text
                    : null,
                decoration: const InputDecoration(labelText: '조회한 텍스트 생성 모델'),
                items: _models
                    .map(
                      (m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          '${m.label} · ${m.id}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _modelController.text = value!),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '모델 ID · 직접 입력 가능',
                helperText: '목록 조회가 어려우면 AI Studio의 모델 ID를 입력하세요.',
                helperMaxLines: 2,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '연결 확인 중…' : '연결 테스트 및 암호화 저장'),
            ),
            if (present)
              TextButton(
                onPressed: _busy ? null : _delete,
                child: const Text('저장된 API 키 삭제'),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(_message!)),
              ),
            const Divider(height: 32),
            const Text('즐겨찾는 리그 · 홈에서 먼저 표시'),
            Wrap(
              spacing: 8,
              children: [
                for (final league in League.values)
                  FilterChip(
                    label: Text(league.label),
                    selected: favorites.contains(league),
                    onSelected: (_) =>
                        ref.read(favoritesProvider.notifier).toggle(league),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
