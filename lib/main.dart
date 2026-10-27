import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/scores/presentation/dashboard_screen.dart';
import 'services/providers.dart';
import 'theme/tactical_dark_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final preferences = await SharedPreferences.getInstance();
    runApp(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(preferences)],
        child: const BriefingApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: tacticalDarkTheme(),
        home: const Scaffold(
          body: Center(child: Text('기기 저장소를 열 수 없습니다. 앱을 다시 시작해 주세요.')),
        ),
      ),
    );
  }
}

class BriefingApp extends StatelessWidget {
  const BriefingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '스포츠 한눈에',
    debugShowCheckedModeBanner: false,
    theme: tacticalDarkTheme(),
    home: const DashboardScreen(),
  );
}
