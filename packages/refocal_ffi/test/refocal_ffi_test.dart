// Host test of the Dart bridge against a real libenh.so (REFOCAL_LIBENH, e.g.
// native/build-host/libenh.so) with a synthetic ncnn model: event port, NEEDS_USER, cancel,
// pause/resume, export. Skipped when REFOCAL_LIBENH is not set.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

// 97x61 JPEG (native/tests/test_pipeline.cpp pattern).
const _jpeg =
    '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';

void main() {
  final lib = Platform.environment['REFOCAL_LIBENH'];
  final skip = lib == null || lib.isEmpty ? 'REFOCAL_LIBENH not set' : null;

  late Directory root;
  late String input;
  late RefocalNative native;
  late RefocalSession session;

  setUpAll(() {
    if (skip != null) return;
    root = Directory.systemTemp.createTempSync('refocal_ffi_test');
    final model = Directory('${root.path}/models/nearest4')..createSync(recursive: true);
    File('${model.path}/model.ncnn.param').writeAsStringSync(
      '7767517\n2 2\nInput in0 0 1 in0\nInterp up 1 1 in0 out0 0=1 1=4.0 2=4.0\n',
    );
    File('${model.path}/model.ncnn.bin').writeAsBytesSync(const []);
    input = '${root.path}/in.jpg';
    File(input).writeAsBytesSync(base64Decode(_jpeg));
    native = RefocalNative.open(path: lib);
    session = native.openSession(
      modelsDir: '${root.path}/models',
      workDir: '${root.path}/jobs',
      backend: EnhBackend.cpu,
    );
  });

  tearDownAll(() async {
    if (skip != null) return;
    await session.dispose();
    root.deleteSync(recursive: true);
  });

  Map<String, Object?> req(String id, {Map<String, Object?> extra = const {}}) => {
    'job_id': id,
    'input': input,
    'sr_model': 'nearest4',
    'tile': 32,
    ...extra,
  };

  test('runs a job over the native port and exports a JPEG', () async {
    final job = session.start(req('ok'));
    final events = <JobEvent>[];
    job.events.listen(events.add);
    final result = await job.done;
    expect(result.width, 388);
    expect(result.height, 244);
    expect(File(result.previewPath).existsSync(), isTrue);
    expect(events.whereType<StageEvent>().map((e) => e.stage), contains(JobStage.upscale));
    final last = events.whereType<ProgressEvent>().last;
    expect(last.done, last.total);
    final out = await session.export(result.jobDir, '${root.path}/out.jpg');
    expect(out['width'], 388);
    expect(File('${root.path}/out.jpg').lengthSync(), greaterThan(1000));
  }, skip: skip);

  test('NEEDS_USER answer path', () async {
    final job = session.start(req('nu', extra: {'max_output_mp': 0.05}));
    job.events.listen((e) {
      if (e is NeedsUserEvent) job.answer(e.options.first);
    });
    final r = await job.done;
    expect(r.width, lessThan(388));
  }, skip: skip);

  test('cancel completes with JobFailure(cancelled)', () async {
    final job = session.start(req('cx', extra: {'max_output_mp': 0.01})); // waits in NEEDS_USER
    await job.events.firstWhere((e) => e is NeedsUserEvent);
    job.cancel();
    await expectLater(
      job.done,
      throwsA(isA<JobFailure>().having((f) => f.status, 'status', EnhStatus.cancelled)),
    );
  }, skip: skip);

  test('invalid request throws EnhException', () {
    expect(() => session.start({'job_id': '../bad', 'input': input}), throwsA(isA<EnhException>()));
  }, skip: skip);
}
