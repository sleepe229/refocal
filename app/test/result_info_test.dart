import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/l10n/app_localizations.dart';
import 'package:refocal/ui_kit/labels.dart';
import 'package:refocal_core/refocal_core.dart';

JobResult _result({String model = 'sr.general-x4v3', String backend = 'cpu:4', int? ms = 12400}) =>
    JobResult.fromJson({
      'job_id': 'j',
      'job_dir': '/w/j',
      'width': 400,
      'height': 300,
      'backend': backend,
      'scale': 4,
      'fast2': false,
      'model': model,
      'input': {'width': 100, 'height': 75},
      if (ms != null) 'timings_ms': {'total': ms},
    });

void main() {
  final ru = lookupAppLocalizations(const Locale('ru'));

  test('what made the result (FR-CMP-007)', () {
    expect(
      resultInfo(ru, _result()),
      'Шумоподавление: Обычное · processor · 12 с'.replaceFirst('processor', ru.tierCpu),
    );
    expect(
      resultInfo(ru, _result(model: 'sr.general-x4v3-dn100', backend: 'vulkan_fp16', ms: 300)),
      'Шумоподавление: Сильное · ${ru.tierGpu} · 1 с',
    );
    expect(
      resultInfo(ru, _result(model: 'face.gfpgan-1.4', backend: 'lanczos', ms: null)),
      'face.gfpgan-1.4 · Только лица',
    );
  });
}
