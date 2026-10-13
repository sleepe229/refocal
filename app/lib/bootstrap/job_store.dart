import 'dart:convert';
import 'dart:io';

/// What is on disk under `jobs/` and `inbox/` (07 §1, ADR-0004, ADR-0010). The job directory is
/// the source of truth until the history database (0.3): request.json, checkpoint.json while
/// running or paused, result.json when finished.
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
  String get scaleLabel => fast2 ? 'Fast 2×' : '$scale×';
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
  /// inbox copies no job refers to (nothing is open yet when this runs).
  void sweep({DateTime? now}) {
    final t = now ?? DateTime.now();
    final root = Directory(jobsDir);
    if (root.existsSync()) {
      for (final d in root.listSync().whereType<Directory>()) {
        final e = _read(d);
        final age = t.difference(e?.modified ?? d.statSync().modified);
        if (age > maxAge || (e == null && age > const Duration(hours: 1))) _deleteDir(d.path);
      }
    }
    final inbox = Directory(inboxDir);
    if (!inbox.existsSync()) return;
    final referenced = list().map((j) => j.input).toSet();
    for (final f in inbox.listSync().whereType<File>()) {
      if (!referenced.contains(f.path)) f.deleteSync();
    }
  }

  bool _isInInbox(String path) => path.startsWith('$inboxDir/');

  static void _deleteDir(String path) {
    final d = Directory(path);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }
}
