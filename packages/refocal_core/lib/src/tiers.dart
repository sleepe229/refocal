import 'dart:convert';


import 'db/database.dart';

/// Device tiers (ADR-0017, 02 §1, 05 §6).
enum DeviceTier {
  t0,
  t1,
  t2;

  /// As the core takes it (enh_set_tier) and reports it ("T0".."T2").
  int get level => index;
  String get label => 'T$index';

  static DeviceTier? parse(String? s) => values.where((t) => t.label == s).firstOrNull;
}

/// A benchmark result (enh_benchmark JSON), read once.
class BenchmarkResult {
  BenchmarkResult({
    required this.tier,
    required this.backend,
    required this.gpu,
    required this.tile128Ms,
    required this.reasons,
    required this.belowT0Budget,
  });

  /// Throws [FormatException] for anything the core did not write.
  factory BenchmarkResult.fromJson(Map<String, Object?> j) {
    if (j case {
      'schema': 1,
      'tier': final String tier,
      'selected': final String backend,
      'selected_is_gpu': final bool gpu,
      'tile128_ms': final num ms,
      'reasons': final List<Object?> reasons,
      'below_t0_budget': final bool below,
    }) {
      return BenchmarkResult(
        tier: DeviceTier.parse(tier) ?? (throw FormatException('bad tier', tier)),
        backend: backend,
        gpu: gpu,
        tile128Ms: ms.toDouble(),
        reasons: [for (final r in reasons) r is String ? r : throw FormatException('bad reason')],
        belowT0Budget: below,
      );
    }
    throw FormatException('not a benchmark result', j);
  }

  final DeviceTier tier;

  /// The fastest backend that passed the GPU gate (05 §6.3: not "GPU first").
  final String backend;
  final bool gpu;
  final double tile128Ms;
  final List<String> reasons;

  /// Slower than the T0 budget of NFR-PERF-001.
  final bool belowT0Budget;
}

/// Benchmark results by what they depend on (05 §6.2): a new app, model, GPU driver, OS build
/// or gate version runs the benchmark again.
class TierRepository {
  TierRepository(this._db);

  final RefocalDatabase _db;

  /// Bumped when the benchmark or the gate changes how it judges.
  static const gateVersion = 1;

  static String key({
    required String appVersion,
    required String modelVersion,
    required String driverVersion,
    required String gpuDeviceId,
    required String osBuild,
  }) => [appVersion, modelVersion, driverVersion, gpuDeviceId, osBuild, '$gateVersion'].join('|');

  /// The cached result for [key], or null (none, or one this version cannot read).
  Future<BenchmarkResult?> get(String key) async {
    final row = await (_db.select(
      _db.benchmarkCache,
    )..where((b) => b.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    try {
      return BenchmarkResult.fromJson((jsonDecode(row.json) as Map).cast());
    } on FormatException {
      return null;
    }
  }

  /// Stores [json] (the core's result) for [key]; older keys are dropped (one device).
  Future<BenchmarkResult> put(String key, Map<String, Object?> json, {DateTime? now}) =>
      _db.transaction(() async {
        final r = BenchmarkResult.fromJson(json);
        await _db.delete(_db.benchmarkCache).go();
        await _db
            .into(_db.benchmarkCache)
            .insert(
              BenchmarkCacheCompanion.insert(
                key: key,
                json: jsonEncode(json),
                createdAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
              ),
            );
        return r;
      });
}
