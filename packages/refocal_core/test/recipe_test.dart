import 'dart:convert';

import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

// TEST-UNIT-007: serialization and validation of recipes.
void main() {
  Map<String, Object?> roundTrip(Recipe r) =>
      (jsonDecode(jsonEncode(r.toJson())) as Map).cast<String, Object?>();

  test('round trip with and without an output', () {
    final preset = Recipe(scale: 2, fast2: true, srModel: 'sr.general-x4v3', strength: 0.75);
    expect(Recipe.fromJson(roundTrip(preset)), preset);
    final saved = preset.copyWith(output: () => OutputSpec(ExportFormat.webp, quality: 80));
    expect(Recipe.fromJson(roundTrip(saved)), saved);
    final png = Recipe(scale: 4, srModel: 'm', output: OutputSpec(ExportFormat.png, quality: 90));
    expect(png.output!.quality, isNull, reason: 'PNG has no quality');
    expect(Recipe.fromJson(roundTrip(png)), png);
  });

  test('the constructor rejects impossible recipes', () {
    expect(() => Recipe(scale: 3, srModel: 'm'), throwsArgumentError);
    expect(() => Recipe(scale: 4, fast2: true, srModel: 'm'), throwsArgumentError);
    expect(() => Recipe(scale: 4, srModel: ''), throwsArgumentError);
    expect(() => Recipe(scale: 4, srModel: 'm', strength: 1.5), throwsArgumentError);
    expect(() => OutputSpec(ExportFormat.jpeg), throwsArgumentError);
    expect(() => OutputSpec(ExportFormat.jpeg, quality: 59), throwsArgumentError);
  });

  test('faces round-trip; schema 1 recipes (0.0.4 history) read as without faces', () {
    final r = Recipe(scale: 2, srModel: 'm', faceModel: 'face.gfpgan-1.4', faceStrength: 0.3);
    expect(Recipe.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>), r);
    final old = Recipe.fromJson(const {
      'schema': 1,
      'scale': 4,
      'fast2': false,
      'sr_model': 'm',
      'strength': 0.8,
    });
    expect((old.faceModel, old.faceStrength), (null, Recipe.defaultFaceStrength));
    expect(Recipe(scale: 4, srModel: 'm').toJson().containsKey('face_model'), isFalse);
    expect(() => Recipe(scale: 4, srModel: 'm', faceStrength: 2), throwsArgumentError);
  });

  test('anything else is a FormatException', () {
    final good = Recipe(scale: 4, srModel: 'm').toJson();
    for (final bad in <Map<String, Object?>>[
      {...good, 'schema': Recipe.schemaVersion + 1}, // a newer app wrote it
      {...good, 'schema': 1, 'face_model': 'face.x'}, // schema 1 has no faces
      {...good, 'face_model': ''},
      {...good, 'face_model': 'face.x', 'face_strength': 1.5},
      {...good, 'face_model': 'face.x', 'face_strength': '0.5'},
      {...good}..remove('schema'),
      {...good, 'scale': '4'},
      {...good, 'scale': 8},
      {...good, 'strength': -0.1},
      {...good, 'sr_model': null},
      {
        ...good,
        'output': {'format': 'gif'},
      },
      {
        ...good,
        'output': {'format': 'jpeg', 'quality': 101},
      },
      {
        ...good,
        'output': {'format': 'jpeg', 'quality': '90'},
      },
      {...good, 'output': 'jpeg'},
    ]) {
      expect(() => Recipe.fromJson(bad), throwsFormatException, reason: '$bad');
    }
  });

  test('WebP size limits match the core', () {
    expect(ExportFormat.webp.maxMegapixels, 50);
    expect(ExportFormat.webpLossless.maxMegapixels, 24);
    expect(ExportFormat.png.maxMegapixels, double.infinity);
  });
}
