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

  test('JPEG cleanup for a low-quality JPEG on T2 with the pack installed (S9)', () {
    PhotoAnalysis jpeg(int q) => PhotoAnalysis(
      width: 1000,
      height: 800,
      noiseSigma: 4,
      faces: 0,
      largestFacePx: 0,
      detector: true,
      jpegQuality: q,
    );
    const withPack = AutoModels(standard: 'sr.general-x4v3', jpegPack: 'jpeg.fbcnn');
    final d = _auto.decide(jpeg(35), DeviceTier.t2, withPack);
    expect(d.recipe.jpegModel, 'jpeg.fbcnn');
    expect(d.recipe.jpegQf, isNull, reason: 'the core reads it from the photo');
    expect(d.reasons, contains(AutoReason.jpegArtifacts));
    expect(_auto.decide(jpeg(85), DeviceTier.t2, withPack).recipe.jpegModel, isNull);
    expect(_auto.decide(jpeg(0), DeviceTier.t2, withPack).recipe.jpegModel, isNull, reason: 'PNG');
    expect(_auto.decide(jpeg(35), DeviceTier.t1, withPack).recipe.jpegModel, isNull);
    expect(_auto.decide(jpeg(35), DeviceTier.t2, _bundled).recipe.jpegModel, isNull);
    expect(
      PhotoAnalysis.fromJson({
        'schema': 1,
        'width': 10,
        'height': 10,
        'noise_sigma': 1,
        'faces': {'count': 0, 'largest_px': 0, 'detector': false, 'boxes': <Object?>[]},
      }).jpegQuality,
      0,
      reason: 'older cores do not write it',
    );
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

  test('a blurry photo runs at its effective resolution; every recipe is sharpened (ADR-0025)', () {
    PhotoAnalysis blurry(double eff, {double mp = 1}) => PhotoAnalysis(
      width: 1000,
      height: (mp * 1000).round(),
      noiseSigma: 1,
      faces: 0,
      largestFacePx: 0,
      detector: true,
      effScale: eff,
    );
    final d = _auto.decide(blurry(0.537), DeviceTier.t1, _all);
    expect((d.recipe.preDown, d.recipe.sharpen), (0.54, AutoPolicy.sharpen));
    expect(d.reasons, contains(AutoReason.blurryPhoto));
    expect(d.recipe.srModel, 'sr.general-x4v3-dn0', reason: 'still clean');
    final sharp = _auto.decide(blurry(0.92), DeviceTier.t1, _all);
    expect((sharp.recipe.preDown, sharp.recipe.sharpen), (1.0, 1.0));
    expect(sharp.reasons, isNot(contains(AutoReason.blurryPhoto)));
    expect(_auto.decide(blurry(0.1), DeviceTier.t1, _all).recipe.preDown, AutoPolicy.minPreDown);
    // >= 8 MP, fast 2x: half the size already, so 0.7 would change nothing: 1, not reported.
    final big = _auto.decide(blurry(0.7, mp: 12), DeviceTier.t1, _all);
    expect((big.recipe.fast2, big.recipe.preDown), (true, 1.0));
    expect(big.reasons, isNot(contains(AutoReason.blurryPhoto)));
    // Region Faces (T0, >= 8 MP, one face): no SR to downscale for.
    final faces = _auto.decide(
      PhotoAnalysis(
        width: 4000,
        height: 3000,
        noiseSigma: 1,
        faces: 1,
        largestFacePx: 200,
        detector: true,
        effScale: 0.3,
      ),
      DeviceTier.t0,
      _all,
    );
    expect((faces.recipe.facesOnly, faces.recipe.preDown), (true, 1.0));
    expect(faces.reasons, isNot(contains(AutoReason.blurryPhoto)));
    expect(
      _auto.decide(blurry(0.45, mp: 12), DeviceTier.t1, _all).reasons,
      contains(AutoReason.blurryPhoto),
    );
    Map<String, Object?> json(Object? eff) => {
      'schema': 1,
      'width': 10,
      'height': 10,
      'noise_sigma': 1,
      'eff_scale': ?eff,
      'faces': {'count': 0, 'largest_px': 0, 'detector': false, 'boxes': <Object?>[]},
    };
    expect(PhotoAnalysis.fromJson(json(null)).effScale, 1.0, reason: 'an older core');
    expect(PhotoAnalysis.fromJson(json(0.5)).effScale, 0.5);
    for (final bad in [0, 1.5, 'x']) {
      expect(() => PhotoAnalysis.fromJson(json(bad)), throwsFormatException);
    }
  });
}
