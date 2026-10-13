import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap/processing.dart';
import 'features/about/about_page.dart';
import 'features/editor/editor_page.dart';
import 'features/home/home_page.dart';
import 'features/settings/settings_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // NFR-MEM-006: bound the decoded image cache (T1 value; tiers come with the benchmark, 0.2).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
  registerNativeLicenses();
  ProcessingActions.install();
  runApp(const ProviderScope(child: RefocalApp()));
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/editor',
      builder: (_, s) => EditorPage(args: s.extra! as EditorArgs),
    ),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
  ],
);

class RefocalApp extends StatelessWidget {
  const RefocalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Refocal',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
    routerConfig: _router,
  );
}
