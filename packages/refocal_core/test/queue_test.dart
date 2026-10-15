// FR-BATCH-001..003/007/008 over the database and a fake runner (TEST-INT-002 at the core
// level; the native part is covered by refocal_ffi and the emulator e2e).
import 'dart:async';

import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

final _recipe = Recipe(scale: 2, fast2: true, srModel: 'sr.m', strength: 0.8);
final _autosave = _recipe.copyWith(output: () => OutputSpec(ExportFormat.jpeg, quality: 90));

class FakeRunner implements QueueJobRunner {
  /// Outcome per input path; missing: finished, not saved.
  final outcomes = <String, QueueOutcome>{};
  final ran = <String>[];

  /// Inputs on which the runner itself throws (a bug, not a job failure).
  final throwFor = <String>{};
  Completer<void>? gate;
  bool paused = false, cancelled = false;

  @override
  Future<QueueOutcome> run(QueueItem item, void Function(double) onProgress) async {
    ran.add(item.inputPath);
    onProgress(0.5);
    if (gate case final g?) await g.future;
    if (paused) return const JobPaused(0.5);
    if (cancelled) return const JobFailed(JobFailed.cancelled);
    if (throwFor.contains(item.inputPath)) throw StateError('runner bug');
    return outcomes[item.inputPath] ??
        JobFinished(saved: item.autosave, sourceWidth: 40, sourceHeight: 30);
  }

  @override
  void pause() => paused = true;

  @override
  void cancel() => cancelled = true;
}

void main() {
  late RefocalDatabase db;
  late QueueRepository repo;
  late FakeRunner runner;
  late QueueOrchestrator queue;
  final errors = <Object>[];

  setUp(() {
    db = RefocalDatabase.memory();
    repo = QueueRepository(db);
    runner = FakeRunner();
    errors.clear();
    queue = QueueOrchestrator(repo, runner, onError: (e, _) => errors.add(e));
  });
  tearDown(() async {
    await queue.dispose();
    await db.close();
  });

  List<String> inputs(int n) => [for (var i = 0; i < n; i++) 'inbox/$i.jpg'];
  Future<Map<String, QueueState>> states() async => {
    for (final i in await repo.all()) i.inputPath: i.state,
  };

  group('repository', () {
    test('enqueue keeps the order, shares the recipe and appends to the end', () async {
      final first = await repo.enqueue(inputs(3), _recipe);
      expect(first.map((i) => i.inputPath), inputs(3));
      expect(first.map((i) => i.jobId).toSet(), hasLength(3));
      expect(first.every((i) => i.recipe == _recipe && i.state == QueueState.queued), isTrue);
      await repo.enqueue(['inbox/x.jpg'], _autosave);
      final all = await repo.all();
      expect(all.last.inputPath, 'inbox/x.jpg');
      expect(all.last.autosave, isTrue);
      expect(await db.select(db.recipes).get(), hasLength(2), reason: 'one recipe per batch');
    });

    test('the same copy twice shares one asset; removing one job keeps it (FR-IMP-004)', () async {
      final items = await repo.enqueue(['inbox/same.jpg', 'inbox/same.jpg'], _recipe);
      await repo.enqueue(['inbox/same.jpg'], _autosave);
      expect(await db.select(db.assets).get(), hasLength(1));
      final r = await repo.remove([items[0].id]);
      expect(r.inputs, isEmpty, reason: 'two jobs still use it');
      expect((await repo.references()).inputs, {'inbox/same.jpg'});
    });

    test('move reorders (FR-BATCH-001)', () async {
      final items = await repo.enqueue(inputs(4), _recipe);
      await repo.move(items[3].id, 0);
      await repo.move(items[0].id, 10);
      expect((await repo.all()).map((i) => i.inputPath), [
        'inbox/3.jpg',
        'inbox/1.jpg',
        'inbox/2.jpg',
        'inbox/0.jpg',
      ]);
    });

    test('removal returns the files only it referred to', () async {
      final items = await repo.enqueue(inputs(2), _recipe);
      final r = await repo.remove([items[0].id]);
      expect(r.jobIds, {items[0].jobId});
      expect(r.inputs, {'inbox/0.jpg'});
      expect((await repo.all()).single.id, items[1].id);
      expect(await db.select(db.recipes).get(), hasLength(1), reason: 'still used by item 1');
      await repo.remove([items[1].id]);
      expect(await db.select(db.recipes).get(), isEmpty);
      expect(await db.select(db.assets).get(), isEmpty);
    });

    test('a job the history refers to keeps its directory and input', () async {
      final item = (await repo.enqueue(['inbox/a.jpg'], _recipe)).single;
      await repo.setSourceSize(item.id, 40, 30);
      await HistoryRepository(db).add(
        HistoryEntry(
          id: 'h1',
          createdAt: DateTime(2026),
          recipe: _autosave,
          inputPath: 'inbox/a.jpg',
          sourceWidth: 40,
          sourceHeight: 30,
          width: 80,
          height: 60,
          previewPath: 'history/h1.jpg',
          resultUri: 'content://r',
          modelIds: ['sr.m'],
          backend: 'cpu',
          duration: null,
          jobId: item.jobId,
        ),
      );
      final r = await repo.remove([item.id]);
      expect(r.jobIds, isEmpty);
      expect(r.inputs, isEmpty);
      expect((await HistoryRepository(db).get('h1'))!.sourceWidth, 40);
    });

    test('history removal keeps a directory a queue job still uses', () async {
      final item = (await repo.enqueue(['inbox/a.jpg'], _recipe)).single;
      final history = HistoryRepository(db);
      await history.add(
        HistoryEntry(
          id: 'h1',
          createdAt: DateTime(2026),
          recipe: _autosave,
          inputPath: 'inbox/a.jpg',
          sourceWidth: 40,
          sourceHeight: 30,
          width: 80,
          height: 60,
          previewPath: 'history/h1.jpg',
          resultUri: 'content://r',
          modelIds: ['sr.m'],
          backend: 'cpu',
          duration: null,
          jobId: item.jobId,
        ),
      );
      final a = await (db.select(db.assets)).getSingle();
      expect((a.width, a.height), (40, 30), reason: 'the entry fills the size of a queued photo');
      final r = await history.remove('h1');
      expect(r.jobIds, isEmpty);
      expect(r.inputs, isEmpty);
    });

    test('recover pauses jobs of a process that is gone (FR-BATCH-007)', () async {
      final items = await repo.enqueue(inputs(2), _recipe);
      await repo.setState(items[0].id, QueueState.running, progress: 0.3);
      expect(await repo.recover(), 1);
      final s = await states();
      expect(s, {'inbox/0.jpg': QueueState.paused, 'inbox/1.jpg': QueueState.queued});
      expect((await repo.get(items[0].id))!.progress, 0.3);
    });

    test('old jobs are removed after 7 days, a running one never', () async {
      final now = DateTime(2026, 10, 15);
      final items = await repo.enqueue(inputs(3), _recipe, now: now);
      await repo.setState(items[0].id, QueueState.running, now: now);
      final r = await repo.removeOlderThan(
        const Duration(days: 7),
        now: now.add(const Duration(days: 8)),
      );
      expect(r.inputs, {'inbox/1.jpg', 'inbox/2.jpg'});
      expect((await repo.all()).single.id, items[0].id);
    });

    test('references list what the startup sweep keeps', () async {
      final items = await repo.enqueue(inputs(2), _recipe);
      final refs = await repo.references();
      expect(refs.jobIds, {for (final i in items) i.jobId});
      expect(refs.inputs, inputs(2).toSet());
    });
  });

  group('orchestrator', () {
    test(
      'runs everything in order; a failure does not stop it; the report counts (FR-BATCH-008)',
      () async {
        await repo.enqueue(inputs(2), _autosave);
        await repo.enqueue(['inbox/bad.jpg', 'inbox/bug.jpg', 'inbox/keep.jpg'], _recipe);
        runner.outcomes['inbox/bad.jpg'] = const JobFailed('invalid');
        runner.throwFor.add('inbox/bug.jpg');
        final reports = queue.status.where((s) => s.report != null).first;
        await queue.start();
        expect(runner.ran, [...inputs(2), 'inbox/bad.jpg', 'inbox/bug.jpg', 'inbox/keep.jpg']);
        expect(await states(), {
          'inbox/0.jpg': QueueState.saved,
          'inbox/1.jpg': QueueState.saved,
          'inbox/bad.jpg': QueueState.failed,
          'inbox/bug.jpg': QueueState.failed,
          'inbox/keep.jpg': QueueState.done,
        });
        final failed = {for (final i in await repo.all()) i.inputPath: i.errorCode};
        expect(failed['inbox/bad.jpg'], 'invalid');
        expect(failed['inbox/bug.jpg'], 'internal');
        expect(errors, hasLength(1));
        final report = (await reports).report!;
        expect((report.finished, report.failed, report.pending), (3, 2, 0));
        expect(queue.running, isFalse);
      },
    );

    test(
      'pause stops at the checkpoint; start continues paused and queued jobs (FR-BATCH-003)',
      () async {
        await repo.enqueue(inputs(3), _recipe);
        runner.gate = Completer();
        final running = queue.status.firstWhere((s) => s.currentId != null);
        final run = queue.start();
        await running;
        queue.pause();
        runner.gate!.complete();
        await run;
        expect(queue.current.report, isNull, reason: 'not drained');
        expect(await states(), {
          'inbox/0.jpg': QueueState.paused,
          'inbox/1.jpg': QueueState.queued,
          'inbox/2.jpg': QueueState.queued,
        });
        expect((await repo.all()).first.progress, 0.5);

        runner
          ..gate = null
          ..paused = false
          ..ran.clear();
        await queue.start();
        expect(runner.ran, inputs(3), reason: 'the paused job first, from its checkpoint');
        expect((await states()).values.toSet(), {QueueState.done});
      },
    );

    test('cancel fails the current job and stops the queue', () async {
      await repo.enqueue(inputs(2), _recipe);
      runner.gate = Completer();
      final running = queue.status.firstWhere((s) => s.currentId != null);
      final run = queue.start();
      await running;
      queue.cancelCurrent();
      runner.gate!.complete();
      await run;
      final items = await repo.all();
      expect((items[0].state, items[0].errorCode), (QueueState.failed, JobFailed.cancelled));
      expect(items[1].state, QueueState.queued);
    });

    test('the running job cannot be removed', () async {
      final items = await repo.enqueue(inputs(2), _recipe);
      runner.gate = Completer();
      final running = queue.status.firstWhere((s) => s.currentId != null);
      final run = queue.start();
      await running;
      await queue.remove([for (final i in items) i.id]);
      runner.gate!.complete();
      await run;
      expect((await repo.all()).single.id, items[0].id);
    });
  });
}
