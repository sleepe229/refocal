// TEST-UNIT-008: Auto v1 rules (FR-ENH-007), deterministic.
import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

PhotoAnalysis photo({double mp = 1, double noise = 4, int faces = 0, bool detector = true}) {
  final w = 1000, h = (mp * 1e6 / 1000).round();
  return PhotoAnalysis(
    width: w,
    height: h,
    noiseSigma: noise,
    faces: faces,
    largestFacePx: faces > 0 ? 200 : 0,
    detector: detector,
  );
}

const _all = AutoModels(
  standard: 'sr.general-x4v3',
  none: 'sr.general-x4v3-dn0',
  strong: 'sr.general-x4v3-dn100',
  facePack: 'face.gfpgan-1.4',
);
const _bundled = AutoModels(standard: 'sr.general-x4v3');
const _auto = AutoPolicy();

void main() {
  test('the same input gives the same decision', () {
    final a = _auto.decide(photo(mp: 6, noise: 9, faces: 2), DeviceTier.t1, _all);
    final b = _auto.decide(photo(mp: 6, noise: 9, faces: 2), DeviceTier.t1, _all);
    expect(a.recipe, b.recipe);
    expect(a.reasons, b.reasons);
  });

  test('scale by size and tier (ADR-0014, 05 §3)', () {
    Recipe r(double mp, DeviceTier t) => _auto.decide(photo(mp: mp), t, _bundled).recipe;
    expect((r(1, DeviceTier.t1).scale, r(1, DeviceTier.t1).fast2), (4, false));
    expect((r(5, DeviceTier.t1).scale, r(5, DeviceTier.t1).fast2), (2, false));
    expect(r(5, DeviceTier.t0).fast2, isTrue);
    expect((r(12, DeviceTier.t1).scale, r(12, DeviceTier.t1).fast2), (2, true));
    expect(r(12, DeviceTier.t2).fast2, isFalse);
  });

  test('denoise by the noise estimate, with the levels installed (ADR-0015)', () {
    String m(double noise, AutoModels models) =>
        _auto.decide(photo(noise: noise), DeviceTier.t1, models).recipe.srModel;
    expect(m(1, _all), 'sr.general-x4v3-dn0');
    expect(m(4, _all), 'sr.general-x4v3');
    expect(m(12, _all), 'sr.general-x4v3-dn100');
    expect(m(1, _bundled), 'sr.general-x4v3', reason: 'only the built-in level');
    expect(m(12, _bundled), 'sr.general-x4v3');
  });

  test('faces when found and the pack is there; T0 only one face; large on T0: only faces', () {
    AutoDecision d(int faces, DeviceTier t, {double mp = 2, AutoModels m = _all}) =>
        _auto.decide(photo(faces: faces, mp: mp), t, m);
    expect(d(2, DeviceTier.t1).recipe.faceModel, 'face.gfpgan-1.4');
    expect(d(2, DeviceTier.t1).recipe.faceStrength, Recipe.defaultFaceStrength);
    expect(d(2, DeviceTier.t1).reasons, contains(AutoReason.faces));
    expect(d(2, DeviceTier.t1, m: _bundled).recipe.faceModel, isNull, reason: 'no pack');
    expect(d(0, DeviceTier.t1).recipe.faceModel, isNull);
    expect(d(2, DeviceTier.t0).recipe.faceModel, isNull);
    expect(d(2, DeviceTier.t0).reasons, contains(AutoReason.tooManyFacesForTier));
    expect(d(1, DeviceTier.t0).recipe.faceModel, 'face.gfpgan-1.4');
    final big = d(1, DeviceTier.t0, mp: 12).recipe;
    expect((big.facesOnly, big.fast2), (true, false));
  });

  test('analysis JSON as the core writes it', () {
    final a = PhotoAnalysis.fromJson(const {
      'schema': 1,
      'width': 675,
      'height': 900,
      'megapixels': 0.6075,
      'noise_sigma': 1.87,
      'faces': {
        'count': 1,
        'largest_px': 431,
        'detector': true,
        'boxes': [
          [120, 88, 431, 402],
        ],
      },
    });
    expect((a.faces, a.megapixels), (1, 0.6075));
    expect(a.boxes, [const FaceBox(120, 88, 431, 402)]);
    expect(
      () => PhotoAnalysis.fromJson(const {
        'schema': 1,
        'width': 1,
        'height': 1,
        'noise_sigma': 0,
        'faces': {
          'count': 1,
          'largest_px': 1,
          'detector': true,
          'boxes': [
            [1, 2, -3, 4],
          ],
        },
      }),
      throwsFormatException,
    );
    expect(() => PhotoAnalysis.fromJson(const {'schema': 2}), throwsFormatException);
  });
}
