import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

// Schema of AppSupport/db.sqlite (ADR-0009, 07 §3). The tables of 07 §3 arrive with their
// features, each through a migration (PRIV-DATA-001): queue_jobs with the queue, model_packs and
// consents with the model manager, benchmark_cache with the tiers. Paths are relative to
// AppSupport (iOS moves the app container on updates); times are Unix milliseconds.
//
// Changing a table: bump [RefocalDatabase.schemaVersion], run `dart run drift_dev
// make-migrations` in packages/refocal_core, write the step and fill the generated test data.

/// Key-value settings (FR-SET-*); keys and value formats belong to the app.
@DataClassName('SettingRow')
class SettingEntries extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// An input photo: its inbox copy (ADR-0010), which may already be gone, and its size. The
/// SHA-256 deduplication and "keep for reprocessing" of 07 §3 come with FR-IMP-004 dedup.
@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get inboxPath => text().unique()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recipe JSON (`Recipe`); shared by history entries (and queue jobs later).
@DataClassName('RecipeRow')
class Recipes extends Table {
  TextColumn get id => text()();
  IntColumn get schema => integer()();
  TextColumn get json => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One saved or exported result (FR-HIST-001): recipe, preview <= 512 px, the result's URI.
@DataClassName('HistoryRow')
@TableIndex(name: 'history_created_at', columns: {#createdAt})
class History extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get recipeId => text().references(Recipes, #id)();

  /// Job directory name under AppSupport/jobs (deleted with the entry, FR-HIST-004).
  TextColumn get jobId => text()();
  TextColumn get resultUri => text()();
  TextColumn get previewPath => text()();
  IntColumn get width => integer()();
  IntColumn get height => integer()();

  /// JSON list of the model ids that produced the result.
  TextColumn get modelIds => text()();
  TextColumn get backend => text()();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// User presets (FR-PRE-002); the built-in ones (FR-PRE-001) live in the app with the models
/// they need.
@DataClassName('PresetRow')
class Presets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get recipeJson => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [SettingEntries, Assets, Recipes, History, Presets])
class RefocalDatabase extends _$RefocalDatabase {
  RefocalDatabase(super.e);

  /// The database file, opened on a background isolate.
  RefocalDatabase.open(File file) : super(NativeDatabase.createInBackground(file));

  /// For tests.
  RefocalDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // An older app opening a newer database (the user installed an older APK): its tables
      // cannot be interpreted; failing keeps the data for the newer version.
      if (from > to) throw StateError('database schema $from is newer than this app ($to)');
      throw StateError('no migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

final _random = Random.secure();

/// A random 128-bit id (hex) for TEXT primary keys.
String newId() =>
    List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
