import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/history.dart';
import 'package:refocal/bootstrap/job_store.dart';
import 'package:refocal/bootstrap/storage.dart';
import 'package:refocal_core/refocal_core.dart';
import 'package:refocal_platform/refocal_platform.dart';

void main() {
  late Directory root;
  late RefocalDatabase db;
  late JobStore jobs;
  late StorageManager storage;
  var queued = <String>{};
  var logsCleared = 0;

  File file(String rel, int bytes) => File('${root.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsBytesSync(List.filled(bytes, 1));

  void job(String id, String input) => File('${jobs.jobsDir}/$id/request.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(JobRequest(id: id, input: input, scale: 4, srModel: 'sr.m')));

  setUp(() {
    root = Directory.systemTemp.createTempSync('refocal-storage');
    db = RefocalDatabase.memory();
    jobs = JobStore(jobsDir: '${root.path}/support/jobs', inboxDir: '${root.path}/support/inbox');
    queued = {};
    logsCleared = 0;
    storage = StorageManager(
      dirs: AppDirs(
        support: '${root.path}/support',
        backedUp: '${root.path}/files',
        cache: '${root.path}/cache',
      ),
      jobs: jobs,
      history: HistoryStore(HistoryRepository(db), '${root.path}/support', jobs),
      queueInputs: () async => queued,
      clearLogs: () async => logsCleared++,
      logFiles: () => ['${root.path}/support/logs/refocal.log'],
    );
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('copies count only what no job or queue needs; clearing keeps those', () async {
    final free = file('support/inbox/free.jpg', 100);
    final paused = file('support/inbox/paused.jpg', 200);
    final inQueue = file('support/inbox/queued.jpg', 400);
    final partial = file('support/inbox/new.jpg.part', 10);
    job('job-p', paused.path);
    queued = {inQueue.path};
    expect((await storage.measure())[StorageCategory.copies], 110);
    await storage.clear(StorageCategory.copies);
    expect(free.existsSync(), isFalse);
    expect(paused.existsSync() && inQueue.existsSync(), isTrue);
    expect(partial.existsSync(), isTrue, reason: 'the platform may still be writing it');
  });

  test('unfinished jobs are the editor\'s, not the queue\'s', () async {
    final a = file('support/inbox/a.jpg', 1), q = file('support/inbox/q.jpg', 1);
    job('job-editor', a.path);
    job('job-queue', q.path);
    file('support/jobs/job-editor/bands/0.bin', 1000);
    file('support/jobs/job-queue/bands/0.bin', 5000);
    queued = {q.path};
    final unfinished = (await storage.measure())[StorageCategory.unfinished];
    expect(unfinished, greaterThan(1000));
    expect(unfinished, lessThan(5000));
    await storage.clear(StorageCategory.unfinished);
    expect(Directory('${jobs.jobsDir}/job-editor').existsSync(), isFalse);
    expect(a.existsSync(), isFalse, reason: 'its input goes with it');
    expect(Directory('${jobs.jobsDir}/job-queue').existsSync(), isTrue);
  });

  test('cache, log and models are measured; models cannot be cleared', () async {
    file('cache/export/x.jpg', 300);
    file('cache/share/log.txt', 20);
    file('support/logs/refocal.log', 50);
    file('support/models/sr/model.bin', 7000);
    final u = await storage.measure();
    expect(
      (u[StorageCategory.cache], u[StorageCategory.logs], u[StorageCategory.models]),
      (320, 50, 7000),
    );
    await storage.clear(StorageCategory.cache);
    await storage.clear(StorageCategory.logs);
    expect(Directory('${root.path}/cache').listSync(), isEmpty);
    expect(logsCleared, 1);
    expect(StorageManager.clearable(StorageCategory.models), isFalse);
    expect(() => storage.clear(StorageCategory.models), throwsStateError);
  });
}
