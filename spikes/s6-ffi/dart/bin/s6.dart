// S6 scenarios. Usage: dart run bin/s6.dart <scenario>; prints one JSON object per result line.
// Each scenario runs in its own process (run.sh) so a crash in one does not hide the others.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:refocal_s6_ffi/bridge.dart';
import 'package:refocal_s6_ffi/enh_bindings.g.dart';

final b = openBindings();
final rng = Random(42);

final mode = modeFromEnv();

void emit(String scenario, Map<String, Object?> data) =>
    print(jsonEncode({'scenario': scenario, 'mode': mode.name, ...data}));

Future<void> settle([int ms = 200]) => Future.delayed(Duration(milliseconds: ms));

int rssMb() => ProcessInfo.currentRss ~/ (1 << 20);

/// 10k events per job: delivery latency, event-loop lateness, leaks. Variants: flood (10k in
/// ~50 ms), paced (10k over ~5 s), coalesced (flood with native 33 ms coalescing), raw (no decode).
Future<void> throughput() async {
  final variants = <String, (Map<String, int>, bool)>{
    'flood': ({'tiles': 100, 'events_per_tile': 100, 'infer_us': 500}, true),
    'flood_nodecode': ({'tiles': 100, 'events_per_tile': 100, 'infer_us': 500}, false),
    'flood_big_payload': (
      {'tiles': 100, 'events_per_tile': 100, 'infer_us': 500, 'payload_bytes': 1024},
      true
    ),
    'paced_5s': ({'tiles': 100, 'events_per_tile': 100, 'infer_us': 50000}, true),
    'flood_coalesce_33ms': (
      {'tiles': 100, 'events_per_tile': 100, 'infer_us': 500, 'progress_min_us': 33000},
      true
    ),
    'paced_coalesce_33ms': (
      {'tiles': 100, 'events_per_tile': 100, 'infer_us': 50000, 'progress_min_us': 33000},
      true
    ),
  };
  for (final MapEntry(key: name, value: (req, decode)) in variants.entries) {
    final br = Bridge(b, decode: decode);
    final probe = FrameProbe()..start();
    final sw = Stopwatch()..start();
    final j = br.start(req);
    await j.terminal.future;
    final wallMs = sw.elapsedMilliseconds;
    final frames = probe.stop();
    final st = br.stats(j);
    b.enh_job_destroy(j.ptr);
    await settle();
    br.close();
    emit('throughput', {
      'variant': name,
      'received': j.received,
      'emitted': st['emitted'],
      'coalesced': st['coalesced'],
      'wall_ms': wallMs,
      'latency_us': pct(j.latenciesUs),
      'native_cb_us_avg': (st['cb_ns_total'] as int) / max(1, st['emitted'] as int) / 1000,
      'native_cb_us_max': (st['cb_ns_max'] as int) / 1000,
      'event_loop': frames,
      'after_terminal': j.afterTerminal,
      'non_monotonic': j.nonMonotonic,
      'live_payloads': b.enh_debug_live_payloads(),
    });
  }
}

/// 200 sequential jobs x 10k events: RSS drift and leak counters.
Future<void> soak() async {
  final br = Bridge(b);
  final rss = <int>[];
  var events = 0;
  final sw = Stopwatch()..start();
  for (var i = 0; i < 200; i++) {
    final j = br.start({'tiles': 100, 'events_per_tile': 100, 'infer_us': 200});
    await j.terminal.future;
    events += j.received;
    b.enh_job_destroy(j.ptr);
    br.jobs.remove(j.token);
    if (i % 20 == 0) rss.add(rssMb());
  }
  await settle();
  rss.add(rssMb());
  br.close();
  emit('soak', {
    'jobs': 200,
    'events': events,
    'wall_s': sw.elapsedMilliseconds / 1000,
    'events_per_s': (events / (sw.elapsedMilliseconds / 1000)).round(),
    'rss_mb_series': rss,
    'live_payloads': b.enh_debug_live_payloads(),
    'live_jobs': b.enh_debug_live_jobs(),
    'live_threads': b.enh_debug_live_threads(),
  });
}

/// Cancel/pause latency: cancel() call -> terminal event received in Dart, with tile = 100 ms
/// (T1 tile budget is <= 1 s) and the depth-2 pipeline full.
Future<void> cancel() async {
  for (final (label, infer, prep, post) in [
    ('tile100ms', 100000, 5000, 10000),
    ('tile500ms', 500000, 5000, 10000),
    ('post_heavy', 50000, 5000, 80000),
  ]) {
    for (final op in ['cancel', 'pause']) {
      final br = Bridge(b);
      final lat = <int>[], after = <int>[];
      final trials = infer >= 500000 ? 10 : 30;
      for (var t = 0; t < trials; t++) {
        final j = br.start({
          'tiles': 1000,
          'events_per_tile': 1,
          'infer_us': infer,
          'prep_us': prep,
          'post_us': post,
        });
        await Future.delayed(Duration(milliseconds: 50 + rng.nextInt(1500)));
        final t0 = b.enh_debug_now_ns();
        op == 'cancel' ? b.enh_job_cancel(j.ptr) : b.enh_job_pause(j.ptr);
        final ev = await j.terminal.future;
        lat.add((ev.recvNs - t0) ~/ 1000000);
        final st = br.stats(j);
        after.add(st['tiles_after_cancel'] as int);
        final status = (ev.payload!['status'] as int);
        if (status != (op == 'cancel' ? 1 : 2)) throw StateError('bad status $status');
        b.enh_job_destroy(j.ptr);
        br.jobs.remove(j.token);
      }
      br.close();
      emit('cancel', {
        'variant': label,
        'op': op,
        'tile_ms': {'prep': prep / 1000, 'infer': infer / 1000, 'post': post / 1000},
        'latency_ms': pct(lat),
        'tiles_completed_after_cancel': pct(after),
        'live_payloads': b.enh_debug_live_payloads(),
      });
    }
  }
}

/// enh_job_destroy() joins the worker. Called on the UI isolate while the job runs it blocks
/// for up to one tile; the recommended order (cancel -> await terminal -> destroy) does not.
Future<void> destroyBlocking() async {
  final br = Bridge(b);
  final naive = <int>[], recommended = <int>[];
  for (var t = 0; t < 20; t++) {
    final j = br.start({'tiles': 1000, 'infer_us': 100000, 'post_us': 10000});
    await Future.delayed(Duration(milliseconds: 50 + rng.nextInt(500)));
    final sw = Stopwatch()..start();
    b.enh_job_destroy(j.ptr); // blocks the isolate
    naive.add(sw.elapsedMicroseconds ~/ 1000);
    br.jobs.remove(j.token);
  }
  for (var t = 0; t < 20; t++) {
    final j = br.start({'tiles': 1000, 'infer_us': 100000, 'post_us': 10000});
    await Future.delayed(Duration(milliseconds: 50 + rng.nextInt(500)));
    b.enh_job_cancel(j.ptr);
    await j.terminal.future;
    final sw = Stopwatch()..start();
    b.enh_job_destroy(j.ptr);
    recommended.add(sw.elapsedMicroseconds);
    br.jobs.remove(j.token);
  }
  await settle();
  final unknown = br.unknownToken;
  br.close();
  emit('destroy_blocking', {
    'naive_destroy_block_ms': pct(naive),
    'recommended_destroy_block_us': pct(recommended),
    'events_for_unknown_token_after_naive_destroy': unknown,
    'live_payloads': b.enh_debug_live_payloads(),
  });
}

/// Closing the NativeCallable while messages are still queued in the port, and while the
/// native side still calls it.
Future<void> earlyClose() async {
  // (a) job finished and destroyed, but its events are still queued -> close() before draining.
  {
    final before = b.enh_debug_live_payloads();
    final br = Bridge(b);
    final j = br.start({'tiles': 100, 'events_per_tile': 100, 'infer_us': 0});
    // Busy-wait on the native status without yielding: all 10k messages stay queued.
    while (b.enh_job_status(j.ptr) < 0) {}
    b.enh_job_destroy(j.ptr);
    br.close();
    await settle(500);
    emit('early_close', {
      'variant': 'close_with_queued_messages',
      'received_before_close': j.received,
      'leaked_payloads': b.enh_debug_live_payloads() - before,
    });
  }
  // (b) native keeps calling a closed listener (job not destroyed, callback not swapped).
  {
    final before = b.enh_debug_live_payloads();
    final br = Bridge(b);
    final j = br.start({'tiles': 200, 'events_per_tile': 50, 'infer_us': 2000});
    await settle(100);
    final recv = j.received;
    br.closeSink();
    while (b.enh_job_status(j.ptr) < 0) {
      await settle(10);
    }
    final st = br.stats(j);
    b.enh_job_destroy(j.ptr);
    b.enh_session_destroy(br.session);
    await settle(300);
    emit('early_close', {
      'variant': 'native_calls_closed_listener',
      'process_alive': true,
      'received_before_close': recv,
      'emitted_total': st['emitted'],
      'dropped_natively': st['dropped'],
      'leaked_payloads': b.enh_debug_live_payloads() - before,
    });
  }
}

/// Engine/isolate death mid-job (Flutter hot restart; Android Activity destroyed while the FGS
/// keeps the process and the job alive). The job is re-attached from another isolate with
/// enh_job_set_callback().
Future<void> isolateKill() async {
  final br = Bridge(b);
  final before = b.enh_debug_live_payloads();
  final rp = ReceivePort();
  final iso = await Isolate.spawn(_jobOwner, (rp.sendPort, br.session.address, mode.name));
  final msgs = StreamIterator(rp);
  await msgs.moveNext();
  final jobAddr = msgs.current as int;
  await settle(150);
  iso.kill(priority: Isolate.immediate);
  await settle(300); // native keeps emitting into the dead isolate's listener
  final statsDead = br.stats(JobHandle(0, Pointer.fromAddress(jobAddr)));
  final leakedWhileDead = b.enh_debug_live_payloads() - before;

  final j = JobHandle(777, Pointer<enh_job>.fromAddress(jobAddr));
  final st = br.attach(j);
  final ev = await j.terminal.future.timeout(const Duration(seconds: 30));
  final statsEnd = br.stats(j);
  b.enh_job_destroy(j.ptr);
  await settle();
  emit('isolate_kill', {
    'process_alive': true,
    'emitted_before_reattach': statsDead['emitted'],
    'dropped_while_dead': statsDead['dropped'],
    'leaked_payloads_while_dead': leakedWhileDead,
    'reattach_status': st,
    'received_after_reattach': j.received,
    'terminal_type': ev.type,
    'tiles_done': statsEnd['tiles_done'],
    'leaked_payloads_total': b.enh_debug_live_payloads() - before,
  });
  rp.close();
  br.close();
}

Future<void> _jobOwner((SendPort, int, String) args) async {
  final (port, sessionAddr, modeName) = args;
  final bb = openBindings();
  final m = Mode.values.byName(modeName);
  final callable = m == Mode.callable
      ? NativeCallable<enh_event_cbFunction>.listener(
          (int t, int ty, int sg, int d, int tot, Pointer<Char> p) => bb.enh_free(p.cast()))
      : null;
  final rp = m == Mode.port ? (ReceivePort()..listen((_) {})) : null;
  if (rp != null) initDartApi(bb);
  final req = '{"tiles":300,"events_per_tile":20,"infer_us":5000}';
  final r = req.codeUnits;
  final cstr = calloc<Uint8>(r.length + 1)..asTypedList(r.length).setAll(0, r);
  final out = calloc<Pointer<enh_job>>();
  bb.enh_job_create(Pointer.fromAddress(sessionAddr), cstr.cast(), out);
  if (callable != null) {
    bb.enh_job_start(out.value, callable.nativeFunction, 1);
  } else {
    bb.enh_job_start_port(out.value, rp!.sendPort.nativePort, 1);
  }
  port.send(out.value.address);
  await Completer<void>().future; // live until killed
}

/// NEEDS_USER: answer path, cancel while waiting, destroy while waiting (must not hang).
Future<void> needsUser() async {
  final br = Bridge(b);
  final res = <String, Object?>{};
  {
    final j = br.start({'tiles': 20, 'infer_us': 2000, 'needs_user_at': 5});
    await j.events.stream.firstWhere((e) => e.type == evNeedsUser);
    final waitingTiles = br.stats(j)['tiles_done'];
    final ans = '{"choice":"2x"}'.codeUnits;
    final c = calloc<Uint8>(ans.length + 1)..asTypedList(ans.length).setAll(0, ans);
    b.enh_job_answer(j.ptr, c.cast());
    calloc.free(c);
    final ev = await j.terminal.future;
    res['answer'] = {'tiles_done_while_waiting': waitingTiles, 'terminal': ev.type};
    b.enh_job_destroy(j.ptr);
  }
  {
    final j = br.start({'tiles': 20, 'infer_us': 2000, 'needs_user_at': 5});
    await j.events.stream.firstWhere((e) => e.type == evNeedsUser);
    final t0 = b.enh_debug_now_ns();
    b.enh_job_cancel(j.ptr);
    final ev = await j.terminal.future;
    res['cancel_while_waiting'] = {
      'terminal': ev.type,
      'status': ev.payload!['status'],
      'latency_ms': (ev.recvNs - t0) / 1e6,
    };
    b.enh_job_destroy(j.ptr);
  }
  {
    final j = br.start({'tiles': 20, 'infer_us': 2000, 'needs_user_at': 0});
    await j.events.stream.firstWhere((e) => e.type == evNeedsUser);
    final sw = Stopwatch()..start();
    b.enh_job_destroy(j.ptr);
    res['destroy_while_waiting_ms'] = sw.elapsedMicroseconds / 1000;
  }
  await settle();
  br.close();
  emit('needs_user', {...res, 'live_payloads': b.enh_debug_live_payloads()});
}

/// Several concurrent jobs on one listener: routing by token, no cross-talk, ordering.
Future<void> concurrent() async {
  final br = Bridge(b);
  final js = [
    for (var i = 0; i < 8; i++)
      br.start({'tiles': 100, 'events_per_tile': 100, 'infer_us': 300 + 100 * i})
  ];
  await Future.wait(js.map((j) => j.terminal.future));
  final perJob = [for (final j in js) br.stats(j)['emitted'] == j.received];
  final nonMono = js.fold<int>(0, (a, j) => a + j.nonMonotonic);
  final after = js.fold<int>(0, (a, j) => a + j.afterTerminal);
  for (final j in js) {
    b.enh_job_destroy(j.ptr);
  }
  await settle();
  br.close();
  emit('concurrent', {
    'jobs': js.length,
    'all_routed': perJob.every((x) => x),
    'events': js.fold<int>(0, (a, j) => a + j.received),
    'non_monotonic': nonMono,
    'after_terminal': after,
    'unknown_token': br.unknownToken,
    'live_payloads': b.enh_debug_live_payloads(),
  });
}

/// Invalid UTF-8 in a payload (e.g. a raw path in an error message).
Future<void> badUtf8() async {
  final errors = <String>[];
  await runZonedGuarded(() async {
    final br = Bridge(b);
    final j = br.start({'tiles': 3, 'infer_us': 1000, 'bad_utf8': 1});
    final stages = <Object?>[];
    j.events.stream.listen((e) => stages.add(e.payload?['stage']));
    final ev = await j.terminal.future.timeout(const Duration(seconds: 10));
    final st = br.stats(j);
    b.enh_job_destroy(j.ptr);
    await settle();
    br.close();
    emit('bad_utf8', {
      'received': j.received,
      'emitted': st['emitted'],
      'dropped': st['dropped'],
      'terminal': ev.type,
      'stage_values': stages.take(1).toList(),
      'errors': errors,
      'live_payloads': b.enh_debug_live_payloads(),
    });
  }, (e, _) => errors.add('${e.runtimeType}: ${e.toString().split('\n').first}'));
}

Future<void> main(List<String> args) async {
  final scenarios = <String, Future<void> Function()>{
    'throughput': throughput,
    'soak': soak,
    'cancel': cancel,
    'destroy_blocking': destroyBlocking,
    'early_close': earlyClose,
    'isolate_kill': isolateKill,
    'needs_user': needsUser,
    'concurrent': concurrent,
    'bad_utf8': badUtf8,
  };
  final names = args.isEmpty ? scenarios.keys.toList() : args;
  for (final n in names) {
    await scenarios[n]!();
  }
  // NativeCallable.listener keeps the isolate alive; exit explicitly.
  exit(0);
}
