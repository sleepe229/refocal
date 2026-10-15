import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _result(String tier, {double ms = 40}) => {
  'schema': 1,
  'model': 'sr.general-x4v3',
  'tile': 128,
  'backends': <Object>[],
  'selected': 'vulkan:Adreno:fp16',
  'selected_is_gpu': true,
  'tile128_ms': ms,
  'ram_gb': 7.5,
  'tier': tier,
  'reasons': ['fast'],
  'below_t0_budget': false,
};

void main() {
  late RefocalDatabase db;
  late TierRepository repo;
  setUp(() {
    db = RefocalDatabase.memory();
    repo = TierRepository(db);
  });
  tearDown(() => db.close());

  test('results are cached by app, model, driver, GPU, OS build and gate version', () async {
    final k1 = TierRepository.key(
      appVersion: '0.2.0',
      modelVersion: 'sr.general-x4v3@1',
      driverVersion: '512.1',
      gpuDeviceId: '5143:43050a01',
      osBuild: 'AP2A.1',
    );
    expect(k1, endsWith('|${TierRepository.gateVersion}'));
    expect(await repo.get(k1), isNull);
    final r = await repo.put(k1, _result('T1'));
    expect((r.tier, r.gpu, r.tile128Ms), (DeviceTier.t1, true, 40));
    expect((await repo.get(k1))!.tier, DeviceTier.t1);
    final k2 = k1.replaceFirst('512.1', '512.2'); // a driver update
    expect(await repo.get(k2), isNull);
    await repo.put(k2, _result('T2', ms: 20));
    expect(await repo.get(k1), isNull, reason: 'one device: the old result is gone');
  });

  test('anything the core did not write is rejected', () {
    expect(() => BenchmarkResult.fromJson({..._result('T1'), 'tier': 'T9'}), throwsFormatException);
    expect(() => BenchmarkResult.fromJson({..._result('T1'), 'schema': 2}), throwsFormatException);
    expect(DeviceTier.parse('T2'), DeviceTier.t2);
    expect(DeviceTier.t1.level, 1);
  });
}
