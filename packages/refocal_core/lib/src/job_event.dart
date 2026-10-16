import 'enh_status.dart';

/// Pipeline stage reported by the native core (`stage` of ENH_EV_STAGE).
enum JobStage {
  queued('queued'),
  decode('decode'),

  /// DetectFaces + RestoreFaces (ADR-0012).
  faces('restore_faces'),
  upscale('upscale'),
  finalize('finalize'),
  unknown('');

  const JobStage(this.wire);

  /// The name the core reports.
  final String wire;

  static JobStage fromName(String? name) =>
      values.firstWhere((s) => s != unknown && s.wire == name, orElse: () => unknown);
}

/// Events of one enhancement job (docs/spec/03 §4.1). Decoded from the native event tuple
/// `(type, stage, done, total, payload)`; unknown types are ignored by [JobEvent.fromNative].
sealed class JobEvent {
  const JobEvent();

  static JobEvent? fromNative(int type, int done, int total, Map<String, Object?> p) {
    switch (type) {
      case 1:
        return StageEvent(JobStage.fromName(p['stage'] as String?));
      case 2:
        final eta = (p['eta_ms'] as num?)?.toInt() ?? -1;
        return ProgressEvent(done, total, eta >= 0 ? Duration(milliseconds: eta) : null);
      case 3:
        return FallbackEvent(
          FallbackKind.fromName(p['kind'] as String?),
          '${p['from'] ?? ''}',
          '${p['to'] ?? ''}',
          '${p['reason']}',
          faceIndex: (p['index'] as num?)?.toInt(),
        );
      case 4:
        return WarningEvent('${p['code']}', p);
      case 5:
        return NeedsUserEvent('${p['code']}', p);
      case 6:
        return DoneEvent(JobResult.fromJson(p));
      case 7:
        final status = EnhStatus.fromCode((p['status'] as num?)?.toInt() ?? 99);
        return FailedEvent(status, p['message'] as String?, p['job_dir'] as String?);
    }
    return null;
  }

  bool get isTerminal => this is DoneEvent || this is FailedEvent;
}

class StageEvent extends JobEvent {
  const StageEvent(this.stage);
  final JobStage stage;
}

class ProgressEvent extends JobEvent {
  const ProgressEvent(this.done, this.total, this.eta);
  final int done, total;
  final Duration? eta;
  double get fraction => total > 0 ? done / total : 0;
}

/// A rung of the fallback ladder (ADR-0016, enh.h ENH_EV_FALLBACK).
enum FallbackKind {
  /// Smaller tiles, the same pixels (slower).
  tile,

  /// Another backend.
  backend,

  /// A face ([FallbackEvent.faceIndex]) or all faces left as the SR model makes them.
  face;

  static FallbackKind fromName(String? name) =>
      values.where((k) => k.name == name).firstOrNull ?? backend;
}

class FallbackEvent extends JobEvent {
  const FallbackEvent(this.kind, this.from, this.to, this.reason, {this.faceIndex});
  final FallbackKind kind;

  /// Reason: oom | memory_pressure | numeric | backend_error.
  final String from, to, reason;
  final int? faceIndex;
}

class WarningEvent extends JobEvent {
  const WarningEvent(this.code, this.payload);
  final String code;
  final Map<String, Object?> payload;
}

/// The core waits for [answer]-style input, e.g. `downscale_required` with `options`.
class NeedsUserEvent extends JobEvent {
  const NeedsUserEvent(this.code, this.payload);
  final String code;
  final Map<String, Object?> payload;

  List<Map<String, Object?>> get options => [
    for (final o in (payload['options'] as List? ?? const [])) (o as Map).cast<String, Object?>(),
  ];
}

class DoneEvent extends JobEvent {
  const DoneEvent(this.result);
  final JobResult result;
}

/// Terminal failure; [status] is [EnhStatus.cancelled] / [EnhStatus.paused] for user actions.
/// A paused job can be resumed from [jobDir].
class FailedEvent extends JobEvent {
  const FailedEvent(this.status, this.message, this.jobDir);
  final EnhStatus status;
  final String? message;
  final String? jobDir;
}

/// `result.json` of a finished job.
class JobResult {
  const JobResult({
    required this.jobId,
    required this.jobDir,
    required this.width,
    required this.height,
    required this.previewFile,
    required this.backend,
    required this.fallbacks,
    required this.scale,
    required this.fast2,
    required this.model,
    required this.inputWidth,
    required this.inputHeight,
    required this.duration,
    required this.raw,
  });

  factory JobResult.fromJson(Map<String, Object?> j) {
    final input = j['input']! as Map;
    final totalMs = ((j['timings_ms'] as Map?)?['total'] as num?)?.toInt();
    return JobResult(
      jobId: j['job_id'] as String,
      jobDir: j['job_dir'] as String,
      width: (j['width'] as num).toInt(),
      height: (j['height'] as num).toInt(),
      previewFile: ((j['preview'] as Map?)?['file'] as String?) ?? 'preview.jpg',
      backend: j['backend'] as String? ?? '',
      fallbacks: [for (final f in (j['fallbacks'] as List? ?? const [])) '$f'],
      scale: (j['scale'] as num).toInt(),
      fast2: j['fast2'] as bool,
      model: j['model'] as String,
      inputWidth: (input['width'] as num).toInt(),
      inputHeight: (input['height'] as num).toInt(),
      duration: totalMs == null ? null : Duration(milliseconds: totalMs),
      raw: j,
    );
  }

  final String jobId, jobDir, previewFile, backend;
  final int width, height;
  final List<String> fallbacks;

  /// What was asked for (ADR-0014) and the SR model that ran.
  final int scale;
  final bool fast2;
  final String model;

  /// The input after EXIF orientation.
  final int inputWidth, inputHeight;

  /// Processing time of the last run (from the resume for a resumed job).
  final Duration? duration;
  final Map<String, Object?> raw;

  String get previewPath => '$jobDir/$previewFile';
}
