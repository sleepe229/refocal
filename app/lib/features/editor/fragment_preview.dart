import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/job_store.dart';
import '../../bootstrap/queue.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/compare_slider.dart';
import '../../ui_kit/errors.dart';

/// FR-ENH-015: the recipe on one part of the photo before the whole of it, at most
/// [resultSide] x [resultSide] px of the result.
abstract final class FragmentPreview {
  static const resultSide = 512;

  /// The part of the oriented input [w] x [h] around [centre] (0..1 of each side) whose result
  /// is at most [resultSide] px per side.
  static ({int x, int y, int w, int h}) cropFor(Recipe r, int w, int h, Offset centre) {
    final perInput = r.fast2 ? 2 : r.scale; // result px per input px
    final side = math.max(16, resultSide ~/ perInput);
    final cw = math.min(side, w), ch = math.min(side, h);
    final x = (centre.dx * w - cw / 2).round().clamp(0, w - cw);
    final y = (centre.dy * h - ch / 2).round().clamp(0, h - ch);
    return (x: x, y: y, w: cw, h: ch);
  }
}

/// Runs the fragment, shows it against the original, and returns true when the user asks
/// to enhance the whole photo. The fragment's job is deleted when the sheet closes.
Future<bool> showFragmentPreview(
  BuildContext context, {
  required String input,
  required Recipe recipe,
  required ({int x, int y, int w, int h}) crop,
  List<FaceBox> facesOff = const [],
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FragmentSheet(input, recipe, crop, facesOff),
    ) ??
    false;

class _Fragment {
  const _Fragment(this.result, this.original, this.elapsed);
  final JobResult result;
  final ImageProvider original;
  final Duration elapsed;
}

class _FragmentSheet extends ConsumerStatefulWidget {
  const _FragmentSheet(this.input, this.recipe, this.crop, this.facesOff);
  final String input;
  final Recipe recipe;
  final ({int x, int y, int w, int h}) crop;
  final List<FaceBox> facesOff;

  @override
  ConsumerState<_FragmentSheet> createState() => _FragmentSheetState();
}

class _FragmentSheetState extends ConsumerState<_FragmentSheet> {
  late final Future<_Fragment> _run = _start();
  String? _jobDir;
  RefocalJob? _job;
  JobStore? _jobs;

  Future<_Fragment> _start() async {
    final engine = await ref.read(engineProvider.future);
    _jobs = await ref.read(jobStoreProvider.future);
    final watch = Stopwatch()..start();
    final request = JobRequest.of(
      widget.recipe,
      widget.input,
      id: '${JobStore.previewPrefix}${newId()}',
      facesOff: widget.facesOff,
      crop: widget.crop,
    );
    _jobDir = '${engine.jobsDir}/${request.id}';
    final job = _job = engine.session.start(request.toJson());
    final result = await job.done;
    final elapsed = watch.elapsed;
    AppLog.info('fragment ${widget.crop.w}x${widget.crop.h}: ${elapsed.inMilliseconds} ms');
    // The original under the same part, scaled to the result by the core (06 §5).
    final viewer = await RefocalViewer.open(engine.native, result.jobDir);
    try {
      final t = await viewer.render(1, 0, 0, result.width, result.height, 1);
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(t.rgba, t.width, t.height, ui.PixelFormat.rgba8888, done.complete);
      final image = await done.future;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return _Fragment(result, MemoryImage(png!.buffer.asUint8List()), elapsed);
    } finally {
      await viewer.close();
    }
  }

  @override
  void dispose() {
    _job?.cancel();
    final dir = _jobDir, jobs = _jobs;
    if (dir != null && jobs != null) unawaited(_cleanup(jobs, dir));
    super.dispose();
  }

  Future<void> _cleanup(JobStore jobs, String dir) async {
    try {
      await _run;
    } on Object {
      // cancelled or failed: its directory goes all the same
    }
    try {
      await jobs.discard(dir, inUse: {widget.input});
    } on FileSystemException catch (e) {
      AppLog.warn('fragment cleanup: ${e.message}'); // the startup sweep removes it
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<_Fragment>(
          future: _run,
          builder: (context, snap) {
            final f = snap.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.fragmentTitle, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (snap.hasError)
                  Text(
                    statusText(l10n, switch (snap.error) {
                      JobFailure(:final status) => status,
                      EnhException(:final status) => status,
                      _ => EnhStatus.internal,
                    }),
                  )
                else if (f == null) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(l10n.fragmentRunning, textAlign: TextAlign.center),
                ] else ...[
                  CompareSlider(
                    before: f.original,
                    after: FileImage(File(f.result.previewPath)),
                    aspectRatio: f.result.width / f.result.height,
                    resultLabel: l10n.resultAlt(f.result.width, f.result.height),
                  ),
                  Text(
                    l10n.fragmentInfo(
                      f.result.width,
                      f.result.height,
                      (f.elapsed.inMilliseconds / 1000).toStringAsFixed(1),
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(l10n.close),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(l10n.fragmentEnhanceAll),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
