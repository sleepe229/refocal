import 'dart:convert';

import 'package:drift/drift.dart';

import '../recipe.dart';
import 'database.dart';
import 'tables.dart';

/// One photo in the batch queue (FR-BATCH-001). Paths are relative to AppSupport.
class QueueItem {
  const QueueItem({
    required this.id,
    required this.jobId,
    required this.inputPath,
    required this.recipe,
    required this.state,
    required this.position,
    required this.progress,
    required this.errorCode,
    required this.updatedAt,
  });

  final String id;

  /// The job directory name under AppSupport/jobs.
  final String jobId;

  /// The inbox copy (ADR-0010).
  final String inputPath;

  /// `output` set: saved in that format when done (FR-BATCH-006).
  final Recipe recipe;
  final QueueState state;
  final int position;
  final double progress;
  final String? errorCode;
  final DateTime updatedAt;

  bool get autosave => recipe.output != null;

  /// Waiting or stopped: the queue will (still) run it.
  bool get pending => state == QueueState.queued || state == QueueState.paused;
}

/// Counts by state, for the report "done N, failed M" (FR-BATCH-008, 06 §3.4).
class QueueSummary {
  const QueueSummary(this.counts);

  final Map<QueueState, int> counts;

  int operator [](QueueState s) => counts[s] ?? 0;
  int get finished => this[QueueState.done] + this[QueueState.saved];
  int get failed => this[QueueState.failed];
  int get pending => this[QueueState.queued] + this[QueueState.paused] + this[QueueState.running];
  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// What a removal left without a reference; the caller deletes the files.
class QueueRemoval {
  const QueueRemoval({this.jobIds = const {}, this.inputs = const {}});

  /// Job directories under AppSupport/jobs.
  final Set<String> jobIds;

  /// Inbox copies no queue job or history entry refers to any more.
  final Set<String> inputs;
}

/// The queue over `queue_jobs`, `assets` and `recipes` (07 §3).
class QueueRepository {
  QueueRepository(this._db);

  final RefocalDatabase _db;

  /// Adds [inputs] (inbox paths relative to AppSupport) in this order after the existing jobs,
  /// all with [recipe] (FR-BATCH-002). Returns the new items.
  Future<List<QueueItem>> enqueue(List<String> inputs, Recipe recipe, {DateTime? now}) =>
      _db.transaction(() async {
        final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
        final max = _db.queueJobs.position.max();
        final last = await (_db.selectOnly(_db.queueJobs)..addColumns([max])).getSingle();
        var position = (last.read(max) ?? -1) + 1;
        final recipeId = newId();
        await _db
            .into(_db.recipes)
            .insert(
              RecipesCompanion.insert(
                id: recipeId,
                schema: Recipe.schemaVersion,
                json: jsonEncode(recipe.toJson()),
                createdAt: at,
              ),
            );
        final ids = <String>[];
        for (final input in inputs) {
          // One copy per content (FR-IMP-004): the same photo again, or one the history or
          // another queue job already has, shares its asset.
          final existing = await (_db.select(
            _db.assets,
          )..where((a) => a.inboxPath.equals(input))).getSingleOrNull();
          final assetId = existing?.id ?? newId(), id = newId();
          if (existing == null) {
            await _db
                .into(_db.assets)
                .insert(AssetsCompanion.insert(id: assetId, inboxPath: input, createdAt: at));
          }
          await _db
              .into(_db.queueJobs)
              .insert(
                QueueJobsCompanion.insert(
                  id: id,
                  assetId: assetId,
                  recipeId: recipeId,
                  state: QueueState.queued,
                  position: position++,
                  jobId: 'job-$id',
                  createdAt: at,
                  updatedAt: at,
                ),
              );
          ids.add(id);
        }
        final rows = await (_joined()..where(_db.queueJobs.id.isIn(ids))).get();
        return _ordered(rows);
      });

  JoinedSelectStatement<HasResultSet, dynamic> _joined() => _db.select(_db.queueJobs).join([
    innerJoin(_db.assets, _db.assets.id.equalsExp(_db.queueJobs.assetId)),
    innerJoin(_db.recipes, _db.recipes.id.equalsExp(_db.queueJobs.recipeId)),
  ]);

  List<QueueItem> _ordered(List<TypedResult> rows) =>
      [for (final r in rows) _item(r)]..sort((a, b) => a.position.compareTo(b.position));

  /// Rows are decoded here, once: a recipe this version cannot read throws [FormatException].
  QueueItem _item(TypedResult r) {
    final q = r.readTable(_db.queueJobs);
    return QueueItem(
      id: q.id,
      jobId: q.jobId,
      inputPath: r.readTable(_db.assets).inboxPath,
      recipe: Recipe.fromJson((jsonDecode(r.readTable(_db.recipes).json) as Map).cast()),
      state: q.state,
      position: q.position,
      progress: q.progress,
      errorCode: q.errorCode,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(q.updatedAt),
    );
  }

  /// In processing order.
  Stream<List<QueueItem>> watchAll() =>
      (_joined()..orderBy([OrderingTerm.asc(_db.queueJobs.position)])).watch().map(_ordered);

  Future<List<QueueItem>> all() => watchAll().first;

  Future<QueueItem?> get(String id) async {
    final r = await (_joined()..where(_db.queueJobs.id.equals(id))).getSingleOrNull();
    return r == null ? null : _item(r);
  }

  /// The first job in [states], in processing order.
  Future<QueueItem?> first(Set<QueueState> states) async {
    final r =
        await (_joined()
              ..where(_db.queueJobs.state.isInValues(states))
              ..orderBy([OrderingTerm.asc(_db.queueJobs.position)])
              ..limit(1))
            .getSingleOrNull();
    return r == null ? null : _item(r);
  }

  Stream<QueueSummary> watchSummary() => watchAll().map((items) {
    final counts = <QueueState, int>{};
    for (final i in items) {
      counts[i.state] = (counts[i.state] ?? 0) + 1;
    }
    return QueueSummary(counts);
  });

  Future<QueueSummary> summary() => watchSummary().first;

  Future<void> setState(
    String id,
    QueueState state, {
    double? progress,
    String? errorCode,
    DateTime? now,
  }) => (_db.update(_db.queueJobs)..where((q) => q.id.equals(id))).write(
    QueueJobsCompanion(
      state: Value(state),
      progress: progress == null ? const Value.absent() : Value(progress),
      errorCode: Value(state == QueueState.failed ? errorCode : null),
      updatedAt: Value((now ?? DateTime.now()).millisecondsSinceEpoch),
    ),
  );

  Future<void> setProgress(String id, double progress) => (_db.update(
    _db.queueJobs,
  )..where((q) => q.id.equals(id))).write(QueueJobsCompanion(progress: Value(progress)));

  /// The size of the input once the core has read it (the history entry needs it).
  Future<void> setSourceSize(String id, int width, int height) => _db.transaction(() async {
    final q = await (_db.select(_db.queueJobs)..where((t) => t.id.equals(id))).getSingle();
    await (_db.update(_db.assets)..where((a) => a.id.equals(q.assetId))).write(
      AssetsCompanion(width: Value(width), height: Value(height)),
    );
  });

  /// Moves job [id] to [index] of the processing order (FR-BATCH-001).
  Future<void> move(String id, int index) => _db.transaction(() async {
    final order = [
      for (final q in await (_db.select(
        _db.queueJobs,
      )..orderBy([(t) => OrderingTerm.asc(t.position)])).get())
        q.id,
    ];
    if (!order.remove(id)) return;
    order.insert(index.clamp(0, order.length), id);
    for (final (i, qid) in order.indexed) {
      await (_db.update(
        _db.queueJobs,
      )..where((q) => q.id.equals(qid))).write(QueueJobsCompanion(position: Value(i)));
    }
  });

  /// Paused jobs go back in line (resume of the whole queue, FR-BATCH-003).
  Future<void> requeuePaused() =>
      (_db.update(_db.queueJobs)..where((q) => q.state.equalsValue(QueueState.paused))).write(
        QueueJobsCompanion(
          state: const Value(QueueState.queued),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Startup: a job "running" in a process that is gone is paused at its checkpoint (03 §6,
  /// FR-BATCH-007). Returns how many.
  Future<int> recover() =>
      (_db.update(_db.queueJobs)..where((q) => q.state.equalsValue(QueueState.running))).write(
        QueueJobsCompanion(
          state: const Value(QueueState.paused),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// Removes jobs (FR-BATCH-001). A running job must be stopped first.
  Future<QueueRemoval> remove(Iterable<String> ids) => _removeWhere((q) => q.id.isIn(ids));

  /// "Clear finished": saved and failed jobs; a done job keeps its unsaved result.
  Future<QueueRemoval> removeFinished() =>
      _removeWhere((q) => q.state.isInValues({QueueState.saved, QueueState.failed}));

  /// Jobs not touched for [age] (07 §1: jobs and inbox copies live 7 days), except a running one.
  Future<QueueRemoval> removeOlderThan(Duration age, {DateTime? now}) {
    final limit = (now ?? DateTime.now()).subtract(age).millisecondsSinceEpoch;
    return _removeWhere(
      (q) => q.updatedAt.isSmallerThanValue(limit) & q.state.equalsValue(QueueState.running).not(),
    );
  }

  Future<QueueRemoval> _removeWhere(Expression<bool> Function($QueueJobsTable) where) =>
      _db.transaction(() async {
        final rows = await (_db.select(_db.queueJobs)..where(where)).get();
        if (rows.isEmpty) return const QueueRemoval();
        await (_db.delete(_db.queueJobs)..where(where)).go();
        final inHistory = _db.selectOnly(_db.history)
          ..addColumns([_db.history.jobId])
          ..where(_db.history.jobId.isIn([for (final r in rows) r.jobId]));
        final kept = {for (final r in await inHistory.get()) r.read(_db.history.jobId)!};
        return QueueRemoval(
          jobIds: {
            for (final r in rows)
              if (!kept.contains(r.jobId)) r.jobId,
          },
          inputs: await _db.dropUnreferenced(),
        );
      });

  /// What the startup sweep of jobs/ and inbox/ must keep (07 §1).
  Future<({Set<String> jobIds, Set<String> inputs})> references() async {
    final rows = await _joined().get();
    return (
      jobIds: {for (final r in rows) r.readTable(_db.queueJobs).jobId},
      inputs: {for (final r in rows) r.readTable(_db.assets).inboxPath},
    );
  }
}
