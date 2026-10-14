import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import 'database.dart';
import 'engine.dart';
import 'job_store.dart';

/// History entries and their files (FR-HIST-001..005, PRIV-DATA-002/004). Previews live in
/// AppSupport/history: the system may clear Cache/ while the entry stays (07 §2).
class HistoryStore {
  HistoryStore(this.repo, this.supportDir, this.jobs);

  final HistoryRepository repo;
  final String supportDir;
  final JobStore jobs;

  static const previewMaxSide = 512;

  String get previewDir => '$supportDir/history';

  /// Paths in the database are relative to AppSupport (the iOS container moves on updates).
  String absolute(String relative) => '$supportDir/$relative';

  String relative(String path) {
    if (!path.startsWith('$supportDir/')) {
      throw ArgumentError.value(path, 'path', 'not under AppSupport');
    }
    return path.substring(supportDir.length + 1);
  }

  /// Where the export writes the preview of entry [id].
  String previewPathFor(String id) {
    Directory(previewDir).createSync(recursive: true);
    return '$previewDir/$id.jpg';
  }

  /// Deletes an entry and every file only it referred to (FR-HIST-004).
  Future<void> remove(String id) async => _deleteFiles(await repo.remove(id));

  /// Deletes the whole history (FR-HIST-004, FR-HIST-005).
  Future<void> clear() async => _deleteFiles(await repo.removeAll());

  /// Rows go first: a file that cannot be deleted now is an orphan the next [sweep] (previews)
  /// or [JobStore.sweep] (jobs, inbox) removes. Tries every file, then throws the first failure.
  void _deleteFiles(HistoryRemoval r) {
    FileSystemException? failure;
    void attempt(void Function() delete) {
      try {
        delete();
      } on FileSystemException catch (e) {
        failure ??= e;
      }
    }

    for (final p in r.previews) {
      attempt(() {
        final f = File(absolute(p));
        if (f.existsSync()) f.deleteSync();
      });
    }
    for (final id in r.jobIds) {
      attempt(() => jobs.discard('${jobs.jobsDir}/$id'));
    }
    for (final input in r.inputs) {
      attempt(() => jobs.releaseInput(absolute(input)));
    }
    if (failure case final e?) throw e;
  }

  /// Startup: deletes previews no entry refers to (left by a crash between the export and the
  /// insert, or by a failed delete). Runs before any export can write a new one.
  Future<void> sweep() async {
    final dir = Directory(previewDir);
    if (!dir.existsSync()) return;
    final known = await repo.previewPaths();
    for (final f in dir.listSync().whereType<File>()) {
      if (known.contains(relative(f.path))) continue;
      try {
        f.deleteSync();
      } on FileSystemException {
        // Retried at the next start.
      }
    }
  }
}

/// The history store, swept once per process before first use.
final historyStoreProvider = FutureProvider<HistoryStore>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final dirs = await ref.watch(appDirsProvider.future);
  final store = HistoryStore(HistoryRepository(db), dirs.support, jobStoreOf(dirs));
  await store.sweep();
  return store;
});

/// Newest first.
final historyProvider = StreamProvider<List<HistoryEntry>>((ref) async* {
  final store = await ref.watch(historyStoreProvider.future);
  yield* store.repo.watchAll();
});
