import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/features/report/bad_result.dart';
import 'package:refocal_core/refocal_core.dart';

void main() {
  final result = JobResult.fromJson({
    'job_id': 'job-1',
    'job_dir': '/data/user/0/io.github.refocal.app/files/jobs/job-1',
    'width': 4000,
    'height': 3000,
    'backend': 'vulkan_fp16',
    'fallbacks': ['tile:256->128'],
    'scale': 4,
    'fast2': false,
    'model': 'sr.general-x4v3',
    'input': {'width': 1000, 'height': 750},
    'timings_ms': {'total': 4321},
  });
  final request = JobRequest(
    input: '/data/user/0/io.github.refocal.app/files/inbox/in-abc.jpg',
    scale: 4,
    srModel: 'sr.general-x4v3',
    faceModel: 'face.gfpgan-1.4',
    facesOff: const [FaceBox(1, 2, 3, 4)],
  );

  test('the report has the parameters, never a path or the photo (FR-REP-002)', () {
    final body = badResultBody(
      kind: BadResultKind.otherFace,
      comment: '  The eyes changed  ',
      app: '0.5.0',
      os: 'android 15',
      device: 'SM8550, 7.5 GB',
      tier: 'T2',
      result: result,
      request: request,
    );
    for (final want in [
      '**Category:** otherFace',
      'The eyes changed',
      '| Model | sr.general-x4v3 |',
      '| Mode | 4x |',
      '| Faces | face.gfpgan-1.4, strength 50%, 1 off |',
      '| Backend | vulkan_fp16 |',
      '| Fallbacks | tile:256->128 |',
      '| Time | 4321 ms |',
      '| Device | SM8550, 7.5 GB (T2) |',
    ]) {
      expect(body, contains(want));
    }
    expect(body, isNot(contains('/data/')));
    expect(body, isNot(contains('job-1')));
  });

  test('the issue is pre-filled with the label of 15 §5', () {
    final uri = badResultIssue(BadResultKind.color, 'text & more');
    expect(uri.scheme, 'https');
    expect(uri.path, '/sleepe229/refocal/issues/new');
    expect(uri.queryParameters, {
      'labels': 'bad-result',
      'title': 'Bad result: color',
      'body': 'text & more',
    });
  });
}
