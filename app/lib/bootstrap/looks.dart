import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import 'engine.dart';

/// FR-LOOK-*: the core's data for previewing a look, so the editor shows what the export
/// writes (ADR-0012 amendment 0.8).
extension LookPreview on Engine {
  /// The look's colour matrix as a filter; null when it changes no colour.
  ColorFilter? lookFilter(Look? look) => look == null || look.id == LookId.none || look.amount == 0
      ? null
      : ColorFilter.matrix(native.lookMatrix(look.id, look.amount));
}

/// The leak overlay of a [width] x [height] result as an image (a few hundred pixels).
final lookLeaksProvider = FutureProvider.autoDispose.family<ui.Image, (int, int)>((
  ref,
  size,
) async {
  final engine = await ref.watch(engineProvider.future);
  final g = engine.native.lookLeaks(size.$1, size.$2);
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(g.rgba, g.width, g.height, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  ref.onDispose(image.dispose);
  return image;
});
