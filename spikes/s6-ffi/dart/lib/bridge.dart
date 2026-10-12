// S6: the event bridge for refocal_ffi — one event sink per session, events routed by job token.
// Mode A ("callable", ADR-0005 as written): NativeCallable.listener, heap payload freed by Dart.
// Mode B ("port", S6 proposal): Dart_PostCObject into a ReceivePort, VM-copied payload.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'enh_bindings.g.dart';

enum Mode { callable, port }

Mode modeFromEnv() => Mode.values.byName(Platform.environment['S6_MODE'] ?? 'callable');

bool _dartApiReady = false;
void initDartApi(EnhBindings b) {
  if (_dartApiReady) return;
  if (b.enh_dart_init(NativeApi.initializeApiDLData) != 0) throw StateError('enh_dart_init');
  _dartApiReady = true;
}

const evProgress = 2, evNeedsUser = 5, evDone = 6, evError = 7;

EnhBindings openBindings() {
  final path = Platform.environment['S6_LIB'] ??
      '${File.fromUri(Platform.script).parent.parent.parent.path}/native/build-rel/libenh_mock.so';
  return EnhBindings(DynamicLibrary.open(path));
}

class Event {
  Event(this.type, this.done, this.total, this.payload, this.recvNs);
  final int type, done, total, recvNs;
  final Map<String, dynamic>? payload;
}

class JobHandle {
  JobHandle(this.token, this.ptr);
  final int token;
  final Pointer<enh_job> ptr;
  final events = StreamController<Event>.broadcast(sync: true);
  final terminal = Completer<Event>();
  int received = 0, afterTerminal = 0, lastDone = -1, nonMonotonic = 0;
  final latenciesUs = <int>[];
}

class Bridge {
  Bridge(this.b, {this.decode = true, Mode? mode}) : mode = mode ?? modeFromEnv() {
    final cfg = calloc<enh_session_config>();
    cfg.ref.struct_size = sizeOf<enh_session_config>();
    final out = calloc<Pointer<enh_session>>();
    final st = b.enh_session_create(cfg, out);
    if (st != ENH_OK) throw StateError('session_create: $st');
    session = out.value;
    calloc.free(cfg);
    calloc.free(out);
    if (this.mode == Mode.callable) {
      callable = NativeCallable<enh_event_cbFunction>.listener(_onCallable);
    } else {
      initDartApi(b);
      port = ReceivePort()..listen(_onPort);
    }
  }

  final EnhBindings b;
  final bool decode;
  final Mode mode;
  NativeCallable<enh_event_cbFunction>? callable;
  ReceivePort? port;
  late final Pointer<enh_session> session;
  final jobs = <int, JobHandle>{};
  int _nextToken = 1;
  int unknownToken = 0;

  void _onCallable(int token, int type, int stage, int done, int total, Pointer<Char> payload) {
    final now = b.enh_debug_now_ns();
    String? str;
    try {
      str = decode ? payload.cast<Utf8>().toDartString() : null;
    } finally {
      b.enh_free(payload.cast()); // free even if decoding throws (invalid UTF-8)
    }
    _onEvent(now, token, type, done, total, str);
  }

  void _onPort(dynamic msg) {
    final now = b.enh_debug_now_ns();
    final m = msg as List;
    _onEvent(now, m[0] as int, m[1] as int, m[3] as int, m[4] as int, decode ? m[5] as String : null);
  }

  void _onEvent(int now, int token, int type, int done, int total, String? str) {
    final json = str == null ? null : jsonDecode(str) as Map<String, dynamic>;
    final j = jobs[token];
    if (j == null) {
      unknownToken++;
      return;
    }
    if (j.terminal.isCompleted) j.afterTerminal++;
    j.received++;
    if (type == evProgress) {
      if (done < j.lastDone) j.nonMonotonic++;
      j.lastDone = done;
      final t = json?['t_ns'];
      if (t is int) j.latenciesUs.add((now - t) ~/ 1000);
    }
    final ev = Event(type, done, total, json, now);
    j.events.add(ev);
    if ((type == evDone || type == evError) && !j.terminal.isCompleted) j.terminal.complete(ev);
  }

  JobHandle start(Map<String, int> request, {int? token}) {
    final req = jsonEncode(request).toNativeUtf8();
    final out = calloc<Pointer<enh_job>>();
    final st = b.enh_job_create(session, req.cast(), out);
    malloc.free(req);
    if (st != ENH_OK) throw StateError('job_create: $st');
    final j = JobHandle(token ?? _nextToken++, out.value);
    calloc.free(out);
    jobs[j.token] = j;
    final st2 = mode == Mode.callable
        ? b.enh_job_start(j.ptr, callable!.nativeFunction, j.token)
        : b.enh_job_start_port(j.ptr, port!.sendPort.nativePort, j.token);
    if (st2 != ENH_OK) throw StateError('job_start: $st2');
    return j;
  }

  Map<String, dynamic> stats(JobHandle j) {
    final out = calloc<Pointer<Char>>();
    b.enh_debug_job_stats(j.ptr, out);
    final s = jsonDecode(out.value.cast<Utf8>().toDartString()) as Map<String, dynamic>;
    b.enh_free(out.value.cast());
    calloc.free(out);
    return s;
  }

  /// Recommended teardown: cancel, await terminal event (async, UI not blocked), then destroy
  /// (join is instant because the worker has already finished).
  Future<void> dispose(JobHandle j) async {
    b.enh_job_cancel(j.ptr);
    await j.terminal.future;
    b.enh_job_destroy(j.ptr);
    jobs.remove(j.token);
  }

  /// Re-attach a running job (created elsewhere) to this bridge.
  int attach(JobHandle j) {
    jobs[j.token] = j;
    return mode == Mode.callable
        ? b.enh_job_set_callback(j.ptr, callable!.nativeFunction, j.token)
        : b.enh_job_set_port(j.ptr, port!.sendPort.nativePort, j.token);
  }

  /// Closes the event sink only (no native detach) — used by the early-close scenarios.
  void closeSink() {
    callable?.close();
    port?.close();
  }

  void close() {
    b.enh_session_destroy(session);
    closeSink();
  }
}

/// Measures event-loop lateness as a proxy for UI jank: a 16 ms periodic timer.
class FrameProbe {
  final _sw = Stopwatch();
  Timer? _t;
  int _last = 0;
  final latenessMs = <double>[];
  void start() {
    _sw.start();
    _last = _sw.elapsedMicroseconds;
    _t = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = _sw.elapsedMicroseconds;
      latenessMs.add(((now - _last) - 16000) / 1000);
      _last = now;
    });
  }

  Map<String, num> stop() {
    _t?.cancel();
    final l = [...latenessMs]..sort();
    if (l.isEmpty) return {'frames': 0};
    return {
      'frames': l.length,
      'late_gt_16ms': l.where((x) => x > 16).length,
      'p99_ms': l[(l.length * 0.99).floor().clamp(0, l.length - 1)],
      'max_ms': l.last,
    };
  }
}

Map<String, num> pct(List<int> xs) {
  if (xs.isEmpty) return {'n': 0};
  final s = [...xs]..sort();
  num p(double q) => s[(s.length * q).floor().clamp(0, s.length - 1)];
  return {'n': s.length, 'p50': p(0.5), 'p90': p(0.9), 'p99': p(0.99), 'max': s.last};
}
