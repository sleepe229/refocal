import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_platform/refocal_platform.dart';

import 'app_log.dart';
import 'history.dart';
import 'job_store.dart';
import 'queue.dart';

/// The categories of the Storage screen (FR-SET-004, PRIV-DATA-003, 07 §2).
enum StorageCategory {
  /// Copies of originals in inbox/ that no unfinished job or queue job needs.
  copies,

  /// Editor jobs that were paused or not saved (jobs/ outside the queue).
  unfinished,

  /// History previews (clearing deletes the history).
  history,

  /// Cache/: export and share copies; the system may clear it as well.
  cache,

  /// The bug-report log (FR-SET-007).
  logs,

  /// Installed models: bundled ones cannot be removed (packs come with the model manager).
  models,
}

/// Bytes per category, and what clearing a category would remove.
class StorageUsage {
  const StorageUsage(this.bytes);
  final Map<StorageCategory, int> bytes;

  int operator [](StorageCategory c) => bytes[c] ?? 0;
  int get total => bytes.values.fold(0, (a, b) => a + b);
}

/// Measures and clears app storage. Paths in use by the queue or an unfinished job are never
/// counted as clearable copies, and never deleted from here.
class StorageManager {
  StorageManager({
    required this.dirs,
    required this.jobs,
    required this.history,
    required this.queueInputs,
    this.clearLogs = AppLog.clear,
    this.logFiles = _appLogFiles,
  });

  final AppDirs dirs;
  final JobStore jobs;
  final HistoryStore history;

  /// Inbox paths (absolute) the queue refers to.
  final Future<Set<String>> Function() queueInputs;
  final Future<void> Function() clearLogs;
  final List<String> Function() logFiles;

  static List<String> _appLogFiles() => AppLog.files;

  String get _inbox => jobs.inboxDir;

  Future<StorageUsage> measure() async {
    final keep = await _inUse();
    var copies = 0;
    for (final f in await _files(_inbox)) {
      if (!keep.contains(f.path)) copies += await _size(f);
    }
    var unfinished = 0;
    for (final j in await _unfinished()) {
      unfinished += await _dirSize(Directory(j.dir));
    }
    return StorageUsage({
      StorageCategory.copies: copies,
      StorageCategory.unfinished: unfinished,
      StorageCategory.history: await _dirSize(Directory(history.previewDir)),
      StorageCategory.cache: await _dirSize(Directory(dirs.cache)),
      StorageCategory.logs: await _sum(logFiles().map(File.new)),
      StorageCategory.models: await _dirSize(Directory('${dirs.support}/models')),
    });
  }

  /// Whether [c] can be cleared from the Storage screen.
  static bool clearable(StorageCategory c) => c != StorageCategory.models;

  Future<void> clear(StorageCategory c) async {
    switch (c) {
      case StorageCategory.copies:
        final keep = await _inUse();
        for (final f in await _files(_inbox)) {
          // A copy the platform is still writing (ADR-0010) is not ours to delete yet.
          if (!keep.contains(f.path) && !f.path.endsWith('.part')) await _delete(f);
        }
      case StorageCategory.unfinished:
        for (final j in await _unfinished()) {
          await jobs.discard(j.dir);
        }
      case StorageCategory.history:
        await history.clear();
      case StorageCategory.cache:
        final cache = Directory(dirs.cache);
        if (await cache.exists()) {
          await for (final e in cache.list()) {
            await _delete(e);
          }
        }
      case StorageCategory.logs:
        await clearLogs();
      case StorageCategory.models:
        throw StateError('bundled models cannot be removed');
    }
    AppLog.info('storage: cleared ${c.name}');
  }

  /// Editor jobs: those the queue does not own.
  Future<List<JobEntry>> _unfinished() async {
    final queued = await queueInputs();
    return [
      for (final j in await jobs.list())
        if (!queued.contains(j.input)) j,
    ];
  }

  /// Inputs of unfinished jobs and queue jobs.
  Future<Set<String>> _inUse() async => {
    ...await queueInputs(),
    for (final j in await jobs.list()) j.input,
  };

  static Future<List<File>> _files(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    return d.list().where((e) => e is File).cast<File>().toList();
  }

  static Future<int> _size(File f) async {
    try {
      return await f.length();
    } on FileSystemException {
      return 0; // deleted meanwhile
    }
  }

  static Future<int> _sum(Iterable<File> files) async {
    var n = 0;
    for (final f in files) {
      n += await _size(f);
    }
    return n;
  }

  static Future<int> _dirSize(Directory d) async {
    if (!await d.exists()) return 0;
    var n = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) n += await _size(e);
    }
    return n;
  }

  /// A file still held by the system is left for the startup sweep.
  static Future<void> _delete(FileSystemEntity e) async {
    try {
      await e.delete(recursive: true);
    } on FileSystemException catch (err) {
      AppLog.warn('storage: not deleted: ${err.message}');
    }
  }
}

final storageManagerProvider = FutureProvider.autoDispose<StorageManager>((ref) async {
  final engine = await ref.watch(startupProvider.future);
  final queue = await ref.watch(queueRepositoryProvider.future);
  return StorageManager(
    dirs: engine.dirs,
    jobs: engine.jobs,
    history: await ref.watch(historyStoreProvider.future),
    queueInputs: () async => {
      for (final i in (await queue.references()).inputs) '${engine.dirs.support}/$i',
    },
  );
});

/// Measured when the Storage screen opens; invalidate after clearing.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>(
  (ref) async => (await ref.watch(storageManagerProvider.future)).measure(),
);
