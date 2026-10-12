import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/editor/editor_page.dart';
import 'features/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // NFR-MEM-006: bound the decoded image cache (T1 value; tiers come with the benchmark, 0.2).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
  runApp(const ProviderScope(child: RefocalApp()));
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/editor',
      builder: (_, s) => EditorPage(input: s.extra! as String),
    ),
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
