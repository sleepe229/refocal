import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'database.steps.dart';
import 'prefs_database.dart';
import 'tables.dart';

part 'database.g.dart';

// AppSupport/db.sqlite (ADR-0009, 07 §3): assets, recipes, history, the queue, model packs,
// license consents, the manifest state. The tables of 07 §3 arrive with their features, each
// through a migration (PRIV-DATA-001): benchmark_cache with the tiers.
//
// Changing a table: bump [RefocalDatabase.schemaVersion], run `dart run drift_dev
// make-migrations` in packages/refocal_core, write the step and fill the generated test data.

/// Receives the settings and presets of schema 1 when db.sqlite migrates to 2 (they moved to
/// prefs.sqlite, PRIV-DATA-005). Must have stored them when it returns: the tables are dropped
/// next.
typedef MovePrefs = Future<void> Function(LegacyPrefs prefs);

@DriftDatabase(tables: [Assets, Recipes, History, QueueJobs, ModelPacks, Consents, ManifestState])
class RefocalDatabase extends _$RefocalDatabase {
  /// [movePrefs] is needed only to migrate a schema-1 file that holds settings or presets.
  RefocalDatabase(super.e, {this._movePrefs});

  /// The database file, opened on a background isolate.
  RefocalDatabase.open(File file, {MovePrefs? movePrefs})
    : this(NativeDatabase.createInBackground(file), movePrefs: movePrefs);

  /// For tests.
  RefocalDatabase.memory() : this(NativeDatabase.memory());

  final MovePrefs? _movePrefs;

  late final _steps = stepByStep(
    // Settings and presets move to prefs.sqlite (PRIV-DATA-005); assets get a nullable size (a
    // queued photo is not read yet); the queue (FR-BATCH-001..008).
    from1To2: (m, schema) async {
      final legacy = LegacyPrefs(
        settings: {
          for (final r in await customSelect('SELECT key, value FROM settings').get())
            r.read<String>('key'): r.read<String>('value'),
        },
        presets: [
          for (final r in await customSelect(
            'SELECT id, name, recipe_json, created_at FROM presets',
          ).get())
            PresetRow(
              id: r.read('id'),
              name: r.read('name'),
              recipeJson: r.read('recipe_json'),
              createdAt: r.read('created_at'),
            ),
        ],
      );
      if (!legacy.isEmpty) {
        final move = _movePrefs;
        if (move == null) throw StateError('schema 1 holds settings or presets: no movePrefs');
        await move(legacy);
      }
      await m.deleteTable('settings');
      await m.deleteTable('presets');
      await m.alterTable(TableMigration(schema.assets));
      await m.createTable(schema.queueJobs);
      await m.createIndex(schema.queueJobsPosition);
    },
    // The model manager (ADR-0011): installed packs, license consents, the manifest state.
    from2To3: (m, schema) async {
      await m.createTable(schema.modelPacks);
      await m.createTable(schema.consents);
      await m.createTable(schema.manifestState);
    },
  );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // An older app opening a newer database (the user installed an older APK): its tables
      // cannot be interpreted; failing keeps the data for the newer version.
      if (from > to) throw StateError('database schema $from is newer than this app ($to)');
      // Table rebuilds (alterTable) need foreign keys off, which cannot change inside a
      // transaction; beforeOpen turns them on again.
      await customStatement('PRAGMA foreign_keys = OFF');
      await transaction(() async {
        await _steps(m, from, to);
        final broken = await customSelect('PRAGMA foreign_key_check').get();
        if (broken.isNotEmpty) throw StateError('migration $from -> $to broke foreign keys');
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Deletes recipes and assets no history entry or queue job refers to; returns the inbox
  /// paths of those assets (the caller deletes the files). Call inside a transaction.
  Future<Set<String>> dropUnreferenced() async {
    Expression<bool> unusedAsset($AssetsTable a) =>
        a.id.isNotInQuery(selectOnly(history)..addColumns([history.assetId])) &
        a.id.isNotInQuery(selectOnly(queueJobs)..addColumns([queueJobs.assetId]));
    Expression<bool> unusedRecipe($RecipesTable r) =>
        r.id.isNotInQuery(selectOnly(history)..addColumns([history.recipeId])) &
        r.id.isNotInQuery(selectOnly(queueJobs)..addColumns([queueJobs.recipeId]));
    final orphans = await (select(assets)..where(unusedAsset)).get();
    await (delete(assets)..where(unusedAsset)).go();
    await (delete(recipes)..where(unusedRecipe)).go();
    return {for (final o in orphans) o.inboxPath};
  }
}

final _random = Random.secure();

/// A random 128-bit id (hex) for TEXT primary keys.
String newId() =>
    List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
