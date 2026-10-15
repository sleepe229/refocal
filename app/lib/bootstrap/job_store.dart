import 'dart:convert';
import 'dart:io';

import 'package:refocal_core/refocal_core.dart';

/// What is on disk under `jobs/` and `inbox/` (07 §1, ADR-0004, ADR-0010). The job directory is
/// the source of truth for unfinished jobs (the checkpoint, ADR-0004) until the queue keeps
/// them in `queue_jobs`: request.json, checkpoint.json while running or paused, result.json when
/// finished.
class JobEntry {
  JobEntry({
    required this.dir,
    required this.request,
    required this.modified,
    required this.finished,
    required this.progress,
    required this.inputExists,
  });

  final String dir;

  /// As the core rewrote it (a NEEDS_USER answer may have lowered the scale).
  final JobRequest request;
  final DateTime modified;

  /// result.json exists: the result can be opened and saved.
  final bool finished;

  /// Committed bands / all bands, 0 when nothing was committed yet.
  final double progress;

  /// When the directory was read.
  final bool inputExists;

  String get id => request.id;
  String get input => request.input;
  bool get resumable => !finished && inputExists;
  String get previewPath => '$dir/preview.jpg';
}

class JobStore {
  JobStore({required this.jobsDir, required this.inboxDir});

  final String jobsDir, inboxDir;

  /// Jobs and inbox copies are deleted after this long (07 §1).
  static const maxAge = Duration(days: 7);

  /// Unfinished writes younger than this may still be in progress.
  static const partialAge = Duration(hours: 1);

  String dirOf(String jobId) => '$jobsDir/$jobId';

  /// Newest first.
  Future<List<JobEntry>> list() async {
    final out = <JobEntry>[];
    for (final d in await _children<Directory>(jobsDir)) {
      if (await _read(d) case final e?) out.add(e);
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  Future<JobEntry?> _read(Directory d) async {
    try {
      final req = File('${d.path}/request.json');
      final request = JobRequest.fromJson(
        (jsonDecode(await req.readAsString()) as Map).cast<String, Object?>(),
      );
      final finished = await File('${d.path}/result.json').exists();
      var progress = finished ? 1.0 : 0.0;
      var modified = (await req.stat()).modified;
      final ck = File('${d.path}/checkpoint.json');
      if (!finished && await ck.exists()) {
        final c = (jsonDecode(await ck.readAsString()) as Map).cast<String, Object?>();
        final total = (c['bands_total'] as num?)?.toInt() ?? 0;
        final idx = (c['band_idx'] as num?)?.toInt() ?? -1;
        if (total > 0) progress = (idx + 1) / total;
        final m = (await ck.stat()).modified;
        if (m.isAfter(modified)) modified = m;
      }
      return JobEntry(
        dir: d.path,
        request: request,
        modified: modified,
        finished: finished,
        progress: progress,
        inputExists: await File(request.input).exists(),
      );
    } on FileSystemException {
      return null; // half-written or vanished meanwhile: left to [sweep]'s age rule
    } on FormatException {
      return null; // not a request of this version: likewise
    }
  }

  /// Deletes a job and its inbox copy when no other job uses it (PRIV-DATA-004).
  Future<void> discard(String jobDir, {Set<String> inUse = const {}}) async {
    final e = await _read(Directory(jobDir));
    final d = Directory(jobDir);
    if (await d.exists()) await d.delete(recursive: true);
    if (e != null) await releaseInput(e.input, inUse: inUse);
  }

  /// Deletes an inbox copy unless a job or an open screen still refers to it.
  Future<void> releaseInput(String input, {Set<String> inUse = const {}}) async {
    if (!_isInInbox(input) || inUse.contains(input)) return;
    if ((await list()).any((j) => j.input == input)) return;
    final f = File(input);
    if (await f.exists()) await f.delete();
  }

  /// Startup cleanup: jobs older than [maxAge], directories without a readable request, and
  /// inbox copies no job refers to (nothing is open yet when this runs). [keepJobs] (directory
  /// names) and [keepInputs] are what the queue still refers to: a queued photo has no job
  /// directory yet, and the queue expires its own jobs. A copy the platform is
  /// still writing (`*.part`, ADR-0010) is kept until it is [partialAge] old. Each deletion is
  /// best effort: one that fails (e.g. a file the system holds) does not stop the others and is
  /// retried at the next start.
  Future<void> sweep({
    DateTime? now,
    Set<String> keepJobs = const {},
    Set<String> keepInputs = const {},
  }) async {
    final t = now ?? DateTime.now();
    for (final d in await _children<Directory>(jobsDir)) {
      if (keepJobs.contains(d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) continue;
      await _bestEffort(() async {
        final e = await _read(d);
        final age = t.difference(e?.modified ?? (await d.stat()).modified);
        if (age > maxAge || (e == null && age > partialAge)) await d.delete(recursive: true);
      });
    }
    final referenced = {...keepInputs, for (final j in await list()) j.input};
    for (final f in await _children<File>(inboxDir)) {
      if (referenced.contains(f.path)) continue;
      await _bestEffort(() async {
        if (f.path.endsWith('.part') && t.difference((await f.stat()).modified) <= partialAge) {
          return;
        }
        await f.delete();
      });
    }
  }

  static Future<List<T>> _children<T extends FileSystemEntity>(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    return d.list().where((e) => e is T).cast<T>().toList();
  }

  static Future<void> _bestEffort(Future<void> Function() f) async {
    try {
      await f();
    } on FileSystemException {
      // Retried at the next start (see sweep).
    }
  }

  bool _isInInbox(String path) => path.startsWith('$inboxDir/');
}
