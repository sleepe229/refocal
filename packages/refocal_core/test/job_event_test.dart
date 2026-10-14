import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

void main() {
  test('decodes progress and terminal events', () {
    final p = JobEvent.fromNative(2, 3, 10, {'eta_ms': 1500}) as ProgressEvent;
    expect(p.fraction, closeTo(0.3, 1e-9));
    expect(p.eta, const Duration(milliseconds: 1500));
    expect((JobEvent.fromNative(2, 0, 0, {'eta_ms': -1}) as ProgressEvent).eta, isNull);

    final f = JobEvent.fromNative(7, 0, 0, {'status': 2, 'job_dir': '/w/j'}) as FailedEvent;
    expect(f.status, EnhStatus.paused);
    expect(f.jobDir, '/w/j');
    expect(f.isTerminal, isTrue);

    final d = JobEvent.fromNative(6, 0, 0, {
      'job_id': 'j',
      'job_dir': '/w/j',
      'width': 400,
      'height': 300,
      'preview': {'file': 'preview.jpg'},
      'backend': 'cpu:4',
      'fallbacks': ['vulkan_fp16->vulkan_fp32'],
      'input': {'width': 200, 'height': 150, 'orientation': 6, 'format': 'jpeg'},
      'scale': 2,
      'fast2': true,
      'model': 'sr.general-x4v3',
      'timings_ms': {'sr': 900, 'total': 1200},
    }) as DoneEvent;
    expect(d.result.previewPath, '/w/j/preview.jpg');
    expect(d.result.fallbacks.single, 'vulkan_fp16->vulkan_fp32');
    expect((d.result.scale, d.result.fast2, d.result.model), (2, true, 'sr.general-x4v3'));
    expect((d.result.inputWidth, d.result.inputHeight), (200, 150));
    expect(d.result.duration, const Duration(milliseconds: 1200));
  });

  test('unknown event types and status codes do not throw', () {
    expect(JobEvent.fromNative(42, 0, 0, {}), isNull);
    final f = JobEvent.fromNative(7, 0, 0, {'status': 1234}) as FailedEvent;
    expect(f.status, EnhStatus.internal);
    final n = JobEvent.fromNative(5, 0, 0, {
      'code': 'downscale_required',
      'options': [
        {'scale': 2, 'fast2': true},
      ],
    }) as NeedsUserEvent;
    expect(n.options.single['fast2'], isTrue);
  });
}
