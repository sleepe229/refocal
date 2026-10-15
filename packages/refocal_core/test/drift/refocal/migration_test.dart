// TEST-DB-001 / PRIV-DATA-001: every schema version migrates to every later one. The schema
// dumps (drift_schemas/refocal) and generated/ come from `dart run drift_dev make-migrations`;
// with a second version it also adds the step-by-step data template (see drift's docs).
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:refocal_core/src/db/database.dart';
import 'package:refocal_core/src/db/prefs_database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = RefocalDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('the current schema is the last dump (a change needs a new version)', () async {
    final current = RefocalDatabase(NativeDatabase.memory());
    addTearDown(current.close);
    expect(GeneratedHelper.versions.last, current.schemaVersion);
    final schema = await verifier.schemaAt(GeneratedHelper.versions.last);
    final db = RefocalDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
    await db.close();
  });

  test('a new database matches the last dump', () async {
    final db = RefocalDatabase(NativeDatabase.memory());
    await db.validateDatabaseSchema();
    await db.close();
  });

  test('a database of a newer app version is not opened', () async {
    final db = RefocalDatabase(
      NativeDatabase.memory(setup: (raw) => raw.userVersion = GeneratedHelper.versions.last + 1),
    );
    await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
    await db.close();
  });

  group('1 -> 2', () {
    Future<void> fillV1(QueryExecutor e) async {
      final old = v1.DatabaseAtV1(e);
      await old.batch((b) {
        b.insertAll(old.settings, [
          v1.SettingsCompanion.insert(key: 'quality', value: '90'),
          v1.SettingsCompanion.insert(key: 'onboarding_done', value: 'true'),
        ]);
        b.insert(
          old.presets,
          v1.PresetsCompanion.insert(id: 'p1', name: 'Mine', recipeJson: '{}', createdAt: 5),
        );
        b.insert(
          old.assets,
          v1.AssetsCompanion.insert(
            id: 'a1',
            inboxPath: 'inbox/a.jpg',
            width: 40,
            height: 30,
            createdAt: 1,
          ),
        );
        b.insert(
          old.recipes,
          v1.RecipesCompanion.insert(id: 'r1', schema: 1, json: '{}', createdAt: 1),
        );
        b.insert(
          old.history,
          v1.HistoryCompanion.insert(
            id: 'h1',
            assetId: 'a1',
            recipeId: 'r1',
            jobId: 'job-1',
            resultUri: 'content://x',
            previewPath: 'history/h1.jpg',
            width: 160,
            height: 120,
            modelIds: '["m"]',
            backend: 'cpu',
            createdAt: 2,
          ),
        );
      });
      await old.close();
    }

    test('settings and presets move to prefs.sqlite, the rest stays (PRIV-DATA-005)', () async {
      final schema = await verifier.schemaAt(1);
      await fillV1(schema.newConnection());
      LegacyPrefs? moved;
      final db = RefocalDatabase(schema.newConnection(), movePrefs: (p) async => moved = p);
      await verifier.migrateAndValidate(db, 2);
      await db.close();

      expect(moved!.settings, {'quality': '90', 'onboarding_done': 'true'});
      expect([for (final p in moved!.presets) (p.id, p.name, p.createdAt)], [('p1', 'Mine', 5)]);
      final now = v2.DatabaseAtV2(schema.newConnection());
      final a = await now.select(now.assets).getSingle();
      expect((a.id, a.inboxPath, a.width, a.height), ('a1', 'inbox/a.jpg', 40, 30));
      expect((await now.select(now.history).getSingle()).id, 'h1');
      expect(await now.select(now.queueJobs).get(), isEmpty);
      await now.close();
    });

    test('the moved rows land in prefs.sqlite, and a repeated move keeps newer values', () async {
      final prefs = PrefsDatabase.memory();
      addTearDown(prefs.close);
      await prefs
          .into(prefs.settingEntries)
          .insert(
            SettingEntriesCompanion.insert(
              key: 'quality',
              value: '70',
            ), // written after a first move
          );
      const legacy = LegacyPrefs(
        settings: {'quality': '90', 'format': 'png'},
        presets: [PresetRow(id: 'p1', name: 'Mine', recipeJson: '{}', createdAt: 5)],
      );
      await prefs.importLegacy(legacy);
      await prefs.importLegacy(legacy);
      final settings = {
        for (final r in await prefs.select(prefs.settingEntries).get()) r.key: r.value,
      };
      expect(settings, {'quality': '70', 'format': 'png'});
      expect((await prefs.select(prefs.presets).get()).map((p) => p.id), ['p1']);
    });

    test('without a place for the settings the migration fails and changes nothing', () async {
      final schema = await verifier.schemaAt(1);
      await fillV1(schema.newConnection());
      final db = RefocalDatabase(schema.newConnection());
      await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
      await db.close();
      final old = v1.DatabaseAtV1(schema.newConnection());
      expect(await old.select(old.settings).get(), hasLength(2));
      expect(
        await old.customSelect('PRAGMA user_version').getSingle().then((r) => r.data.values.first),
        1,
      );
      await old.close();
    });

    test('a move that fails leaves schema 1 as it was', () async {
      final schema = await verifier.schemaAt(1);
      await fillV1(schema.newConnection());
      final db = RefocalDatabase(
        schema.newConnection(),
        movePrefs: (_) async => throw StateError('prefs.sqlite not writable'),
      );
      await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
      await db.close();
      final old = v1.DatabaseAtV1(schema.newConnection());
      expect(await old.select(old.presets).get(), hasLength(1));
      await old.close();
    });
  });
}
