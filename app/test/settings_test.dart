import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/database.dart';
import 'package:refocal/bootstrap/engine.dart';
import 'package:refocal/bootstrap/settings.dart';
import 'package:refocal_core/refocal_core.dart';
import 'package:refocal_platform/refocal_platform.dart';

void main() {
  test('defaults are private, JPEG 92, history on', () {
    const s = Settings();
    expect(s.keepGps, isFalse);
    expect(s.aiMarker, isTrue);
    expect(s.format, ExportFormat.jpeg);
    expect(s.quality, 92);
    expect(s.languageCode, isNull);
    expect(s.historyEnabled, isTrue);
    expect(Settings.fromStore(const {}).toStore(), s.toStore());
  });

  test('store round trip; bad values fall back to the defaults', () {
    final s = const Settings().copyWith(
      keepGps: true,
      format: ExportFormat.webpLossless,
      quality: 75,
      languageCode: () => 'ru',
      onboardingDone: true,
      historyEnabled: false,
      faceOfferDismissed: true,
      packUpdateCheck: true,
      packUpdateCheckedAt: () => DateTime.fromMillisecondsSinceEpoch(1760000000000),
    );
    expect(
      Settings.fromStore(s.toStore().map((k, v) => MapEntry(k, v ?? ''))).faceOfferDismissed,
      isTrue,
    );
    final stored = {
      for (final e in s.toStore().entries)
        if (e.value != null) e.key: e.value!,
    };
    expect(Settings.fromStore(stored).toStore(), s.toStore());
    final bad = Settings.fromStore(const {
      'keep_gps': 'yes',
      'format': 'gif',
      'quality': '5',
      'language': 'xx',
      'history_enabled': '1',
    });
    expect(bad.keepGps, isFalse);
    expect(bad.format, ExportFormat.jpeg);
    expect(bad.quality, ExportFormat.minQuality);
    expect(bad.languageCode, isNull);
    expect(bad.historyEnabled, isTrue);
    expect(Settings.fromStore(const {'quality': 'x'}).quality, 92);
  });

  test('0.0.2 files skip the introduction; bad values fall back', () {
    final v1 = Settings.fromLegacyJson({'version': 1, 'keep_gps': false, 'ai_marker': true});
    expect(v1.onboardingDone, isTrue);
    expect(v1.format, ExportFormat.jpeg);
    final bad = Settings.fromLegacyJson({
      'version': 2,
      'format': 'gif',
      'quality': 5,
      'language': 'xx',
    });
    expect(bad.format, ExportFormat.jpeg);
    expect(bad.quality, ExportFormat.minQuality);
    expect(bad.languageCode, isNull);
    expect(bad.onboardingDone, isFalse);
  });

  group('settings.json import', () {
    late Directory dir;
    late PrefsDatabase db;
    late SettingsStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('refocal-settings');
      db = PrefsDatabase.memory();
      store = SettingsStore(db);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    File legacy(Object content) =>
        File('${dir.path}/settings.json')..writeAsStringSync(jsonEncode(content));

    test('imports a 0.0.3 file once and deletes it', () async {
      final f = legacy({
        'version': 2,
        'keep_gps': true,
        'ai_marker': false,
        'format': 'png',
        'quality': 80,
        'language': 'ru',
        'onboarding_done': true,
      });
      File('${f.path}.part').writeAsStringSync('{');
      await importLegacySettings(store, dir.path);
      expect(f.existsSync(), isFalse);
      expect(File('${f.path}.part').existsSync(), isFalse);
      final s = Settings.fromStore(await store.read());
      expect((s.keepGps, s.aiMarker, s.format, s.quality), (true, false, ExportFormat.png, 80));
      expect((s.languageCode, s.onboardingDone, s.historyEnabled), ('ru', true, true));
    });

    test('a 0.0.2 file means the introduction was seen', () async {
      legacy({'version': 1, 'keep_gps': false, 'ai_marker': true});
      await importLegacySettings(store, dir.path);
      expect(Settings.fromStore(await store.read()).onboardingDone, isTrue);
    });

    test('settings already in the database win over a leftover file', () async {
      await store.write({'quality': '70'});
      final f = legacy({'version': 2, 'quality': 99});
      await importLegacySettings(store, dir.path);
      expect(await store.read(), {'quality': '70'});
      expect(f.existsSync(), isFalse);
    });

    test('a file that is not JSON holds nothing and is deleted', () async {
      final f = File('${dir.path}/settings.json')..writeAsStringSync('{"vers');
      await importLegacySettings(store, dir.path);
      expect(await store.read(), isEmpty);
      expect(f.existsSync(), isFalse);
      // Nothing to import is not an error.
      await importLegacySettings(store, dir.path);
    });
  });

  group('SettingsController', () {
    late Directory dir;
    late PrefsDatabase db;

    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [
          appDirsProvider.overrideWith(
            (_) => AppDirs(support: dir.path, backedUp: dir.path, cache: dir.path),
          ),
          prefsDatabaseProvider.overrideWith((_) => db),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('refocal-settings');
      db = PrefsDatabase.memory();
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('changes persist and concurrent changes are not lost', () async {
      final c = container();
      final ctl = c.read(settingsProvider.notifier);
      await c.read(settingsProvider.future);
      // Issued together: each one starts from the result of the previous one.
      await Future.wait([
        ctl.change((s) => s.copyWith(keepGps: true)),
        ctl.change((s) => s.copyWith(format: ExportFormat.webp)),
        ctl.change((s) => s.copyWith(quality: 70)),
      ]);
      final s = c.read(settingsProvider).value!;
      expect((s.keepGps, s.format, s.quality), (true, ExportFormat.webp, 70));
      final stored = Settings.fromStore(await SettingsStore(db).read());
      expect(stored.toStore(), s.toStore());
      // A fresh container (the next start) reads the same.
      final again = await container().read(settingsProvider.future);
      expect(again.toStore(), s.toStore());
    });

    test('a failed write leaves the state as stored and the queue going', () async {
      final c = container();
      final ctl = c.read(settingsProvider.notifier);
      await c.read(settingsProvider.future);
      // The settings table is gone: the write fails.
      await db.customStatement('DROP TABLE settings');
      await expectLater(ctl.change((s) => s.copyWith(keepGps: true)), throwsA(anything));
      expect(c.read(settingsProvider).value!.keepGps, isFalse);
      await db.customStatement(
        'CREATE TABLE settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
      );
      await ctl.change((s) => s.copyWith(aiMarker: false));
      expect(c.read(settingsProvider).value!.aiMarker, isFalse);
      expect(c.read(settingsProvider).value!.keepGps, isFalse);
    });

    test('imports settings.json on first read', () async {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({'version': 1}));
      final s = await container().read(settingsProvider.future);
      expect(s.onboardingDone, isTrue);
      expect(File('${dir.path}/settings.json').existsSync(), isFalse);
    });
  });
}
