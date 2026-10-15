import 'dart:convert';

import 'package:drift/drift.dart';

import '../recipe.dart';
import 'database.dart';

/// A saved or exported result (FR-HIST-001/002): what it was made from and how, not a copy of
/// the photo. Paths are relative to AppSupport.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.recipe,
    required this.inputPath,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
    required this.previewPath,
    required this.resultUri,
    required this.modelIds,
    required this.backend,
    required this.duration,
    required this.jobId,
  }) {
    if (recipe.output == null) throw ArgumentError('a history entry records how it was saved');
  }

  final String id;
  final DateTime createdAt;

  /// With [Recipe.output] set.
  final Recipe recipe;

  /// The inbox copy of the input (ADR-0010); usually deleted once the result is saved.
  final String inputPath;
  final int sourceWidth, sourceHeight;

  /// Result size.
  final int width, height;

  /// JPEG <= 512 px (PRIV-DATA-002).
  final String previewPath;

  /// Where the result went: a MediaStore or document URI.
  final String resultUri;
  final List<String> modelIds;
  final String backend;

  /// Processing time of the last run of the job (a resumed job counts from the resume).
  final Duration? duration;

  /// The job directory under AppSupport/jobs, gone once the editor closed (ADR-0010).
  final String jobId;
}

/// What a removal left without a reference in the database; the caller deletes the files.
class HistoryRemoval {
  const HistoryRemoval({this.previews = const [], this.jobIds = const {}, this.inputs = const {}});

  final List<String> previews;
  final Set<String> jobIds;

  /// Inbox copies of inputs no entry refers to any more.
  final Set<String> inputs;
}

/// History entries over `history`, `assets` and `recipes` (07 §3).
class HistoryRepository {
  HistoryRepository(this._db);

  final RefocalDatabase _db;

  Future<void> add(HistoryEntry e) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.assets,
    )..where((a) => a.inboxPath.equals(e.inputPath))).getSingleOrNull();
    final assetId = existing?.id ?? newId();
    final at = e.createdAt.millisecondsSinceEpoch;
    if (existing != null && existing.width == null) {
      // Queued before the core read it: the size is known now.
      await (_db.update(_db.assets)..where((a) => a.id.equals(assetId))).write(
        AssetsCompanion(width: Value(e.sourceWidth), height: Value(e.sourceHeight)),
      );
    }
    if (existing == null) {
      await _db
          .into(_db.assets)
          .insert(
            AssetsCompanion.insert(
              id: assetId,
              inboxPath: e.inputPath,
              width: Value(e.sourceWidth),
              height: Value(e.sourceHeight),
              createdAt: at,
            ),
          );
    }
    final recipeId = newId();
    await _db
        .into(_db.recipes)
        .insert(
          RecipesCompanion.insert(
            id: recipeId,
            schema: Recipe.schemaVersion,
            json: jsonEncode(e.recipe.toJson()),
            createdAt: at,
          ),
        );
    await _db
        .into(_db.history)
        .insert(
          HistoryCompanion.insert(
            id: e.id,
            assetId: assetId,
            recipeId: recipeId,
            jobId: e.jobId,
            resultUri: e.resultUri,
            previewPath: e.previewPath,
            width: e.width,
            height: e.height,
            modelIds: jsonEncode(e.modelIds),
            backend: e.backend,
            durationMs: Value(e.duration?.inMilliseconds),
            createdAt: at,
          ),
        );
  });

  JoinedSelectStatement<HasResultSet, dynamic> _joined() => _db.select(_db.history).join([
    innerJoin(_db.assets, _db.assets.id.equalsExp(_db.history.assetId)),
    innerJoin(_db.recipes, _db.recipes.id.equalsExp(_db.history.recipeId)),
  ]);

  /// Newest first.
  Stream<List<HistoryEntry>> watchAll() =>
      (_joined()..orderBy([OrderingTerm.desc(_db.history.createdAt)])).watch().map(
        (rows) => [for (final r in rows) _entry(r)],
      );

  Future<HistoryEntry?> get(String id) => watch(id).first;

  /// One entry; null once it is deleted.
  Stream<HistoryEntry?> watch(String id) => (_joined()..where(_db.history.id.equals(id)))
      .watchSingleOrNull()
      .map((r) => r == null ? null : _entry(r));

  /// Preview paths of all entries (the startup sweep deletes files no entry refers to).
  Future<Set<String>> previewPaths() async {
    final q = _db.selectOnly(_db.history)..addColumns([_db.history.previewPath]);
    return {for (final r in await q.get()) r.read(_db.history.previewPath)!};
  }

  /// Rows are decoded here, once: a recipe this version cannot read throws [FormatException].
  HistoryEntry _entry(TypedResult r) {
    final h = r.readTable(_db.history);
    final a = r.readTable(_db.assets);
    final recipe = r.readTable(_db.recipes);
    final models = jsonDecode(h.modelIds);
    if (models is! List || models.any((m) => m is! String)) {
      throw FormatException('bad model_ids', h.modelIds);
    }
    return HistoryEntry(
      id: h.id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(h.createdAt),
      recipe: Recipe.fromJson((jsonDecode(recipe.json) as Map).cast()),
      inputPath: a.inboxPath,
      // add() stores the size with the entry.
      sourceWidth: a.width ?? (throw FormatException('asset ${a.id} has no size')),
      sourceHeight: a.height ?? (throw FormatException('asset ${a.id} has no size')),
      width: h.width,
      height: h.height,
      previewPath: h.previewPath,
      resultUri: h.resultUri,
      modelIds: models.cast(),
      backend: h.backend,
      duration: h.durationMs == null ? null : Duration(milliseconds: h.durationMs!),
      jobId: h.jobId,
    );
  }

  /// Deletes one entry (FR-HIST-004).
  Future<HistoryRemoval> remove(String id) => _db.transaction(() async {
    final h = await (_db.select(_db.history)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (h == null) return const HistoryRemoval();
    await (_db.delete(_db.history)..where((t) => t.id.equals(id))).go();
    return HistoryRemoval(
      previews: [h.previewPath],
      jobIds: await _unusedJobs({h.jobId}),
      inputs: await _db.dropUnreferenced(),
    );
  });

  /// Deletes every entry (FR-HIST-004, FR-HIST-005).
  Future<HistoryRemoval> removeAll() => _db.transaction(() async {
    final rows = await _db.select(_db.history).get();
    await _db.delete(_db.history).go();
    return HistoryRemoval(
      previews: [for (final h in rows) h.previewPath],
      jobIds: await _unusedJobs({for (final h in rows) h.jobId}),
      inputs: await _db.dropUnreferenced(),
    );
  });

  /// Of [jobIds], those no remaining entry or queue job refers to (a finished queue job keeps
  /// its directory until it is saved or removed from the queue).
  Future<Set<String>> _unusedJobs(Set<String> jobIds) async {
    final h = _db.selectOnly(_db.history)
      ..addColumns([_db.history.jobId])
      ..where(_db.history.jobId.isIn(jobIds));
    final q = _db.selectOnly(_db.queueJobs)
      ..addColumns([_db.queueJobs.jobId])
      ..where(_db.queueJobs.jobId.isIn(jobIds));
    final used = {
      for (final r in await h.get()) r.read(_db.history.jobId)!,
      for (final r in await q.get()) r.read(_db.queueJobs.jobId)!,
    };
    return jobIds.difference(used);
  }
}
