import 'dart:convert';
import 'dart:io';

/// What is on disk under `jobs/` and `inbox/` (07 §1, ADR-0004, ADR-0010). The job directory is
/// the source of truth for unfinished jobs (the checkpoint, ADR-0004) until the queue keeps
/// them in `queue_jobs`: request.json, checkpoint.json while running or paused, result.json when
/// finished.
class JobEntry {
  JobEntry({
    required this.id,
    required this.dir,
    required this.input,
    required this.scale,
    required this.fast2,
    required this.modified,
    required this.finished,
    required this.progress,
  });

  final String id, dir, input;
  final int scale;
  final bool fast2;
  final DateTime modified;

  /// result.json exists: the result can be opened and saved.
  final bool finished;

  /// Committed bands / all bands, 0 when nothing was committed yet.
  final double progress;

  bool get inputExists => File(input).existsSync();
  bool get resumable => !finished && inputExists;
  String get previewPath => '$dir/preview.jpg';
}

class JobStore {
  JobStore({required this.jobsDir, required this.inboxDir});

  final String jobsDir, inboxDir;

  /// Jobs and inbox copies are deleted after this long (07 §1).
  static const maxAge = Duration(days: 7);

  List<JobEntry> list() {
    final root = Directory(jobsDir);
    if (!root.existsSync()) return [];
    final out = <JobEntry>[];
    for (final d in root.listSync().whereType<Directory>()) {
      final e = _read(d);
      if (e != null) out.add(e);
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  JobEntry? _read(Directory d) {
    try {
      final req = File('${d.path}/request.json');
      final r = jsonDecode(req.readAsStringSync()) as Map<String, Object?>;
      final finished = File('${d.path}/result.json').existsSync();
      var progress = finished ? 1.0 : 0.0;
      final ck = File('${d.path}/checkpoint.json');
      if (!finished && ck.existsSync()) {
        final c = jsonDecode(ck.readAsStringSync()) as Map<String, Object?>;
        final total = (c['bands_total'] as num?)?.toInt() ?? 0;
        final idx = (c['band_idx'] as num?)?.toInt() ?? -1;
        if (total > 0) progress = (idx + 1) / total;
      }
      var modified = req.statSync().modified;
      if (ck.existsSync()) {
        final m = ck.statSync().modified;
        if (m.isAfter(modified)) modified = m;
      }
      return JobEntry(
        id: r['job_id'] as String,
        dir: d.path,
        input: r['input'] as String,
        scale: (r['scale'] as num?)?.toInt() ?? 4,
        fast2: r['fast2'] == true,
        modified: modified,
        finished: finished,
        progress: progress,
      );
    } on Object {
      return null; // half-written or foreign directory: left to [sweep]'s age rule
    }
  }

  /// Deletes a job and its inbox copy when no other job uses it (PRIV-DATA-004).
  void discard(String jobDir, {Set<String> inUse = const {}}) {
    final e = _read(Directory(jobDir));
    _deleteDir(jobDir);
    if (e != null) releaseInput(e.input, inUse: inUse);
  }

  /// Deletes an inbox copy unless a job or an open screen still refers to it.
  void releaseInput(String input, {Set<String> inUse = const {}}) {
    if (!_isInInbox(input) || inUse.contains(input)) return;
    if (list().any((j) => j.input == input)) return;
    final f = File(input);
    if (f.existsSync()) f.deleteSync();
  }

  /// Startup cleanup: jobs older than [maxAge], directories without a readable request, and
  /// inbox copies no job refers to (nothing is open yet when this runs). A copy the platform is
  /// still writing (`*.part`, ADR-0010) is kept until it is [partialAge] old. Each deletion is
  /// best effort: one that fails (e.g. a file the system holds) does not stop the others and is
  /// retried at the next start.
  void sweep({DateTime? now}) {
    final t = now ?? DateTime.now();
    for (final d in _children<Directory>(jobsDir)) {
      final e = _read(d);
      final age = t.difference(e?.modified ?? d.statSync().modified);
      if (age > maxAge || (e == null && age > partialAge)) _tryDelete(d);
    }
    final referenced = list().map((j) => j.input).toSet();
    for (final f in _children<File>(inboxDir)) {
      if (referenced.contains(f.path)) continue;
      if (f.path.endsWith('.part') && t.difference(f.statSync().modified) <= partialAge) continue;
      _tryDelete(f);
    }
  }

  /// Unfinished writes younger than this may still be in progress.
  static const partialAge = Duration(hours: 1);

  static Iterable<T> _children<T extends FileSystemEntity>(String dir) {
    final d = Directory(dir);
    return d.existsSync() ? d.listSync().whereType<T>() : const [];
  }

  static void _tryDelete(FileSystemEntity e) {
    try {
      e.deleteSync(recursive: true);
    } on FileSystemException {
      // Retried at the next start (see sweep).
    }
  }

  bool _isInInbox(String path) => path.startsWith('$inboxDir/');

  static void _deleteDir(String path) {
    final d = Directory(path);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
