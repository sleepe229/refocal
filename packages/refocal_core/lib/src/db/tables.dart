import 'package:drift/drift.dart';

// Tables of the two databases (ADR-0009, 07 §3). Paths are relative to AppSupport (iOS moves
// the app container on updates); times are Unix milliseconds.
//
// prefs.sqlite (PrefsDatabase): settings and user presets. The one file the platform backup
// takes (PRIV-DATA-005): small, and nothing in it refers to photos.
// db.sqlite (RefocalDatabase): what refers to photos and files that are not backed up (assets,
// recipes, history, queue_jobs); in AppSupport, excluded from the backup like inbox/ and jobs/.

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

/// An input photo: its inbox copy (ADR-0010), which may already be gone, and its size once the
/// core has read it (null for a queued photo not processed yet). The SHA-256 deduplication and
/// "keep for reprocessing" of 07 §3 come with FR-IMP-004 dedup.
@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get inboxPath => text().unique()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Recipe JSON (`Recipe`); shared by history entries and queue jobs.
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

/// Where a queue job is (03 §6, FR-BATCH-*).
enum QueueState {
  /// Waiting for its turn.
  queued,

  /// The core works on it (at most one at a time). After a restart such a row is [paused]:
  /// the process that ran it is gone, its checkpoint stays (FR-BATCH-007).
  running,

  /// Stopped at a band boundary (pause, FGS time limit, restart); continues from the checkpoint.
  paused,

  /// Finished; the result waits in its job directory to be opened and saved.
  done,

  /// Finished and saved by the queue (FR-BATCH-006); the job directory is gone.
  saved,

  /// Failed or cancelled ([QueueJobs.errorCode]); the queue went on (FR-BATCH-008).
  failed,
}

/// The batch queue (FR-BATCH-001..008). The recipe's `output` set means: save the result in
/// that format when it is done (FR-BATCH-006); unset: keep it for the user.
@DataClassName('QueueJobRow')
@TableIndex(name: 'queue_jobs_position', columns: {#position})
class QueueJobs extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text().references(Assets, #id)();
  TextColumn get recipeId => text().references(Recipes, #id)();
  TextColumn get state => textEnum<QueueState>()();

  /// Processing order, ascending; gaps are allowed.
  IntColumn get position => integer()();

  /// Job directory name under AppSupport/jobs (exists once the job started).
  TextColumn get jobId => text().unique()();

  /// Committed bands / all bands.
  RealColumn get progress => real().withDefault(const Constant(0))();

  /// `EnhStatus` name of a failure, or "cancelled".
  TextColumn get errorCode => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// An installed model pack (ADR-0011, 07 §3): files under `AppSupport/models/<id>/`.
@DataClassName('ModelPackRow')
class ModelPacks extends Table {
  TextColumn get id => text()();
  TextColumn get version => text()();
  TextColumn get category => text()();

  /// Directory relative to AppSupport.
  TextColumn get path => text()();

  /// Bytes of the installed files.
  IntColumn get size => integer()();

  /// SHA-256 of the manifest entry's files, joined in manifest order (what was verified).
  TextColumn get sha256 => text()();
  TextColumn get licenseSpdx => text()();
  IntColumn get installedAt => integer()();

  /// The pack's localized titles from its manifest entry (JSON), shown for a pack the current
  /// manifest does not list (installed from a .rfpack, or withdrawn). Null before schema 5.
  TextColumn get title => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Acceptance of a pack's license (FR-MOD-*, ADR-0022): for that license text.
@DataClassName('ConsentRow')
class Consents extends Table {
  TextColumn get packId => text()();
  TextColumn get packVersion => text()();
  TextColumn get licenseSha256 => text()();
  IntColumn get acceptedAt => integer()();

  @override
  Set<Column> get primaryKey => {packId, licenseSha256};
}

/// The last verified manifest (one row): its serial guards against rollback (ADR-0011).
@DataClassName('ManifestStateRow')
class ManifestState extends Table {
  IntColumn get id => integer()();
  IntColumn get serial => integer()();
  IntColumn get fetchedAt => integer()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

/// Benchmark results (ADR-0017, 05 §6.2) by `app_ver|model_ver|driver_ver|gpu_device_id|
/// os_build|gate_version`; json is the core's enh_benchmark result.
@DataClassName('BenchmarkRow')
class BenchmarkCache extends Table {
  TextColumn get key => text()();
  TextColumn get json => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}
