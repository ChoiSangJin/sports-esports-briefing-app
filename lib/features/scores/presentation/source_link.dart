import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MatchSourceLink extends StatelessWidget {
  const MatchSourceLink({super.key, required this.label, required this.url});
  final String label, url;
  Future<void> _open(BuildContext context) async {
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Report a safe, actionable message below. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('브라우저를 열 수 없습니다. 연결을 확인해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(Icons.open_in_new, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    ),
  );
}
