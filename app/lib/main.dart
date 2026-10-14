import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap/app_log.dart';
import 'bootstrap/processing.dart';
import 'bootstrap/settings.dart';
import 'features/about/about_page.dart';
import 'features/editor/editor_page.dart';
import 'features/home/home_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/report/report_page.dart';
import 'features/settings/settings_page.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // NFR-MEM-006: bound the decoded image cache (T1 value; tiers come with the benchmark, 0.2).
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
  registerNativeLicenses();
  AppLog.installErrorHandlers();
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
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
    GoRoute(path: '/report', builder: (_, _) => const ReportPage()),
  ],
);

class RefocalApp extends ConsumerWidget {
  const RefocalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final code = settings.value?.languageCode;
    // First run: the introduction once settings are read (FR-ONB-001).
    ref.listen(settingsProvider, (prev, next) {
      final s = next.value;
      if (prev?.value == null && s != null && !s.onboardingDone) _router.push('/onboarding');
    });
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      locale: code == null ? null : Locale(code),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: _router,
    );
  }
}
