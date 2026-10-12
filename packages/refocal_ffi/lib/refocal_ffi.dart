/// Thin bridge to the Refocal native core (native/include/enh.h).
///
/// Events arrive through one native port per session (`enh_job_start_port`, ADR-0005 after
/// S6): the VM copies each message, nothing crosses the boundary as a pointer, and posting to a
/// dead isolate is harmless. Jobs are destroyed only after their terminal event, so
/// `enh_job_destroy` never blocks the UI isolate (S6).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:refocal_core/refocal_core.dart';

import 'src/enh_bindings.g.dart';

export 'package:refocal_core/refocal_core.dart';

class RefocalNative {
  RefocalNative._(this._b, this._libPath) {
    final abi = _b.enh_abi_version();
    if (abi != ENH_ABI_VERSION) {
      throw StateError('libenh ABI $abi, bindings expect $ENH_ABI_VERSION');
    }
  }

  /// Opens libenh: the APK's libenh.so on Android, the linked framework on iOS.
  factory RefocalNative.open({String? path}) => RefocalNative._(EnhBindings(_open(path)), path);

  final EnhBindings _b;
  final String? _libPath;
  static bool _dartApiReady = false;

  String get version => _b.enh_version().cast<Utf8>().toDartString();

  /// CPU/GPU description used for device tiers (ADR-0017).
  Map<String, Object?> deviceProbe() {
    final s = openSession(modelsDir: '', workDir: '');
    try {
      return s._probe();
    } finally {
      s.close();
    }
  }

  RefocalSession openSession({
    required String modelsDir,
    required String workDir,
    String cacheDir = '',
    EnhBackend backend = EnhBackend.auto,
    String? tier,
    int cpuThreads = 0,
  }) {
    if (!_dartApiReady) {
      if (_b.enh_dart_init(NativeApi.initializeApiDLData) != 0) {
        throw StateError('enh_dart_init failed (Dart API DL version mismatch)');
      }
      _dartApiReady = true;
    }
    final strings = <Pointer<Utf8>>[];
    Pointer<Char> str(String? v) {
      if (v == null) return nullptr;
      final p = v.toNativeUtf8();
      strings.add(p);
      return p.cast();
    }

    final cfg = calloc<enh_session_config>();
    final out = calloc<Pointer<enh_session>>();
    try {
      cfg.ref
        ..struct_size = sizeOf<enh_session_config>()
        ..models_dir = str(modelsDir)
        ..work_dir = str(workDir)
        ..cache_dir = str(cacheDir)
        ..backend_pref = backend.code
        ..cpu_threads = cpuThreads
        ..tier = str(tier);
      _check(_b.enh_session_create(cfg, out), 'session_create');
      return RefocalSession._(this, out.value);
    } finally {
      for (final p in strings) {
        malloc.free(p);
      }
      calloc
        ..free(cfg)
        ..free(out);
    }
  }

  static void _check(int code, String what) {
    final s = EnhStatus.fromCode(code);
    if (s != EnhStatus.ok) throw EnhException(s, what);
  }

  static DynamicLibrary _open(String? path) {
    if (path != null) return DynamicLibrary.open(path);
    final env = Platform.environment['REFOCAL_LIBENH'];
    if (env != null && env.isNotEmpty) return DynamicLibrary.open(env);
    if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libenh.so');
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    throw UnsupportedError('Refocal native core: unsupported platform');
  }
}

enum EnhBackend {
  auto(0),
  vulkan(1),
  cpu(2);

  const EnhBackend(this.code);
  final int code;
}

class RefocalSession {
  RefocalSession._(this._native, this._ptr) {
    _port.listen(_onMessage);
  }

  final RefocalNative _native;
  final Pointer<enh_session> _ptr;
  final _port = ReceivePort('refocal-session');
  final _jobs = <int, RefocalJob>{};
  int _nextToken = 1;
  bool _closed = false;

  EnhBindings get _b => _native._b;

  Map<String, Object?> _probe() {
    final out = calloc<Pointer<Char>>();
    try {
      RefocalNative._check(_b.enh_device_probe(_ptr, out), 'device_probe');
      final json = out.value.cast<Utf8>().toDartString();
      _b.enh_free(out.value.cast());
      return jsonDecode(json) as Map<String, Object?>;
    } finally {
      calloc.free(out);
    }
  }

  /// Starts a job from a request (schema 1, see native/core/src/job/job.hpp).
  RefocalJob start(Map<String, Object?> request) {
    final req = jsonEncode({'schema': 1, ...request}).toNativeUtf8();
    final out = calloc<Pointer<enh_job>>();
    try {
      RefocalNative._check(_b.enh_job_create(_ptr, req.cast(), out), 'job_create');
      return _launch(out.value, request['job_id'] as String);
    } finally {
      malloc.free(req);
      calloc.free(out);
    }
  }

  /// Continues a paused or interrupted job from its directory (checkpoint, ADR-0004).
  RefocalJob resume(String jobDir) {
    final dir = jobDir.toNativeUtf8();
    final out = calloc<Pointer<enh_job>>();
    try {
      RefocalNative._check(_b.enh_job_resume(_ptr, dir.cast(), out), 'job_resume');
      return _launch(out.value, jobDir.split('/').where((s) => s.isNotEmpty).last);
    } finally {
      malloc.free(dir);
      calloc.free(out);
    }
  }

  RefocalJob _launch(Pointer<enh_job> ptr, String jobId) {
    final job = RefocalJob._(this, ptr, _nextToken++, jobId);
    _jobs[job.token] = job;
    final st = _b.enh_job_start_port(ptr, _port.sendPort.nativePort, job.token);
    if (st != ENH_OK) {
      _jobs.remove(job.token);
      _b.enh_job_destroy(ptr);
      RefocalNative._check(st, 'job_start');
    }
    return job;
  }

  void _onMessage(dynamic msg) {
    final m = msg as List;
    final job = _jobs[m[0] as int];
    if (job == null) return; // late event of a destroyed job (S6): ignore
    final payload = jsonDecode(m[5] as String) as Map<String, Object?>;
    final ev = JobEvent.fromNative(m[1] as int, m[3] as int, m[4] as int, payload);
    if (ev == null) return;
    job._deliver(ev);
    if (ev.isTerminal) {
      _jobs.remove(job.token);
      _b.enh_job_destroy(job._ptr); // worker has finished: returns immediately
    }
  }

  /// Streams the job's BandStore into a JPEG at [dst] on a helper isolate (can take seconds).
  Future<Map<String, Object?>> export(String jobDir, String dst, {int quality = 92}) async {
    final libPath = _native._libPath;
    final sessionAddr = _ptr.address;
    final json = await Isolate.run(() {
      final b = EnhBindings(RefocalNative._open(libPath));
      final dir = jobDir.toNativeUtf8();
      final opt = jsonEncode({'format': 'jpeg', 'quality': quality}).toNativeUtf8();
      final d = dst.toNativeUtf8();
      final out = calloc<Pointer<Char>>();
      try {
        final st = b.enh_export(
          Pointer.fromAddress(sessionAddr),
          dir.cast(),
          opt.cast(),
          d.cast(),
          out,
        );
        RefocalNative._check(st, 'export');
        final s = out.value.cast<Utf8>().toDartString();
        b.enh_free(out.value.cast());
        return s;
      } finally {
        malloc
          ..free(dir)
          ..free(opt)
          ..free(d);
        calloc.free(out);
      }
    });
    return jsonDecode(json) as Map<String, Object?>;
  }

  void setGpuAllowed(bool allowed) => _b.enh_set_gpu_allowed(_ptr, allowed ? 1 : 0);
  void setMemoryPressure(int level) => _b.enh_set_memory_pressure(_ptr, level);
  void setThermal(int level) => _b.enh_set_thermal(_ptr, level);

  /// Cancels running jobs, waits for their terminal events, then frees the session.
  Future<void> dispose() async {
    final jobs = [..._jobs.values];
    for (final j in jobs) {
      j.cancel();
    }
    await Future.wait(jobs.map((j) => j.done.then((_) {}, onError: (_) {})));
    close();
  }

  /// Frees the session; all jobs must have finished (see [dispose]).
  void close() {
    if (_closed) return;
    if (_jobs.isNotEmpty) throw StateError('session has running jobs; use dispose()');
    _closed = true;
    _b.enh_session_destroy(_ptr);
    _port.close();
  }
}

class RefocalJob {
  RefocalJob._(this._session, this._ptr, this.token, this.jobId);

  final RefocalSession _session;
  final Pointer<enh_job> _ptr;
  final int token;
  final String jobId;
  final _events = StreamController<JobEvent>.broadcast();
  final _done = Completer<JobResult>();
  bool _finished = false;

  Stream<JobEvent> get events => _events.stream;

  /// Completes with the result, or with a [JobFailure] (cancelled, paused, error).
  Future<JobResult> get done => _done.future;

  void _deliver(JobEvent ev) {
    _events.add(ev);
    if (ev is DoneEvent) {
      _finished = true;
      _done.complete(ev.result);
      _events.close();
    } else if (ev is FailedEvent) {
      _finished = true;
      _done.completeError(JobFailure(ev));
      _events.close();
    }
  }

  void cancel() {
    if (!_finished) _session._b.enh_job_cancel(_ptr);
  }

  void pause() {
    if (!_finished) _session._b.enh_job_pause(_ptr);
  }

  /// Answers a [NeedsUserEvent], e.g. `{'scale': 2, 'fast2': true}`.
  void answer(Map<String, Object?> answer) {
    if (_finished) return;
    final a = jsonEncode(answer).toNativeUtf8();
    try {
      RefocalNative._check(_session._b.enh_job_answer(_ptr, a.cast()), 'job_answer');
    } finally {
      malloc.free(a);
    }
  }
}

class JobFailure implements Exception {
  JobFailure(this.event);
  final FailedEvent event;
  EnhStatus get status => event.status;

  @override
  String toString() =>
      'JobFailure(${status.name}${event.message == null ? '' : ': ${event.message}'})';
}
