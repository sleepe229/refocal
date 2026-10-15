import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';
import 'package:refocal_platform/refocal_platform.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/files.dart';
import '../../bootstrap/history.dart';
import '../../bootstrap/processing.dart';
import '../../bootstrap/settings.dart';

/// Output scale choices (ADR-0014). Fast 2x runs x4 on a half-size input: 4x cheaper; 1x runs
/// x4 and scales back down: noise and blur removal without enlarging (FR-ENH-004).
enum ScaleChoice {
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

/// The result was saved ([uri]) but its history entry could not be written.
class HistoryNotRecorded implements Exception {
  const HistoryNotRecorded(this.uri, this.cause);
  final String uri;
  final Object cause;

  @override
  String toString() => '$cause';
}

class EnhanceController extends Notifier<EnhanceState> {
  RefocalJob? _job;
  StreamSubscription<JobEvent>? _sub;
  StreamSubscription<String>? _actions;
  Engine? _engine;
  String? _input;
  bool _timedOut = false;

  /// Strength the result starts with (a preset's, FR-PRE-002; else 100%).
  double _strength = 1;

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
  /// job refers to it (ADR-0010). Unsaved and paused jobs stay for the home screen list. Runs
  /// after the screen is gone: a failure is logged and the startup sweep catches the rest.
  void _cleanup() {
    final engine = _engine, input = _input, s = state;
    if (engine == null) return;
    unawaited(() async {
      try {
        if (s is Finished && s.saved) await engine.jobs.discard(s.result.jobDir);
        if (input != null) await engine.jobs.releaseInput(input);
      } on FileSystemException catch (e) {
        AppLog.warn('editor cleanup: ${e.message}');
      }
    }());
  }

  /// Runs [recipe] on [input]; the result starts at the recipe's strength (a preset's or a
  /// history entry's, FR-PRE-002, FR-HIST-003).
  Future<void> start(String input, Recipe recipe) async {
    _strength = recipe.strength;
    final request = JobRequest.of(recipe, input);
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
    _engine = await ref.read(engineProvider.future);
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
    _engine = engine;
    _input = input;
    _timedOut = false;
    final platform = ref.read(platformApiProvider);
    state = const Running(JobStage.queued, 0, null);
    await _guard(platform.requestNotificationPermission);
    final l10n = ref.read(l10nProvider);
    await _guard(
      () => platform.startProcessing(
        ProcessingTexts(
          title: l10n.notifEnhancing,
          pause: l10n.pause,
          cancel: l10n.cancel,
          timedOut: l10n.notifTimedOut,
          channelName: l10n.notifChannelName,
          channelDescription: l10n.notifChannelDescription,
        ),
      ),
    );
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
            AppLog.warn('fallback ${e.from} -> ${e.to} (${e.reason})');
            note = l10n.noteSwitchedTo(e.to);
          case WarningEvent(code: 'alpha_flattened'):
            note = l10n.noteAlphaFlattened;
          case WarningEvent(code: 'animation_first_frame'):
            note = l10n.noteFirstFrame;
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
      await _guard(() => platform.stopProcessing(l10n.notifReady));
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
      await _guard(() => platform.stopProcessing(text));
    } on EnhException catch (e) {
      AppLog.warn('job not started: $e');
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
  /// A refusal (e.g. ForegroundServiceStartNotAllowedException, no activity for the permission
  /// dialog) is logged; anything else is a bug and propagates.
  static Future<void> _guard(FutureOr<Object?> Function() f) async {
    try {
      await f();
    } on PlatformException catch (e) {
      AppLog.warn('platform: ${e.code}');
    }
  }

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
    return _export(
      settings.format,
      (platform, path, name) => platform.saveToGallery(path, name, settings.format.mimeType),
    );
  }

  /// Exports in [format] to a document the user picks (FR-EXP-006). Null when cancelled.
  Future<String?> saveToFile(ExportFormat format) =>
      _export(format, (platform, path, name) => platform.saveToFile(path, name, format.mimeType));

  /// Any number of exports from one result, without processing again (FR-EXP-007). Each one
  /// that reaches its destination becomes a history entry unless history is off (FR-HIST-001,
  /// FR-HIST-005); a failure to record it throws [HistoryNotRecorded] after the save.
  Future<String?> _export(
    ExportFormat format,
    Future<String?> Function(RefocalPlatformApi, String path, String name) deliver,
  ) async {
    final s = state;
    if (s is! Finished || s.saving) return null;
    final engine = await ref.read(engineProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final history = settings.historyEnabled ? await ref.read(historyStoreProvider.future) : null;
    final entryId = newId();
    final preview = await history?.previewPathFor(entryId);
    await Directory(engine.exportDir).create(recursive: true);
    final name = 'Refocal_${s.result.jobId}.${format.extension}';
    final tmp = '${engine.exportDir}/$name';
    state = s.copyWith(saving: true);
    String? uri;
    try {
      await engine.session.export(
        s.result.jobDir,
        tmp,
        format: format.format,
        quality: settings.quality,
        lossless: format.lossless,
        strength: s.strength,
        keepGps: settings.keepGps,
        aiMarker: settings.aiMarker,
        thumbnail: preview,
        thumbnailMaxSide: HistoryStore.previewMaxSide,
      );
      uri = await deliver(ref.read(platformApiProvider), tmp, name);
      AppLog.info(
        'export ${format.name} q${settings.quality} strength ${s.strength}: '
        '${uri == null ? 'cancelled' : 'saved'}',
      );
    } catch (e, stack) {
      AppLog.error('export ${format.name} failed', e, stack);
      state = s.copyWith(saving: false);
      if (preview != null) await deleteIfPresent(preview);
      rethrow;
    } finally {
      await deleteIfPresent(tmp); // the export copy is delivered or abandoned
    }
    state = s.copyWith(saved: s.saved || uri != null, saving: false);
    if (history == null || preview == null) return uri;
    if (uri == null) {
      await deleteIfPresent(preview); // cancelled: nothing was saved
      return null;
    }
    final r = s.result;
    try {
      await history.repo.add(
        HistoryEntry(
          id: entryId,
          createdAt: DateTime.now(),
          recipe: Recipe(
            scale: r.scale,
            fast2: r.fast2,
            srModel: r.model,
            strength: s.strength,
            output: OutputSpec(format, quality: settings.quality),
          ),
          inputPath: history.relative(_input!),
          sourceWidth: r.inputWidth,
          sourceHeight: r.inputHeight,
          width: r.width,
          height: r.height,
          previewPath: history.relative(preview),
          resultUri: uri,
          modelIds: [r.model],
          backend: r.backend,
          duration: r.duration,
          jobId: r.jobId,
        ),
      );
    } on Exception catch (e) {
      await deleteIfPresent(preview);
      throw HistoryNotRecorded(uri, e);
    }
    return uri;
  }

  Future<void> reset() async {
    final s = state;
    _strength = 1;
    state = const Idle();
    if (s is Finished && s.saved) {
      try {
        await _engine?.jobs.discard(s.result.jobDir, inUse: {?_input});
      } on FileSystemException catch (e) {
        AppLog.warn('discard saved job: ${e.message}'); // the startup sweep removes it
      }
    }
  }
}

final enhanceProvider = NotifierProvider.autoDispose<EnhanceController, EnhanceState>(
  EnhanceController.new,
);
