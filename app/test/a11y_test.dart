// TEST-A11Y-001 (labelled tap targets, Android tap target size), TEST-A11Y-004 (contrast) and
// TEST-A11Y-003 (text at 200% without overflow) on the screens that run without the native core;
// and NFR-L10N-003: the same screens laid out right to left.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/presets.dart';
import 'package:refocal/bootstrap/settings.dart';
import 'package:refocal/bootstrap/engine.dart';
import 'package:refocal/bootstrap/queue.dart';
import 'package:refocal/bootstrap/storage.dart';
import 'package:refocal/features/onboarding/onboarding_page.dart';
import 'package:refocal/features/queue/batch_sheet.dart';
import 'package:refocal/features/queue/queue_page.dart';
import 'package:refocal/features/settings/settings_page.dart';
import 'package:refocal/features/storage/storage_page.dart';
import 'package:refocal/l10n/app_localizations.dart';
import 'package:refocal/ui_kit/compare_slider.dart';
import 'package:refocal_core/refocal_core.dart';
import 'package:refocal_platform/refocal_platform.dart';

final _png1x1 = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

QueueItem _item(String id, QueueState state, {String? error}) => QueueItem(
  id: id,
  jobId: 'job-$id',
  inputPath: 'inbox/$id.jpg',
  recipe: Recipe(scale: 2, fast2: true, srModel: 'sr.general-x4v3'),
  state: state,
  position: 0,
  progress: 0.4,
  errorCode: error,
  updatedAt: DateTime(2026),
);

/// Stored settings without a database (drift does not complete under the widget tester's
/// fake async; the screens are under test here, not the store).
class _FixedSettings extends SettingsController {
  @override
  Future<Settings> build() async => const Settings(onboardingDone: true);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('refocal-a11y'));
  tearDown(() => dir.deleteSync(recursive: true));

  final screens = <String, Widget Function()>{
    'onboarding': () => const OnboardingPage(),
    'settings': () => const SettingsPage(),
    'storage': () => const StoragePage(),
    'queue': () => const QueuePage(),
    'compare slider': () => Scaffold(
      body: CompareSlider(
        before: MemoryImage(_png1x1),
        after: MemoryImage(Uint8List.fromList(_png1x1)),
        aspectRatio: 4 / 3,
        resultLabel: 'Result, 4×3, enhanced by AI',
      ),
    ),
    'batch sheet': () => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(onPressed: () => showBatchSheet(context, 5), child: const Text('open')),
        ),
      ),
    ),
  };

  Future<void> pump(
    WidgetTester tester,
    Widget screen,
    double scale, {
    TextDirection? direction,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final dirs = AppDirs(support: dir.path, backedUp: dir.path, cache: dir.path);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDirsProvider.overrideWith((_) => dirs),
          settingsProvider.overrideWith(_FixedSettings.new),
          presetsProvider.overrideWith(
            (_) => Stream.value([
              Preset(
                id: 'p',
                name: 'Mine',
                recipe: Recipe(scale: 4, srModel: 'sr.general-x4v3', strength: 0.7),
              ),
            ]),
          ),
          queueItemsProvider.overrideWith(
            (_) => Stream.value([
              _item('a', QueueState.running),
              _item('b', QueueState.queued),
              _item('c', QueueState.failed, error: 'oom'),
              _item('d', QueueState.saved),
            ]),
          ),
          queueStatusProvider.overrideWith(
            (_) => Stream.value(const QueueStatus(running: true, currentId: 'a', progress: 0.4)),
          ),
          storageUsageProvider.overrideWith(
            (_) => StorageUsage({for (final c in StorageCategory.values) c: 1234567}),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: direction == null
                ? child!
                : Directionality(textDirection: direction, child: child!),
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.text('open').evaluate().isNotEmpty) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }
  }

  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name: labelled targets, 48 dp, contrast', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, build(), 1);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('$name: text at 200% does not overflow (A11Y-GEN-004)', (tester) async {
      await pump(tester, build(), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: right to left, no overflow (NFR-L10N-003)', (tester) async {
      await pump(tester, build(), 1, direction: TextDirection.rtl);
      expect(tester.takeException(), isNull);
      await pump(tester, build(), 2, direction: TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('right to left: "Skip" sits at the start edge', (tester) async {
    for (final direction in TextDirection.values) {
      await pump(tester, const OnboardingPage(), 1, direction: direction);
      final skip = tester.getCenter(find.byType(TextButton).first).dx;
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(skip > width / 2, direction == TextDirection.ltr, reason: '$direction');
    }
  });
}
