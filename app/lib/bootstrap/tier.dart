import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import 'app_log.dart';
import 'database.dart';
import 'engine.dart';
import 'queue.dart';
import 'settings.dart';

/// The device tier in use (ADR-0017): the benchmark's, or the user's choice (FR-SET-003).
class TierState {
  const TierState({required this.tier, required this.benchmark, required this.overridden});
  final DeviceTier tier;

  /// Null when the benchmark could not run (the tier is then T0, the safe one).
  final BenchmarkResult? benchmark;
  final bool overridden;
}

/// Runs once per process after startup: the cached benchmark result for this app, model, GPU
/// driver and OS build, or a new benchmark (seconds, off the UI isolate; a job started
/// meanwhile waits), then sets the session's tier.
final tierProvider = FutureProvider<TierState>((ref) async {
  final engine = await ref.watch(startupProvider.future);
  final override = DeviceTier.parse(
    ref.watch(settingsProvider.select((s) => s.value?.tierOverride)),
  );
  final repo = TierRepository(await ref.read(databaseProvider.future));
  BenchmarkResult? result;
  try {
    final info = await ref.read(platformApiProvider).deviceInfo();
    final gpus = (engine.native.deviceProbe()['gpus'] as List?) ?? const [];
    // ncnn GpuInfo.type 3 is a software rasterizer, never used (S3).
    final gpu = gpus.cast<Map<String, Object?>>().where((g) => g['type'] != 3).firstOrNull;
    final key = TierRepository.key(
      appVersion: engine.version,
      modelVersion: bundledSrModel,
      driverVersion: '${gpu?['driver_version'] ?? 'none'}',
      gpuDeviceId: gpu == null ? 'none' : '${gpu['vendor_id']}:${gpu['device_id']}',
      osBuild: info.osBuild,
    );
    result = await repo.get(key);
    if (result == null) {
      AppLog.info('benchmark: running');
      result = await repo.put(key, await engine.session.benchmark(ramBytes: info.totalRamBytes));
      AppLog.info(
        'benchmark: ${result.tier.label}, ${result.backend} ${result.tile128Ms.round()} ms',
      );
    }
  } on EnhException catch (e) {
    AppLog.warn('benchmark failed: ${e.status.name}'); // T0: the safe tier
  } on PlatformException catch (e) {
    AppLog.warn('device info: ${e.code}');
  } on FormatException catch (e) {
    AppLog.warn('benchmark result: ${e.message}');
  }
  final tier = override ?? result?.tier ?? DeviceTier.t0;
  engine.session.setTier(tier.level);
  return TierState(tier: tier, benchmark: result, overridden: override != null);
});
