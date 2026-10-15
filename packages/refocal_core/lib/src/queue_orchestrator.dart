import 'dart:async';

import 'db/queue_repository.dart';
import 'db/tables.dart';

/// How running one queue job ended.
sealed class QueueOutcome {
  const QueueOutcome();
}

/// The result is in the job directory, or [saved] (FR-BATCH-006) and the directory is gone.
class JobFinished extends QueueOutcome {
  const JobFinished({required this.saved, required this.sourceWidth, required this.sourceHeight});
  final bool saved;
  final int sourceWidth, sourceHeight;
}

/// Stopped at a band boundary (pause, FGS time limit); continues from the checkpoint.
class JobPaused extends QueueOutcome {
  const JobPaused(this.progress);
  final double progress;
}

/// [code]: an `EnhStatus` name, "cancelled", or "internal" for an exception of the runner.
class JobFailed extends QueueOutcome {
  const JobFailed(this.code);
  final String code;

  static const cancelled = 'cancelled';
}

/// Runs one queue job on the native core (the app's side: session, export, history).
abstract interface class QueueJobRunner {
  /// Starts [item], or continues it from its checkpoint when its job directory has one.
  /// Saves the result when [QueueItem.autosave]. [onProgress]: 0..1.
  Future<QueueOutcome> run(QueueItem item, void Function(double progress) onProgress);

  /// Stop the running job at the next band boundary (it completes with [JobPaused]).
  void pause();

  /// Stop the running job now (it completes with [JobFailed.cancelled]).
  void cancel();
}

/// What the orchestrator is doing.
class QueueStatus {
  const QueueStatus({this.running = false, this.currentId, this.progress = 0, this.report});

  final bool running;

  /// The job the core works on.
  final String? currentId;
  final double progress;

  /// Set when the queue ran dry: "done N, failed M" over the whole queue (FR-BATCH-008).
  final QueueSummary? report;
}

/// Runs the queue one job at a time (03 §5: one GPU job; the core serializes as well). A failed
/// job does not stop the queue (FR-BATCH-008); pause stops it at the current job's checkpoint
/// (FR-BATCH-003), and state lives in `queue_jobs`, so it survives a restart (FR-BATCH-007).
class QueueOrchestrator {
  QueueOrchestrator(this._repo, this._runner, {this.onError});

  final QueueRepository _repo;
  final QueueJobRunner _runner;

  /// An exception of the runner; the job is failed with "internal" and the queue goes on.
  final void Function(Object error, StackTrace stack)? onError;

  final _status = StreamController<QueueStatus>.broadcast();
  QueueStatus _current = const QueueStatus();
  Future<void>? _loop;
  bool _stop = false;

  Stream<QueueStatus> get status => _status.stream;
  QueueStatus get current => _current;
  bool get running => _loop != null;

  /// Runs queued and paused jobs in order until none is left or [pause] (FR-BATCH-003).
  /// Returns when the run ends. Calling it while running joins the current run.
  Future<void> start() {
    if (_loop case final l?) return l;
    _stop = false;
    return _loop = _run().whenComplete(() => _loop = null);
  }

  /// The running job stops at its checkpoint and the queue stops after it.
  void pause() {
    if (!running) return;
    _stop = true;
    _runner.pause();
  }

  /// The running job is cancelled (failed "cancelled") and the queue stops.
  void cancelCurrent() {
    if (!running) return;
    _stop = true;
    _runner.cancel();
  }

  /// Removes jobs; the running one is not removed (pause or cancel it first).
  Future<QueueRemoval> remove(Iterable<String> ids) =>
      _repo.remove(ids.where((id) => id != _current.currentId));

  Future<void> _run() async {
    await _repo.requeuePaused();
    var drained = false;
    _emit(const QueueStatus(running: true));
    while (!_stop) {
      final item = await _repo.first({QueueState.queued});
      if (item == null) {
        drained = true;
        break;
      }
      await _repo.setState(item.id, QueueState.running);
      var stored = item.progress;
      _emit(QueueStatus(running: true, currentId: item.id, progress: item.progress));
      QueueOutcome outcome;
      try {
        outcome = await _runner.run(item, (p) {
          _emit(QueueStatus(running: true, currentId: item.id, progress: p));
          if ((p - stored).abs() >= 0.05) {
            stored = p;
            unawaited(_repo.setProgress(item.id, p));
          }
        });
      } catch (e, stack) {
        onError?.call(e, stack);
        outcome = const JobFailed('internal');
      }
      switch (outcome) {
        case JobFinished(:final saved, :final sourceWidth, :final sourceHeight):
          await _repo.setSourceSize(item.id, sourceWidth, sourceHeight);
          await _repo.setState(item.id, saved ? QueueState.saved : QueueState.done, progress: 1);
        case JobPaused(:final progress):
          await _repo.setState(item.id, QueueState.paused, progress: progress);
          _stop = true; // a pause or the FGS time limit: the rest waits as well
        case JobFailed(:final code):
          await _repo.setState(item.id, QueueState.failed, errorCode: code);
      }
    }
    _emit(QueueStatus(report: drained ? await _repo.summary() : null));
  }

  void _emit(QueueStatus s) {
    _current = s;
    _status.add(s);
  }

  Future<void> dispose() async {
    pause();
    await _loop;
    await _status.close();
  }
}
