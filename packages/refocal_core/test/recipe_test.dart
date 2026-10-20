import 'dart:convert';

import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

// TEST-UNIT-007: serialization and validation of recipes.
void main() {
  test('CodeFormer fidelity survives JSON and reaches the job request (FR-FACE-005)', () {
    final r = Recipe(scale: 2, srModel: 'm', faceModel: 'face.codeformer', faceFidelity: 0.3);
    final back = Recipe.fromJson(r.toJson());
    expect(back, r);
    expect(back.faceFidelity, 0.3);
    expect(JobRequest.of(r, '/in.jpg').toJson()['face_fidelity'], 0.3);
    // The default is not written, and old recipes read with it.
    final d = Recipe(scale: 2, srModel: 'm', faceModel: 'face.gfpgan-1.4');
    expect(d.toJson().containsKey('face_fidelity'), isFalse);
    expect(Recipe.fromJson(d.toJson()).faceFidelity, Recipe.defaultFaceFidelity);
    expect(() => Recipe(scale: 2, srModel: 'm', faceFidelity: 1.5), throwsArgumentError);
    expect(() => Recipe.fromJson({...r.toJson(), 'face_fidelity': 2}), throwsFormatException);
  });

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
    expect(() => Recipe(scale: 8, fast2: true, srModel: 'm'), throwsArgumentError);
    expect(Recipe(scale: 8, srModel: 'm').scale, 8); // ADR-0014: x4 twice
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

  test('JPEG cleanup round-trips as schema 3; without it the recipe stays schema 2 (S9)', () {
    final r = Recipe(scale: 2, srModel: 'm', jpegModel: 'jpeg.fbcnn', jpegQf: 0.7);
    expect(r.toJson()['schema'], 3);
    expect(Recipe.fromJson(roundTrip(r)), r);
    final auto = Recipe(scale: 2, srModel: 'm', jpegModel: 'jpeg.fbcnn');
    expect(auto.toJson().containsKey('jpeg_qf'), isFalse, reason: 'qf from the photo');
    expect(Recipe.fromJson(roundTrip(auto)), auto);
    expect(Recipe(scale: 2, srModel: 'm').toJson()['schema'], 2, reason: 'older apps read it');
    expect(r.copyWith(jpegModel: () => null).jpegModel, isNull);
    expect(() => Recipe(scale: 2, srModel: 'm', jpegModel: ''), throwsArgumentError);
    expect(() => Recipe(scale: 2, srModel: 'm', jpegModel: 'j', jpegQf: 1.2), throwsArgumentError);
    expect(() => Recipe.fromJson({...r.toJson(), 'schema': 2}), throwsFormatException);
    expect(() => Recipe.fromJson({...r.toJson(), 'jpeg_qf': -1}), throwsFormatException);
  });

  test('scratch removal round-trips as schema 4, both packs or neither (S9)', () {
    final r = Recipe(
      scale: 2,
      srModel: 'm',
      jpegModel: 'jpeg.fbcnn',
      scratchModel: 'old.scratch',
      inpaintModel: 'old.inpaint-migan',
    );
    expect(r.toJson()['schema'], 4);
    expect(Recipe.fromJson(roundTrip(r)), r);
    expect(r.copyWith(scratches: () => null).toJson()['schema'], 3);
    expect(r.copyWith(scratches: () => ('a.b', 'c.d')).inpaintModel, 'c.d');
    expect(() => Recipe(scale: 2, srModel: 'm', scratchModel: 'old.scratch'), throwsArgumentError);
    expect(() => Recipe.fromJson({...r.toJson(), 'schema': 3}), throwsFormatException);
    expect(() => Recipe.fromJson({...r.toJson(), 'inpaint_model': null}), throwsFormatException);
    final q = JobRequest.of(r, '/in.jpg', id: 'j1');
    expect(q.toJson()['inpaint_model'], 'old.inpaint-migan');
    expect(JobRequest.fromJson({...q.toJson(), 'scale': 2}).recipe(), r);
    final none = JobRequest.fromJson({
      ...JobRequest.of(Recipe(scale: 2, srModel: 'm'), '/in.jpg', id: 'j2').toJson(),
      'scratch_model': '',
      'inpaint_model': '',
    });
    expect(none.scratchModel, isNull, reason: 'the core writes "" for off');
  });

  test('low light round-trips as schema 5 (S9)', () {
    final r = Recipe(scale: 2, srModel: 'm', lowlightModel: 'old.lowlight-cidnet');
    expect(r.toJson()['schema'], 5);
    expect(Recipe.fromJson(roundTrip(r)), r);
    expect(r.copyWith(lowlightModel: () => null).toJson()['schema'], 2);
    expect(() => Recipe(scale: 2, srModel: 'm', lowlightModel: ''), throwsArgumentError);
    expect(() => Recipe.fromJson({...r.toJson(), 'schema': 4}), throwsFormatException);
    final q = JobRequest.of(r, '/in.jpg', id: 'j3');
    expect(q.toJson()['lowlight_model'], 'old.lowlight-cidnet');
    expect(JobRequest.fromJson({...q.toJson(), 'lowlight_model': ''}).lowlightModel, isNull);
  });

  test('a look round-trips as schema 6; one that changes nothing is dropped (FR-LOOK-*)', () {
    final look = Look(LookId.pastel, amount: 0.8, leaks: true);
    final r = Recipe(scale: 2, srModel: 'm', look: look);
    expect(r.toJson()['schema'], 6);
    expect(r.toJson()['look'], {'id': 'pastel', 'amount': 0.8, 'leaks': true});
    expect(Recipe.fromJson(roundTrip(r)), r);
    expect(r.copyWith(look: () => null).toJson()['schema'], 2);
    expect(Recipe(scale: 2, srModel: 'm', look: Look(LookId.none)).look, isNull);
    expect(Recipe(scale: 2, srModel: 'm', look: Look(LookId.pastel, amount: 0)).look, isNull);
    expect(Recipe(scale: 2, srModel: 'm', look: Look(LookId.none, leaks: true)).look, isNotNull);
    expect(() => Look(LookId.pastel, amount: 1.5), throwsArgumentError);
    expect(() => Recipe.fromJson({...r.toJson(), 'schema': 5}), throwsFormatException);
    for (final bad in [
      'pastel',
      {'id': 'vivid', 'amount': 1, 'leaks': false},
      {'id': 'pastel', 'amount': 2, 'leaks': false},
      {'id': 'pastel', 'amount': 1},
    ]) {
      expect(() => Recipe.fromJson({...r.toJson(), 'look': bad}), throwsFormatException);
    }
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
      {...good, 'scale': 16},
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
    expect(ExportFormat.heic.maxMegapixels, 50);
    expect(ExportFormat.heic.hasQuality, isTrue);
  });
}
