import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/job_store.dart';

void main() {
  late Directory root;
  late JobStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('refocal-store');
    store = JobStore(jobsDir: '${root.path}/jobs', inboxDir: '${root.path}/inbox');
    Directory(store.inboxDir).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  String input(String name) {
    final f = File('${store.inboxDir}/$name')..writeAsStringSync('x');
    return f.path;
  }

  String job(String id, String inputPath, {int? bandIdx, int bands = 4, bool finished = false}) {
    final d = Directory('${store.jobsDir}/$id')..createSync(recursive: true);
    File('${d.path}/request.json').writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'job_id': id,
        'input': inputPath,
        'sr_model': 'sr.general-x4v3',
        'scale': 2,
        'fast2': true,
        'tile': 0, // the core adds its own fields
      }),
    );
    if (bandIdx != null) {
      File('${d.path}/checkpoint.json')
          .writeAsStringSync(jsonEncode({'band_idx': bandIdx, 'bands_total': bands}));
    }
    if (finished) File('${d.path}/result.json').writeAsStringSync('{}');
    return d.path;
  }

  test('lists paused and finished jobs with progress', () async {
    final a = input('a.jpg');
    job('j1', a, bandIdx: 1);
    job('j2', a, finished: true);
    Directory('${store.jobsDir}/junk').createSync();
    job('old', a, bandIdx: 0);
    File('${store.jobsDir}/old/request.json').writeAsStringSync('{"schema": 2}');
    final jobs = {for (final j in await store.list()) j.id: j};
    expect(jobs.keys, unorderedEquals(['j1', 'j2']));
    expect(jobs['j1']!.progress, 0.5);
    expect(jobs['j1']!.resumable, isTrue);
    expect(jobs['j1']!.inputExists, isTrue);
    expect(jobs['j1']!.request.fast2, isTrue);
    expect(jobs['j2']!.finished, isTrue);
    expect(jobs['j2']!.resumable, isFalse);
  });

  test('discard keeps an inbox copy another job still uses', () async {
    final a = input('a.jpg');
    final d1 = job('j1', a, bandIdx: 0);
    final d2 = job('j2', a, bandIdx: 0);
    await store.discard(d1);
    expect(Directory(d1).existsSync(), isFalse);
    expect(File(a).existsSync(), isTrue);
    await store.discard(d2);
    expect(File(a).existsSync(), isFalse);
  });

  test('releaseInput keeps a copy the queue needs (one copy per content, FR-IMP-004)', () async {
    final a = input('a.jpg');
    final queued = JobStore(
      jobsDir: store.jobsDir,
      inboxDir: store.inboxDir,
      otherInputs: () async => {a},
    );
    await queued.releaseInput(a);
    expect(File(a).existsSync(), isTrue);
    await store.releaseInput(a);
    expect(File(a).existsSync(), isFalse);
  });

  test('releaseInput respects screens that hold the file and paths outside the inbox', () async {
    final a = input('a.jpg');
    await store.releaseInput(a, inUse: {a});
    expect(File(a).existsSync(), isTrue);
    final outside = File('${root.path}/outside.jpg')..writeAsStringSync('x');
    await store.releaseInput(outside.path);
    expect(outside.existsSync(), isTrue);
    await store.releaseInput(a);
    expect(File(a).existsSync(), isFalse);
  });

  test('sweep removes old jobs and orphaned inbox copies', () async {
    final a = input('a.jpg'), orphan = input('orphan.jpg');
    final d = job('j1', a, bandIdx: 0);
    await store.sweep();
    expect(File(orphan).existsSync(), isFalse);
    expect(File(a).existsSync(), isTrue);
    await store.sweep(now: DateTime.now().add(const Duration(days: 8)));
    expect(Directory(d).existsSync(), isFalse);
    expect(File(a).existsSync(), isFalse);
  });

  test('sweep keeps picker copies still being written, then removes them', () async {
    final now = DateTime.now();
    final fresh = File('${store.inboxDir}/in-1.jpg.part')..writeAsStringSync('x');
    final stale = File('${store.inboxDir}/in-0.jpg.part')..writeAsStringSync('x');
    stale.setLastModifiedSync(now.subtract(const Duration(hours: 2)));
    await store.sweep(now: now);
    expect(fresh.existsSync(), isTrue, reason: 'the platform may still be copying');
    expect(stale.existsSync(), isFalse);
    await store.sweep(now: now.add(const Duration(hours: 2)));
    expect(fresh.existsSync(), isFalse);
  });

  test('one deletion that fails does not stop the sweep', () async {
    final a = input('a.jpg'), b = input('b.jpg');
    // An abandoned job directory whose content cannot be deleted (read-only subdirectory).
    final locked = Directory('${store.jobsDir}/locked/sub')..createSync(recursive: true);
    File('${locked.path}/f').writeAsStringSync('x');
    Process.runSync('chmod', ['a-w', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['u+w', locked.path]));
    await store.sweep(now: DateTime.now().add(const Duration(days: 8)));
    expect(File(a).existsSync(), isFalse);
    expect(File(b).existsSync(), isFalse);
  });

  test('sweep spares what the queue refers to', () async {
    final queued = input('queued.jpg'), orphan = input('orphan.jpg');
    final d = job('job-q', input('paused.jpg'), bandIdx: 0);
    await store.sweep(
      now: DateTime.now().add(const Duration(days: 8)),
      keepJobs: {'job-q'},
      keepInputs: {queued},
    );
    expect(File(queued).existsSync(), isTrue, reason: 'not started: no job directory yet');
    expect(Directory(d).existsSync(), isTrue, reason: 'the queue expires its own jobs');
    expect(File('${store.inboxDir}/paused.jpg').existsSync(), isTrue);
    expect(File(orphan).existsSync(), isFalse);
  });

  test('the inbox quota drops the least recently used jobs first (NFR-SIZE-006)', () async {
    final small = JobStore(jobsDir: store.jobsDir, inboxDir: store.inboxDir, inboxQuota: 25);
    String big(String name) => (File('${store.inboxDir}/$name')..writeAsStringSync('x' * 10)).path;
    final oldest = job('job-1', big('a.jpg'), finished: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final queued = job('job-2', big('b.jpg'), bandIdx: 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final shared = job('job-3', big('c.jpg'), finished: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final newest = job('job-4', '${store.inboxDir}/c.jpg', bandIdx: 0);
    // 30 bytes over a quota of 25: job-1 goes (10 freed); job-2 is the queue's.
    await small.sweep(keepJobs: {'job-2'});
    expect(Directory(oldest).existsSync(), isFalse);
    expect(File('${store.inboxDir}/a.jpg').existsSync(), isFalse);
    expect(Directory(queued).existsSync(), isTrue);
    expect(Directory(shared).existsSync(), isTrue);
    expect(Directory(newest).existsSync(), isTrue);
    // Quota 5: job-3's copy is shared with job-4, so job-3 goes without freeing it; then job-4.
    final tiny = JobStore(jobsDir: store.jobsDir, inboxDir: store.inboxDir, inboxQuota: 5);
    await tiny.sweep(keepJobs: {'job-2'});
    expect(Directory(shared).existsSync(), isFalse);
    expect(Directory(newest).existsSync(), isFalse);
    expect(File('${store.inboxDir}/c.jpg').existsSync(), isFalse);
    expect(File('${store.inboxDir}/b.jpg').existsSync(), isTrue, reason: 'the queue keeps it');
    // Under the quota nothing goes.
    final fresh = job('job-5', big('d.jpg'));
    await store.sweep();
    expect(Directory(fresh).existsSync(), isTrue);
  });

  test('fragment previews are never listed and go at the next start (FR-ENH-015)', () async {
    final d = job('${JobStore.previewPrefix}x', input('p.jpg'), finished: true);
    expect(await store.list(), isEmpty);
    await store.sweep();
    expect(Directory(d).existsSync(), isFalse);
  });
}
