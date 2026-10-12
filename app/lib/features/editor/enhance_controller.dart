import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/engine.dart';

/// Output scale choices (ADR-0014). Fast 2x runs x4 on a half-size input: 4x cheaper.
enum ScaleChoice {
  x4(4, false, '4×'),
  x2(2, false, '2×'),
  fast2(2, true, 'Fast 2×');

  const ScaleChoice(this.scale, this.fastPath, this.label);
  final int scale;
  final bool fastPath;
  final String label;
}

sealed class EnhanceState {
  const EnhanceState();
}

class Idle extends EnhanceState {
  const Idle();
}

class Running extends EnhanceState {
  const Running(this.stage, this.progress, this.eta, {this.note});
  final JobStage stage;
  final double progress;
  final Duration? eta;
  final String? note;
}

class AskUser extends EnhanceState {
  const AskUser(this.event);
  final NeedsUserEvent event;
}

class Finished extends EnhanceState {
  const Finished(this.result, {this.savedUri});
  final JobResult result;
  final String? savedUri;
}

class Failed extends EnhanceState {
  const Failed(this.status, this.message);
  final EnhStatus status;
  final String? message;
}

class EnhanceController extends Notifier<EnhanceState> {
  RefocalJob? _job;
  StreamSubscription<JobEvent>? _sub;

  @override
  EnhanceState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _job?.cancel();
    });
    return const Idle();
  }

  Future<void> start(String input, ScaleChoice choice) async {
    final engine = await ref.read(engineProvider.future);
    final id = 'job-${DateTime.now().millisecondsSinceEpoch}';
    state = const Running(JobStage.queued, 0, null);
    try {
      final job = engine.session.start({
        'job_id': id,
        'input': input,
        'sr_model': bundledSrModel,
        'scale': choice.scale,
        'fast2': choice.fastPath,
      });
      _job = job;
      String? note;
      JobStage stage = JobStage.queued;
      _sub = job.events.listen((e) {
        switch (e) {
          case StageEvent(stage: final st):
            stage = st;
            state = Running(stage, 0, null, note: note);
          case ProgressEvent():
            state = Running(stage, e.fraction, e.eta, note: note);
          case FallbackEvent():
            note = 'Switched to ${e.to}';
          case NeedsUserEvent():
            state = AskUser(e);
          default:
        }
      });
      state = Finished(await job.done);
    } on JobFailure catch (f) {
      state = Failed(f.status, f.event.message);
    } on EnhException catch (e) {
      state = Failed(e.status, e.context);
    } finally {
      await _sub?.cancel();
      _sub = null;
      _job = null;
    }
  }

  void answer(Map<String, Object?> option) {
    _job?.answer(option);
    state = const Running(JobStage.decode, 0, null);
  }

  void cancel() => _job?.cancel();

  Future<void> save() async {
    final s = state;
    if (s is! Finished) return;
    final engine = await ref.read(engineProvider.future);
    Directory(engine.exportDir).createSync(recursive: true);
    final name = 'Refocal_${s.result.jobId}.jpg';
    final tmp = '${engine.exportDir}/$name';
    try {
      await engine.session.export(s.result.jobDir, tmp);
      final uri = await ref.read(platformApiProvider).saveToGallery(tmp, name, 'image/jpeg');
      state = Finished(s.result, savedUri: uri);
    } finally {
      final f = File(tmp);
      if (f.existsSync()) f.deleteSync();
    }
  }

  void reset() => state = const Idle();
}

final enhanceProvider = NotifierProvider.autoDispose<EnhanceController, EnhanceState>(
  EnhanceController.new,
);
