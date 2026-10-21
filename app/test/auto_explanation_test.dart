import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/engine.dart';
import 'package:refocal/l10n/app_localizations.dart';
import 'package:refocal/ui_kit/labels.dart';
import 'package:refocal_core/refocal_core.dart';

PhotoAnalysis _photo({
  int w = 2000,
  int h = 1500,
  double noise = 4,
  int faces = 0,
  double eff = 1,
}) => PhotoAnalysis(
  width: w,
  height: h,
  noiseSigma: noise,
  faces: faces,
  largestFacePx: faces > 0 ? 120 : 0,
  detector: true,
  effScale: eff,
);

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  const policy = AutoPolicy();
  const all = AutoModels(
    standard: bundledSrModel,
    none: bundledNoDenoiseModel,
    strong: 'sr.general-x4v3-dn100',
    facePack: 'face.gfpgan-1.4',
  );
  String explain(PhotoAnalysis a, DeviceTier t, AutoModels m) =>
      autoExplanation(ru, a, policy.decide(a, t, m));

  test('06 §3.2: scale, faces and denoise in one line', () {
    expect(explain(_photo(faces: 2), DeviceTier.t1, all), '4×, лиц: 2, шумоподавление');
  });

  test('denoise levels name the model Auto chose (ADR-0015)', () {
    expect(explain(_photo(noise: 1), DeviceTier.t1, all), '4×, без шумоподавления');
    expect(explain(_photo(noise: 12), DeviceTier.t1, all), '4×, сильное шумоподавление');
    // Without the Compact+ packs the built-in 0.5 runs whatever the noise.
    const bundled = AutoModels(standard: bundledSrModel);
    expect(explain(_photo(noise: 12), DeviceTier.t1, bundled), '4×, шумоподавление');
  });

  test('faces that are not restored say why', () {
    expect(
      explain(_photo(faces: 3), DeviceTier.t0, all),
      '4×, лиц: 3, не улучшаются на этом телефоне, шумоподавление',
    );
    expect(
      explain(_photo(faces: 1), DeviceTier.t1, const AutoModels(standard: bundledSrModel)),
      '4×, лиц: 1, нет модели лиц, шумоподавление',
    );
    expect(
      explain(_photo(w: 4000, h: 3000, faces: 1), DeviceTier.t0, all),
      '2×, лиц: 1, только лица, шумоподавление',
    );
  });

  test('a blurry photo says it is enhanced at its real sharpness (ADR-0025)', () {
    expect(
      explain(_photo(noise: 1, eff: 0.5), DeviceTier.t1, all),
      '4×, нечёткое фото: улучшено по реальной резкости, без шумоподавления',
    );
    expect(explain(_photo(noise: 1, eff: 0.95), DeviceTier.t1, all), '4×, без шумоподавления');
  });
}
