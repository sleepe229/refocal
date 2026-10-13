import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/job_store.dart';
import 'package:refocal/bootstrap/settings.dart';

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
      jsonEncode({'schema': 1, 'job_id': id, 'input': inputPath, 'scale': 2, 'fast2': true}),
    );
    if (bandIdx != null) {
      File('${d.path}/checkpoint.json')
          .writeAsStringSync(jsonEncode({'band_idx': bandIdx, 'bands_total': bands}));
    }
    if (finished) File('${d.path}/result.json').writeAsStringSync('{}');
    return d.path;
  }

  test('lists paused and finished jobs with progress', () {
    final a = input('a.jpg');
    job('j1', a, bandIdx: 1);
    job('j2', a, finished: true);
    Directory('${store.jobsDir}/junk').createSync();
    final jobs = {for (final j in store.list()) j.id: j};
    expect(jobs.keys, unorderedEquals(['j1', 'j2']));
    expect(jobs['j1']!.progress, 0.5);
    expect(jobs['j1']!.resumable, isTrue);
    expect(jobs['j1']!.scaleLabel, 'Fast 2×');
    expect(jobs['j2']!.finished, isTrue);
    expect(jobs['j2']!.resumable, isFalse);
  });

  test('discard keeps an inbox copy another job still uses', () {
    final a = input('a.jpg');
    final d1 = job('j1', a, bandIdx: 0);
    final d2 = job('j2', a, bandIdx: 0);
    store.discard(d1);
    expect(Directory(d1).existsSync(), isFalse);
    expect(File(a).existsSync(), isTrue);
    store.discard(d2);
    expect(File(a).existsSync(), isFalse);
  });

  test('releaseInput respects screens that hold the file and paths outside the inbox', () {
    final a = input('a.jpg');
    store.releaseInput(a, inUse: {a});
    expect(File(a).existsSync(), isTrue);
    final outside = File('${root.path}/outside.jpg')..writeAsStringSync('x');
    store.releaseInput(outside.path);
    expect(outside.existsSync(), isTrue);
    store.releaseInput(a);
    expect(File(a).existsSync(), isFalse);
  });

  test('sweep removes old jobs and orphaned inbox copies', () {
    final a = input('a.jpg'), orphan = input('orphan.jpg');
    final d = job('j1', a, bandIdx: 0);
    store.sweep();
    expect(File(orphan).existsSync(), isFalse);
    expect(File(a).existsSync(), isTrue);
    store.sweep(now: DateTime.now().add(const Duration(days: 8)));
    expect(Directory(d).existsSync(), isFalse);
    expect(File(a).existsSync(), isFalse);
  });

  test('settings default to the private choices and survive a round trip', () {
    const d = Settings();
    expect(d.keepGps, isFalse);
    expect(d.aiMarker, isTrue);
    final s = Settings.fromJson(
      jsonDecode(jsonEncode(d.copyWith(keepGps: true).toJson())) as Map<String, Object?>,
    );
    expect(s.keepGps, isTrue);
    expect(s.aiMarker, isTrue);
    expect(Settings.fromJson(const {}).aiMarker, isTrue);
  });
}
