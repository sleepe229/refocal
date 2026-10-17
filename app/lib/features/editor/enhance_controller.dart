import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/foreground.dart';
import '../../bootstrap/job_store.dart';
import '../../bootstrap/processing.dart';
import '../../bootstrap/queue.dart';
import '../../bootstrap/result_saver.dart';
import '../../bootstrap/settings.dart';

/// Output scale choices (ADR-0014). Fast 2x runs x4 on a half-size input: 4x cheaper; 1x runs
/// x4 and scales back down: noise and blur removal without enlarging (FR-ENH-004).
enum ScaleChoice {
  x8(8, false),
  x4(4, false),
  x2(2, false),
  fast2(2, true),
  x1(1, false);

  const ScaleChoice(this.scale, this.fastPath);
  final int scale;
  final bool fastPath;

  static ScaleChoice of(Recipe r) =>
      values.firstWhere((c) => c.scale == r.scale && c.fastPath == r.fast2);
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
  const Finished(this.result, {this.strength = 1, this.saved = false, this.saving = false});
  final JobResult result;

  /// FR-ENH-005: blend with the original, applied at export (ADR-0012 amendment).
  final double strength;

  /// Exported at least once: the job is deleted when the editor closes (ADR-0010).
  final bool saved;
  final bool saving;

  Finished copyWith({double? strength, bool? saved, bool? saving}) => Finished(
    result,
    strength: strength ?? this.strength,
    saved: saved ?? this.saved,
    saving: saving ?? this.saving,
  );
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
  JobStore? _jobs;
  String? _input;
  bool _timedOut = false;

  /// The state as of the last change: onDispose may not read [state] (Riverpod 3).
  EnhanceState _last = const Idle();

  /// Strength the result starts with (a preset's, FR-PRE-002; else 100%).
  double _strength = 1;

  @override
  EnhanceState build() {
    listenSelf((_, next) => _last = next);
    ref.onDispose(() {
      _sub?.cancel();
      _actions?.cancel();
      _job?.cancel();
      _cleanup();
    });
    return const Idle();
  }

  /// Files this screen leaves behind: a saved result's BandStore, and the inbox copy once no
  /// job refers to it (ADR-0010). Unsaved and paused jobs stay for the home screen list. Runs
  /// after the screen is gone: a failure is logged and the startup sweep catches the rest.
  void _cleanup() {
    final jobs = _jobs, input = _input, s = _last;
    if (jobs == null) return;
    unawaited(() async {
      try {
        if (s is Finished && s.saved) await jobs.discard(s.result.jobDir);
        if (input != null) await jobs.releaseInput(input);
      } on FileSystemException catch (e) {
        AppLog.warn('editor cleanup: ${e.message}');
      }
    }());
  }

  /// Runs [recipe] on [input]; the result starts at the recipe's strength (a preset's or a
  /// history entry's, FR-PRE-002, FR-HIST-003). [facesOff]: faces of this photo not to restore
  /// (FR-FACE-007).
  Future<void> start(String input, Recipe recipe, {List<FaceBox> facesOff = const []}) async {
    _strength = recipe.strength;
    final request = JobRequest.of(recipe, input, facesOff: facesOff);
    AppLog.info(
      'job ${request.id}: ${request.srModel} scale ${request.scale}${request.fast2 ? ' fast' : ''}',
    );
    await _run(input, (e) => e.session.start(request.toJson()));
  }

  /// Continues a paused or interrupted job (FR-BATCH-007, TEST-INT-003).
  Future<void> resume(String jobDir, String input) {
    AppLog.info('job resume');
    return _run(input, (e) => e.session.resume(jobDir));
  }

  /// Shows a job that finished earlier but was not saved.
  Future<void> open(String jobDir, String input) async {
    _jobs = await ref.read(jobStoreProvider.future);
    _input = input;
    try {
      final raw = await File('$jobDir/result.json').readAsString();
      state = Finished(JobResult.fromJson(_decode(raw)));
    } on FileSystemException catch (e) {
      AppLog.warn('open result: ${e.message}');
      state = const Failed(EnhStatus.io, null);
    } on FormatException catch (e) {
      AppLog.warn('open result: ${e.message}');
      state = const Failed(EnhStatus.invalid, null);
    }
  }

  Future<void> _run(String input, RefocalJob Function(Engine) create) async {
    final engine = await ref.read(engineProvider.future);
    _jobs = await ref.read(jobStoreProvider.future);
    _input = input;
    _timedOut = false;
    final fg = ref.read(foregroundWorkProvider);
    final l10n = ref.read(l10nProvider);
    state = const Running(JobStage.queued, 0, null);
    await fg.acquire(this);
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
              fg.update(this, '$pct%', pct);
            }
          case FallbackEvent():
            AppLog.warn('fallback ${e.kind.name} ${e.from} -> ${e.to} (${e.reason})');
            // FR-ENH-013: every rung of the ladder is visible.
            note = switch (e) {
              FallbackEvent(kind: FallbackKind.tile) => l10n.noteTileSmaller,
              FallbackEvent(kind: FallbackKind.face, faceIndex: final i?) => l10n.noteFaceSkipped(
                i + 1,
              ),
              FallbackEvent(kind: FallbackKind.face) => l10n.noteFacesSkipped,
              FallbackEvent(kind: FallbackKind.jpeg) => l10n.noteJpegSkipped,
              FallbackEvent(kind: FallbackKind.scratches) => l10n.noteScratchesSkipped,
              FallbackEvent(kind: FallbackKind.lowlight) => l10n.noteLowLightSkipped,
              FallbackEvent(kind: FallbackKind.backend) => l10n.noteSwitchedTo(e.to),
            };
            state = Running(stage, progress, null, note: note);
          case WarningEvent(code: 'alpha_kept'):
            note = l10n.noteAlphaKept;
          case WarningEvent(code: 'animation_first_frame'):
            note = l10n.noteFirstFrame;
          case WarningEvent(code: 'thermal_wait'):
            AppLog.info('thermal: waiting');
            note = l10n.noteThermalWait;
            state = Running(stage, progress, null, note: note);
          case WarningEvent(code: 'thermal_resumed'):
            note = null;
            state = Running(stage, progress, null);
          case WarningEvent(code: 'thermal_throttle'):
            AppLog.info('thermal: throttled');
            note = l10n.noteThermalThrottle;
          case NeedsUserEvent():
            state = AskUser(e);
          default:
        }
      });
      final result = await job.done;
      AppLog.info(
        'job done: ${result.width}x${result.height}, backend ${result.backend}, '
        'fallbacks ${result.fallbacks}, timings ${result.raw['timings_ms']}',
      );
      state = Finished(result, strength: _strength);
      await fg.release(this, l10n.notifReady);
    } on JobFailure catch (f) {
      AppLog.info(
        'job ended: ${f.status.name}${f.event.message == null ? '' : ': ${f.event.message}'}',
      );
      final dir = f.event.jobDir;
      if (f.status == EnhStatus.paused && dir != null) {
        state = Paused(dir, _progressOf(state), byTimeout: _timedOut);
      } else {
        state = Failed(f.status, f.event.message);
      }
      // A timeout already left its own "tap to continue" notification.
      final text = switch (f.status) {
        EnhStatus.cancelled || EnhStatus.paused => null,
        _ => l10n.notifFailed,
      };
      await fg.release(this, text);
    } on EnhException catch (e) {
      AppLog.warn('job not started: $e');
      state = Failed(e.status, e.context);
      await fg.release(this, null);
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

  void answer(Map<String, Object?> option) {
    _job?.answer(option);
    state = const Running(JobStage.decode, 0, null);
  }

  void cancel() => _job?.cancel();

  void pause() => _job?.pause();

  void setStrength(double v) {
    final s = state;
    if (s is Finished) state = s.copyWith(strength: v.clamp(0.0, 1.0));
  }

  /// The parameters of the shown result, for "Save as preset" (FR-PRE-002).
  Recipe? get recipe => switch (state) {
    Finished(:final result, :final strength) => Recipe(
      scale: result.scale,
      fast2: result.fast2,
      srModel: result.model,
      strength: strength,
    ),
    _ => null,
  };

  /// Exports in the default format into the app album (FR-EXP-004). Returns the gallery URI.
  Future<String?> saveToGallery() async {
    final settings = await ref.read(settingsProvider.future);
    return _save(settings.format, Destination.gallery);
  }

  /// Exports in [format] to a document the user picks (FR-EXP-006). Null when cancelled.
  Future<String?> saveToFile(ExportFormat format) => _save(format, Destination.file);

  /// Each export that reaches its destination becomes a history entry unless history is off
  /// (FR-HIST-001, FR-HIST-005); a failure to record it throws [HistoryNotRecorded].
  Future<String?> _save(ExportFormat format, Destination to) async {
    final s = state;
    final input = _input;
    if (s is! Finished || s.saving || input == null) return null;
    final saver = await readResultSaver(ref);
    state = s.copyWith(saving: true);
    String? uri;
    try {
      uri = await saver.save(
        s.result,
        input: input,
        output: OutputSpec(format, quality: saver.settings.quality),
        strength: s.strength,
        to: to,
      );
    } on HistoryNotRecorded catch (e) {
      uri = e.uri;
      rethrow;
    } finally {
      state = s.copyWith(saved: s.saved || uri != null, saving: false);
    }
    return uri;
  }

  Future<void> reset() async {
    final s = state;
    _strength = 1;
    state = const Idle();
    if (s is Finished && s.saved) {
      try {
        await _jobs?.discard(s.result.jobDir, inUse: {?_input});
      } on FileSystemException catch (e) {
        AppLog.warn('discard saved job: ${e.message}'); // the startup sweep removes it
      }
    }
  }
}

final enhanceProvider = NotifierProvider.autoDispose<EnhanceController, EnhanceState>(
  EnhanceController.new,
);
