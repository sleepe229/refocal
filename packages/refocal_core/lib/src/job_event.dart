import 'enh_status.dart';

/// Pipeline stage reported by the native core (`stage` of ENH_EV_STAGE).
enum JobStage {
  queued,
  decode,
  upscale,
  finalize,
  unknown;

  static JobStage fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => unknown);
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
        return FallbackEvent('${p['from']}', '${p['to']}', '${p['reason']}');
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

class FallbackEvent extends JobEvent {
  const FallbackEvent(this.from, this.to, this.reason);
  final String from, to, reason;
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
    required this.raw,
  });

  factory JobResult.fromJson(Map<String, Object?> j) => JobResult(
    jobId: j['job_id'] as String,
    jobDir: j['job_dir'] as String,
    width: (j['width'] as num).toInt(),
    height: (j['height'] as num).toInt(),
    previewFile: ((j['preview'] as Map?)?['file'] as String?) ?? 'preview.jpg',
    backend: j['backend'] as String? ?? '',
    fallbacks: [for (final f in (j['fallbacks'] as List? ?? const [])) '$f'],
    raw: j,
  );

  final String jobId, jobDir, previewFile, backend;
  final int width, height;
  final List<String> fallbacks;
  final Map<String, Object?> raw;

  String get previewPath => '$jobDir/$previewFile';
}
