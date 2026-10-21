import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal/bootstrap/models.dart';
import 'package:refocal/features/editor/editor_page.dart';
import 'package:refocal/features/models/download_banner.dart';
import 'package:refocal/l10n/app_localizations.dart';
import 'package:refocal_core/refocal_core.dart';

/// Downloads set by the test.
class _Models extends ModelsController {
  @override
  Future<ModelsState> build() async => const ModelsState();

  void downloads(Map<String, PackProgress> d) => state = AsyncData(ModelsState(downloads: d));
}

void main() {
  late GoRouter router;
  late Set<String> installed;
  late ProviderContainer container;

  InstalledPack pack(String id) => InstalledPack(
    id: id,
    version: '1.0.0',
    path: 'models/$id',
    size: 1,
    installedAt: DateTime(2026),
  );

  Future<_Models> pump(WidgetTester tester) async {
    installed = {};
    router = GoRouter(
      routes: [
        for (final p in ['/', '/models', '/editor', '/history'])
          GoRoute(
            path: p,
            builder: (_, s) => Scaffold(
              body: Text('page $p ${s.extra is EditorArgs ? (s.extra! as EditorArgs).input : ''}'),
            ),
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          modelsProvider.overrideWith(_Models.new),
          installedPacksProvider.overrideWith(
            (_) => Stream.value([for (final id in installed) pack(id)]),
          ),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, child) => DownloadBanner(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(DownloadBanner)));
    container.read(modelsProvider);
    await tester.pump();
    return container.read(modelsProvider.notifier) as _Models;
  }

  Future<void> go(WidgetTester tester, String to) async {
    router.go(to);
    await tester.pumpAndSettle();
  }

  testWidgets('progress, then "ready" for a few seconds once installed, then nothing', (
    tester,
  ) async {
    final m = await pump(tester);
    m.downloads({'face': const PackProgress(25, 100)});
    await tester.pump();
    expect(find.text('Downloading a model… 25%'), findsOneWidget);
    installed = {'face'};
    m.downloads({});
    await tester.pumpAndSettle();
    expect(find.text('Model ready'), findsOneWidget);
    await tester.pump(DownloadBanner.doneFor);
    await tester.pumpAndSettle();
    expect(find.text('Model ready'), findsNothing);
  });

  testWidgets('a failed or cancelled download leaves quietly', (tester) async {
    final m = await pump(tester);
    m.downloads({'face': const PackProgress(25, 100)});
    await tester.pump();
    m.downloads({});
    await tester.pumpAndSettle();
    expect(find.textContaining('model'), findsNothing);
    expect(find.text('Model ready'), findsNothing);
  });

  testWidgets('closed, it stays away until another model starts', (tester) async {
    final m = await pump(tester);
    m.downloads({'face': const PackProgress(25, 100)});
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.textContaining('Downloading'), findsNothing);
    m.downloads({'face': const PackProgress(50, 100)});
    await tester.pump();
    expect(find.textContaining('Downloading'), findsNothing);
    m.downloads({'face': const PackProgress(50, 100), 'sr': const PackProgress(0, 100)});
    await tester.pump();
    expect(find.text('Downloading a model… 25%'), findsOneWidget);
  });

  testWidgets('not over the screens that show downloads themselves', (tester) async {
    final m = await pump(tester);
    m.downloads({'face': const PackProgress(25, 100)});
    await go(tester, '/models');
    expect(find.textContaining('Downloading'), findsNothing);
    await go(tester, '/history');
    expect(find.textContaining('Downloading'), findsOneWidget);
  });

  testWidgets('the pages get its height: it covers nothing', (tester) async {
    final m = await pump(tester);
    final before = MediaQuery.paddingOf(tester.element(find.textContaining('page /')));
    m.downloads({'face': const PackProgress(25, 100)});
    await tester.pump();
    final during = MediaQuery.paddingOf(tester.element(find.textContaining('page /')));
    expect(during.bottom, greaterThan(before.bottom));
  });

  testWidgets('a tap goes back to the photo that asked for the model', (tester) async {
    final m = await pump(tester);
    container.read(downloadOriginProvider.notifier).set(['face'], const EditorArgs('/p/a.jpg'));
    m.downloads({'face': const PackProgress(25, 100)});
    await tester.pump();
    await tester.tap(find.text('Back to photo'));
    await tester.pumpAndSettle();
    expect(find.text('page /editor /p/a.jpg'), findsOneWidget);
    expect(container.read(downloadOriginProvider), isNull);
  });

  testWidgets('without a photo, a tap opens the Models screen', (tester) async {
    final m = await pump(tester);
    m.downloads({'face': const PackProgress(25, 100)});
    await tester.pump();
    await tester.tap(find.textContaining('Downloading'));
    await tester.pumpAndSettle();
    expect(find.textContaining('page /models'), findsOneWidget);
  });
}
