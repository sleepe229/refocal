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
}
