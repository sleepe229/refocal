import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

void main() {
  test('a recipe becomes a request with a fresh id, and back without its strength', () {
    final r = Recipe(scale: 2, fast2: true, srModel: 'sr.m', strength: 0.4);
    final a = JobRequest.of(r, '/in/a.jpg'), b = JobRequest.of(r, '/in/a.jpg');
    expect(a.id, isNot(b.id), reason: 'two photos picked in the same millisecond');
    expect(a.id, matches(RegExp(r'^job-[0-9a-f]{32}$')));
    expect(a.recipe(), Recipe(scale: 2, fast2: true, srModel: 'sr.m'));
    expect(a.recipe(strength: 0.4), r);
  });

  test('reads request.json as the core rewrites it', () {
    final j = {
      ...JobRequest(id: 'job-1', input: '/in/a.jpg', scale: 4, srModel: 'sr.m').toJson(),
      'scale': 2, // lowered after NEEDS_USER
      'tile': 256,
      'max_output_mp': 200.0,
    };
    final r = JobRequest.fromJson(j);
    expect((r.id, r.input, r.scale, r.fast2, r.srModel), ('job-1', '/in/a.jpg', 2, false, 'sr.m'));
  });

  test('faces go to the core and come back; the core writes "" for none', () {
    final r = Recipe(scale: 4, srModel: 'sr.m', faceModel: 'face.g', faceStrength: 0.3);
    final q = JobRequest.of(r, '/in/a.jpg', id: 'job-f');
    expect(q.toJson(), containsPair('face_model', 'face.g'));
    expect(q.toJson(), containsPair('face_strength', 0.3));
    expect(JobRequest.fromJson(q.toJson()).recipe(), r);
    final only = Recipe(scale: 2, srModel: 'm', faceModel: 'face.g', facesOnly: true);
    final oq = JobRequest.of(only, '/a');
    expect(oq.toJson(), containsPair('background', 'lanczos'));
    expect(JobRequest.fromJson(oq.toJson()).recipe(), only);
    expect(Recipe.fromJson(only.toJson()), only);
    expect(() => Recipe(scale: 2, srModel: 'm', facesOnly: true), throwsArgumentError);
    final none = JobRequest.fromJson({
      ...JobRequest(id: 'job-n', input: '/a', scale: 4, srModel: 'm').toJson(),
      'face_model': '',
      'det_model': 'det.yunet-2023mar',
      'face_strength': 0.5,
    });
    expect(none.faceModel, isNull);
  });

  test('rejects what the core would not run or this version did not write', () {
    final ok = JobRequest(id: 'job-1', input: '/a', scale: 4, srModel: 'm').toJson();
    expect(() => JobRequest(id: '../x', input: '/a', scale: 4, srModel: 'm'), throwsArgumentError);
    expect(() => JobRequest(input: '/a', scale: 3, srModel: 'm'), throwsArgumentError);
    for (final bad in [
      {...ok, 'schema': 2},
      {...ok, 'scale': 3},
      {...ok, 'job_id': 'a/b'},
      {...ok}..remove('sr_model'),
    ]) {
      expect(() => JobRequest.fromJson(bad), throwsFormatException, reason: '$bad');
    }
  });

  test('faces turned off go to the core and come back (FR-FACE-007)', () {
    final r = Recipe(scale: 2, srModel: 'sr.x', faceModel: 'face.y');
    final q = JobRequest.of(r, '/in.jpg', facesOff: const [FaceBox(10, 20, 30, 40)]);
    expect(q.toJson()['faces_off'], [
      [10.0, 20.0, 30.0, 40.0],
    ]);
    expect(JobRequest.fromJson(q.toJson()).facesOff, const [FaceBox(10, 20, 30, 40)]);
    // Not part of the recipe (a preset or history entry is for any photo).
    expect(JobRequest.fromJson(q.toJson()).recipe(), r);
    // Without face restoration nothing is turned off.
    expect(
      JobRequest.of(Recipe(scale: 2, srModel: 'sr.x'), '/in.jpg').toJson(),
      isNot(contains('faces_off')),
    );
    expect(() => JobRequest.fromJson({...q.toJson(), 'faces_off': 'x'}), throwsFormatException);
  });

  test('a fragment preview crops (FR-ENH-015)', () {
    final r = Recipe(scale: 4, srModel: 'sr.x');
    final q = JobRequest.of(r, '/in.jpg', crop: (x: 10, y: 20, w: 128, h: 96));
    expect(q.toJson()['crop'], [10, 20, 128, 96]);
    expect(JobRequest.fromJson(q.toJson()).crop, (10, 20, 128, 96));
    expect(JobRequest.of(r, '/in.jpg').toJson(), isNot(contains('crop')));
    expect(() => JobRequest.of(r, '/in.jpg', crop: (x: 0, y: 0, w: 8, h: 8)), throwsArgumentError);
  });
}
