import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/engine.dart';
import '../../bootstrap/processing.dart';
import '../../bootstrap/settings.dart';

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

/// Stopped at a band boundary; continues from [jobDir] (checkpoint, ADR-0004).
class Paused extends EnhanceState {
  const Paused(this.jobDir, this.progress, {this.byTimeout = false});
  final String jobDir;
  final double progress;
  final bool byTimeout;
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
  StreamSubscription<String>? _actions;
  Engine? _engine;
  String? _input;
  bool _timedOut = false;

  @override
  EnhanceState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _actions?.cancel();
      _job?.cancel();
      _cleanup();
    });
    return const Idle();
  }

  /// Files this screen leaves behind: a saved result's BandStore, and the inbox copy once no
  /// job refers to it (ADR-0010). Unsaved and paused jobs stay for the home screen list.
  void _cleanup() {
    final engine = _engine, input = _input;
    if (engine == null) return;
    try {
      final s = state;
      if (s is Finished && s.savedUri != null) engine.jobs.discard(s.result.jobDir);
      if (input != null) engine.jobs.releaseInput(input);
    } on FileSystemException {
      // best effort; the startup sweep catches the rest
    }
  }

  Future<void> start(String input, ScaleChoice choice) async {
    final id = 'job-${DateTime.now().millisecondsSinceEpoch}';
    await _run(
      input,
      (e) => e.session.start({
        'job_id': id,
        'input': input,
        'sr_model': bundledSrModel,
        'scale': choice.scale,
        'fast2': choice.fastPath,
      }),
    );
  }

  /// Continues a paused or interrupted job (FR-BATCH-007, TEST-INT-003).
  Future<void> resume(String jobDir, String input) => _run(input, (e) => e.session.resume(jobDir));

  /// Shows a job that finished earlier but was not saved.
  Future<void> open(String jobDir, String input) async {
    _engine = await ref.read(engineProvider.future);
    _input = input;
    try {
      final raw = await File('$jobDir/result.json').readAsString();
      state = Finished(JobResult.fromJson(_decode(raw)));
    } on Object catch (e) {
      state = Failed(EnhStatus.io, '$e');
    }
  }

  Future<void> _run(String input, RefocalJob Function(Engine) create) async {
    final engine = await ref.read(engineProvider.future);
    _engine = engine;
    _input = input;
    _timedOut = false;
    final platform = ref.read(platformApiProvider);
    state = const Running(JobStage.queued, 0, null);
    await _guard(platform.requestNotificationPermission);
    await _guard(() => platform.startProcessing('Enhancing a photo'));
    var lastPercent = -2;
    try {
      final job = _job = create(engine);
      _actions = ref.read(processingActionsProvider).listen((a) {
        if (a == 'cancel') job.cancel();
        if (a == 'pause' || a == 'timeout') {
          _timedOut = a == 'timeout';
          job.pause();
        }
      });
      String? note;
      var stage = JobStage.queued;
      var progress = 0.0;
      _sub = job.events.listen((e) {
        switch (e) {
          case StageEvent(stage: final st):
            stage = st;
            state = Running(stage, progress, null, note: note);
          case ProgressEvent():
            progress = e.fraction;
            state = Running(stage, progress, e.eta, note: note);
            final pct = (progress * 100).floor();
            if (pct != lastPercent) {
              lastPercent = pct;
              _guard(() => platform.updateProcessing('$pct%', pct));
            }
          case FallbackEvent():
            note = 'Switched to ${e.to}';
          case WarningEvent(code: 'alpha_flattened'):
            note = 'Transparent areas become white';
          case WarningEvent(code: 'animation_first_frame'):
            note = 'Only the first frame of the animation is enhanced';
          case NeedsUserEvent():
            state = AskUser(e);
          default:
        }
      });
      final result = await job.done;
      state = Finished(result);
      await _guard(() => platform.stopProcessing('Photo ready. Tap to open.'));
    } on JobFailure catch (f) {
      final dir = f.event.jobDir;
      if (f.status == EnhStatus.paused && dir != null) {
        state = Paused(dir, _progressOf(state), byTimeout: _timedOut);
      } else {
        state = Failed(f.status, f.event.message);
      }
      // A timeout already left its own "tap to continue" notification.
      final text = switch (f.status) {
        EnhStatus.cancelled || EnhStatus.paused => null,
        _ => 'Enhancement failed. Tap to open.',
      };
      await _guard(() => platform.stopProcessing(text));
    } on EnhException catch (e) {
      state = Failed(e.status, e.context);
      await _guard(() => platform.stopProcessing(null));
    } finally {
      await _sub?.cancel();
      await _actions?.cancel();
      _sub = null;
      _actions = null;
      _job = null;
    }
  }

  static double _progressOf(EnhanceState s) => s is Running ? s.progress : 0;

  static Map<String, Object?> _decode(String raw) =>
      (jsonDecode(raw) as Map).cast<String, Object?>();

  /// Platform calls are conveniences (notification, FGS): processing never depends on them.
  static Future<void> _guard(FutureOr<Object?> Function() f) async {
    try {
      await f();
    } on Object {
      // e.g. ForegroundServiceStartNotAllowedException, no activity for the permission dialog
    }
  }

  void answer(Map<String, Object?> option) {
    _job?.answer(option);
    state = const Running(JobStage.decode, 0, null);
  }

  void cancel() => _job?.cancel();

  void pause() => _job?.pause();

  Future<void> save() async {
    final s = state;
    if (s is! Finished) return;
    final engine = await ref.read(engineProvider.future);
    final settings = await ref.read(settingsProvider.future);
    Directory(engine.exportDir).createSync(recursive: true);
    final name = 'Refocal_${s.result.jobId}.jpg';
    final tmp = '${engine.exportDir}/$name';
    try {
      await engine.session.export(
        s.result.jobDir,
        tmp,
        keepGps: settings.keepGps,
        aiMarker: settings.aiMarker,
      );
      final uri = await ref.read(platformApiProvider).saveToGallery(tmp, name, 'image/jpeg');
      state = Finished(s.result, savedUri: uri);
    } finally {
      final f = File(tmp);
      if (f.existsSync()) f.deleteSync();
    }
  }

  void reset() {
    final s = state;
    if (s is Finished && s.savedUri != null) {
      try {
        _engine?.jobs.discard(s.result.jobDir, inUse: {?_input});
      } on FileSystemException {
        // best effort
      }
    }
    state = const Idle();
  }
}

final enhanceProvider = NotifierProvider.autoDispose<EnhanceController, EnhanceState>(
  EnhanceController.new,
);
