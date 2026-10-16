import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import 'app_log.dart';
import 'database.dart';
import 'engine.dart';
import 'foreground.dart';
import 'job_store.dart';
import 'processing.dart';
import 'result_saver.dart';
import 'settings.dart';

/// Runs one queue job on the native core: start or resume, answer NEEDS_USER, save when the
/// batch asked for it (FR-BATCH-006).
class EngineQueueRunner implements QueueJobRunner {
  EngineQueueRunner(this._ref);

  final Ref _ref;
  RefocalJob? _job;

  @override
  Future<QueueOutcome> run(QueueItem item, void Function(double) onProgress) async {
    final engine = await _ref.read(engineProvider.future);
    final jobs = await _ref.read(jobStoreProvider.future);
    final input = '${engine.dirs.support}/${item.inputPath}';
    final dir = jobs.dirOf(item.jobId);
    JobResult result;
    if (await File('$dir/result.json').exists()) {
      // Finished in a process that was killed before the queue recorded it.
      result = JobResult.fromJson(
        (jsonDecode(await File('$dir/result.json').readAsString()) as Map).cast(),
      );
    } else {
      final (processed, stopped) = await _process(engine, item, input, dir, onProgress);
      if (stopped != null) return stopped;
      result = processed!;
    }
    final finished = JobFinished(
      saved: false,
      sourceWidth: result.inputWidth,
      sourceHeight: result.inputHeight,
    );
    final output = item.recipe.output;
    if (output == null) return finished;
    try {
      final saver = await readResultSaver(_ref);
      await saver.save(
        result,
        input: input,
        output: output,
        strength: item.recipe.strength,
        to: Destination.gallery,
      );
    } on HistoryNotRecorded catch (e) {
      AppLog.warn('queue: saved, history not recorded: ${e.cause.runtimeType}');
    } on Exception catch (e, stack) {
      // Processed but not saved: the result waits in the queue for the user (state done).
      AppLog.error('queue: autosave failed', e, stack);
      return finished;
    }
    try {
      await jobs.discard(dir);
    } on FileSystemException catch (e) {
      AppLog.warn('queue: discard saved job: ${e.message}'); // the startup sweep removes it
    }
    return JobFinished(
      saved: true,
      sourceWidth: result.inputWidth,
      sourceHeight: result.inputHeight,
    );
  }

  /// The result, or (exactly one of the two) the outcome the job stopped with.
  Future<(JobResult?, QueueOutcome?)> _process(
    Engine engine,
    QueueItem item,
    String input,
    String dir,
    void Function(double) onProgress,
  ) async {
    final RefocalJob job;
    try {
      job = await File('$dir/request.json').exists()
          ? engine.session.resume(dir) // paused or interrupted: from the checkpoint
          : engine.session.start(JobRequest.of(item.recipe, input, id: item.jobId).toJson());
    } on EnhException catch (e) {
      AppLog.warn('queue: job not started: ${e.status.name}');
      return (null, JobFailed(e.status.name));
    }
    _job = job;
    AppLog.info('queue job ${item.jobId}: scale ${item.recipe.scale}');
    var progress = item.progress;
    var outOfMemory = false;
    final events = job.events.listen((e) {
      switch (e) {
        case ProgressEvent():
          progress = e.fraction;
          onProgress(progress);
        case NeedsUserEvent(code: 'oom_downscale'):
          // FR-ENH-014: never a smaller scale without the user; the item fails with "out of
          // memory" and can be retried from the editor.
          AppLog.warn('queue: out of memory at the smallest tile');
          outOfMemory = true;
          job.cancel();
        case NeedsUserEvent(:final code, :final options):
          // Nobody to ask in a batch: the largest scale that fits (the core lists them in
          // descending order, FR-IMP-006).
          if (options.isEmpty) {
            job.cancel();
          } else {
            AppLog.info('queue: $code, answered ${options.first}');
            job.answer(options.first);
          }
        case FallbackEvent():
          AppLog.warn('fallback ${e.kind.name} ${e.from} -> ${e.to} (${e.reason})');
        case WarningEvent(code: final c) when c.startsWith('thermal_'):
          AppLog.info('queue: $c');
        default:
      }
    });
    try {
      return (await job.done, null);
    } on JobFailure catch (f) {
      AppLog.info('queue job ended: ${f.status.name}');
      return (
        null,
        switch (f.status) {
          EnhStatus.paused => JobPaused(progress),
          EnhStatus.cancelled when outOfMemory => JobFailed(EnhStatus.oom.name),
          EnhStatus.cancelled => const JobFailed(JobFailed.cancelled),
          final s => JobFailed(s.name),
        },
      );
    } finally {
      await events.cancel();
      _job = null;
    }
  }

  @override
  void pause() => _job?.pause();

  @override
  void cancel() => _job?.cancel();
}

final queueRepositoryProvider = FutureProvider<QueueRepository>(
  (ref) async => QueueRepository(await ref.watch(databaseProvider.future)),
);

/// Jobs and inbox copies under AppSupport (07 §2); an inbox copy the queue still needs is
/// never released.
final jobStoreProvider = FutureProvider<JobStore>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final queue = await ref.watch(queueRepositoryProvider.future);
  return JobStore(
    jobsDir: '${dirs.support}/jobs',
    inboxDir: '${dirs.support}/inbox',
    otherInputs: () async => {
      for (final i in (await queue.references()).inputs) '${dirs.support}/$i',
    },
  );
});

/// The batch queue of the app (FR-BATCH-001..008): the orchestrator plus what it needs from
/// the platform (the foreground service, notification actions) and the files of removed jobs.
class QueueService {
  QueueService(this._ref, this.repo, this._engine, this._jobs)
    : orchestrator = QueueOrchestrator(
        repo,
        EngineQueueRunner(_ref),
        onError: (e, stack) => AppLog.error('queue runner', e, stack),
      );

  final Ref _ref;
  final QueueRepository repo;
  final Engine _engine;
  final JobStore _jobs;
  final QueueOrchestrator orchestrator;

  /// Adds photos (absolute inbox paths) with one recipe (FR-BATCH-002).
  Future<void> enqueue(List<String> inputs, Recipe recipe) async {
    final support = _engine.dirs.support;
    await repo.enqueue([for (final i in inputs) i.substring(support.length + 1)], recipe);
    AppLog.info('queue: ${inputs.length} added');
  }

  /// Runs the queue in the foreground service until it is empty or paused. Call from a user
  /// action (Android starts a foreground service only from the foreground, ADR-0019).
  Future<void> start() async {
    if (orchestrator.running) return;
    final fg = _ref.read(foregroundWorkProvider);
    await fg.acquire(this);
    final actions = _ref.read(processingActionsProvider).listen((a) {
      switch (a) {
        case 'pause' || 'timeout':
          orchestrator.pause();
        case 'cancel':
          orchestrator.cancelCurrent();
      }
    });
    var lastPercent = -2;
    var position = '';
    final status = orchestrator.status.listen((s) async {
      if (s.currentId == null) return;
      final pct = (s.progress * 100).floor();
      if (pct == lastPercent) return;
      if (lastPercent < 0 || pct < lastPercent) {
        final sum = await repo.summary();
        position = _ref
            .read(l10nProvider)
            .queueNotifPosition(sum.finished + sum.failed + 1, sum.total);
      }
      lastPercent = pct;
      await fg.update(this, '$position · $pct%', pct);
    });
    try {
      await orchestrator.start();
    } finally {
      await status.cancel();
      await actions.cancel();
      final report = orchestrator.current.report;
      final l10n = _ref.read(l10nProvider);
      await fg.release(
        this,
        report == null ? null : l10n.queueNotifDone(report.finished, report.failed),
      );
    }
  }

  void pause() => orchestrator.pause();

  /// Removes jobs and their files (the running one stays, FR-BATCH-001).
  Future<void> remove(Iterable<String> ids) async => _deleteFiles(await orchestrator.remove(ids));

  /// "Clear finished": saved and failed jobs.
  Future<void> clearFinished() async => _deleteFiles(await repo.removeFinished());

  /// A done job whose result the user saved from the editor (its directory is gone then).
  Future<void> refresh(QueueItem item) async {
    if (item.state != QueueState.done) return;
    if (!await Directory(_jobs.dirOf(item.jobId)).exists()) {
      await repo.setState(item.id, QueueState.saved);
    }
  }

  Future<void> _deleteFiles(QueueRemoval r) async {
    final jobs = _jobs;
    for (final id in r.jobIds) {
      await _bestEffort(() => jobs.discard(jobs.dirOf(id)));
    }
    for (final input in r.inputs) {
      await _bestEffort(() => jobs.releaseInput('${_engine.dirs.support}/$input'));
    }
  }

  static Future<void> _bestEffort(Future<void> Function() f) async {
    try {
      await f();
    } on FileSystemException catch (e) {
      AppLog.warn('queue cleanup: ${e.message}'); // the startup sweep removes it
    }
  }
}

final queueServiceProvider = FutureProvider<QueueService>((ref) async {
  final service = QueueService(
    ref,
    await ref.watch(queueRepositoryProvider.future),
    await ref.watch(engineProvider.future),
    await ref.watch(jobStoreProvider.future),
  );
  ref.onDispose(service.orchestrator.dispose);
  return service;
});

/// In processing order.
final queueItemsProvider = StreamProvider<List<QueueItem>>((ref) async* {
  final repo = await ref.watch(queueRepositoryProvider.future);
  yield* repo.watchAll();
});

final queueStatusProvider = StreamProvider<QueueStatus>((ref) async* {
  final service = await ref.watch(queueServiceProvider.future);
  yield service.orchestrator.current;
  yield* service.orchestrator.status;
});

/// Once per process, before any screen takes a photo: the queue jobs of a process that is gone
/// are paused (FR-BATCH-007), queue jobs older than 7 days are removed, then jobs/ and inbox/
/// are swept, sparing what the queue still refers to (07 §1).
final startupProvider = FutureProvider<Engine>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  final service = await ref.watch(queueServiceProvider.future);
  final repo = service.repo;
  final recovered = await repo.recover();
  if (recovered > 0) AppLog.info('queue: $recovered interrupted, paused');
  await service._deleteFiles(await repo.removeOlderThan(JobStore.maxAge));
  final refs = await repo.references();
  try {
    await service._jobs.sweep(
      keepJobs: refs.jobIds,
      keepInputs: {for (final i in refs.inputs) '${engine.dirs.support}/$i'},
    );
  } on FileSystemException catch (e) {
    AppLog.warn('startup sweep: ${e.message}'); // retried at the next start
  }
  return engine;
});

/// Unfinished and unsaved jobs of the editor for the home screen (queue jobs are listed in the
/// queue); invalidate after a change.
final jobListProvider = FutureProvider<List<JobEntry>>((ref) async {
  await ref.watch(startupProvider.future); // after the sweep
  final queued = (await (await ref.watch(queueRepositoryProvider.future)).references()).jobIds;
  return [
    for (final j in await (await ref.watch(jobStoreProvider.future)).list())
      if (!queued.contains(j.id)) j,
  ];
});
