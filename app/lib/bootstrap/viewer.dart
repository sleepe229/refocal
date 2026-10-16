import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../ui_kit/compare_slider.dart';
import 'app_log.dart';
import 'engine.dart';

/// The core's tiles of a finished job (06 §5) as images for the compare viewer.
class ViewerTiles implements CompareTiles {
  const ViewerTiles(this.viewer);
  final RefocalViewer viewer;

  @override
  Future<ui.Image> tile(int source, int x, int y, int w, int h, int factor) async {
    final t = await viewer.render(source, x, y, w, h, factor);
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(t.rgba, t.width, t.height, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }
}

/// Opened while the result of [jobDir] is shown; closed with it.
final viewerTilesProvider = FutureProvider.autoDispose.family<CompareTiles?, String>((
  ref,
  jobDir,
) async {
  final engine = await ref.watch(engineProvider.future);
  try {
    final v = await RefocalViewer.open(engine.native, jobDir);
    ref.onDispose(v.close);
    return ViewerTiles(v);
  } on EnhException catch (e) {
    AppLog.warn('viewer: ${e.status.name}'); // the previews still zoom
    return null;
  }
});
