import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/engine.dart';
import 'package:refocal/bootstrap/presets.dart';
import 'package:refocal/l10n/app_localizations.dart';
import 'package:refocal/ui_kit/labels.dart';
import 'package:refocal_core/refocal_core.dart';

PhotoAnalysis _photo({int w = 2000, int h = 1500, double noise = 4, int faces = 0}) =>
    PhotoAnalysis(
      width: w,
      height: h,
      noiseSigma: noise,
      faces: faces,
      largestFacePx: faces > 0 ? 120 : 0,
      detector: true,
    );

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));
  const policy = AutoPolicy();
  const all = AutoModels(
    standard: bundledSrModel,
    none: 'sr.general-x4v3-dn0',
    strong: 'sr.general-x4v3-dn100',
    facePack: 'face.gfpgan-1.4',
  );
  String explain(PhotoAnalysis a, DeviceTier t, AutoModels m) =>
      autoExplanation(ru, a, policy.decide(a, t, m));

  test('06 §3.2 example: 4×, лиц: 2, денойз средний', () {
    expect(explain(_photo(faces: 2), DeviceTier.t1, all), '4×, лиц: 2, денойз средний');
  });

  test('denoise levels name the model Auto chose (ADR-0015)', () {
    expect(explain(_photo(noise: 1), DeviceTier.t1, all), '4×, без денойза');
    expect(explain(_photo(noise: 12), DeviceTier.t1, all), '4×, денойз сильный');
    // Without the Compact+ packs the built-in 0.5 runs whatever the noise.
    const bundled = AutoModels(standard: bundledSrModel);
    expect(explain(_photo(noise: 12), DeviceTier.t1, bundled), '4×, денойз средний');
  });

  test('faces that are not restored say why', () {
    expect(
      explain(_photo(faces: 3), DeviceTier.t0, all),
      '4×, лиц: 3, на этом устройстве не восстанавливаются, денойз средний',
    );
    expect(
      explain(_photo(faces: 1), DeviceTier.t1, const AutoModels(standard: bundledSrModel)),
      '4×, лиц: 1, модель лиц не установлена, денойз средний',
    );
    expect(
      explain(_photo(w: 4000, h: 3000, faces: 1), DeviceTier.t0, all),
      '2×, лиц: 1, только лица, денойз средний',
    );
  });
}
