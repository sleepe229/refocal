import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/engine.dart';
import 'package:refocal/bootstrap/models.dart';
import 'package:refocal/bootstrap/presets.dart';
import 'package:refocal/features/models/pack_offer.dart';

void main() {
  const builtIn = {bundledSrModel, bundledDetector};

  test('a mode offers the packs it lacks, in the order they run (06 §3.3)', () {
    expect(missingPacks(BuiltinPreset.quality.recipe, builtIn), isEmpty);
    expect(missingPacks(BuiltinPreset.portrait.recipe, builtIn), [defaultFacePack]);
    expect(missingPacks(BuiltinPreset.oldPhoto.recipe, builtIn), [
      DenoiseLevel.strong.model,
      defaultFacePack,
    ]);
    expect(missingPacks(BuiltinPreset.oldPhoto.recipe, {...builtIn, DenoiseLevel.strong.model}), [
      defaultFacePack,
    ]);
  });

  test('the built-in detector is never offered for download', () {
    expect(missingPacks(BuiltinPreset.portrait.recipe, {bundledSrModel}), [defaultFacePack]);
  });
}
