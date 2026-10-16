import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Tiles of the result (source 0) and of the original scaled to it (source 1): [x], [y], [w],
/// [h] in result pixels, reduced by [factor] (a power of two).
abstract interface class CompareTiles {
  Future<ui.Image> tile(int source, int x, int y, int w, int h, int factor);
}

/// The before/after viewer (06 §5, CompareViewer): two images of the same aspect ratio with a
/// vertical border, zoomable by pinch up to 1:1 pixels of the result and on to 4:1 (nearest);
/// a double tap toggles 1:1 and fit. The previews are the base; past their resolution the
/// visible part is drawn from [tiles] (256 px, rendered on demand, a small LRU cache), so a
/// 48 MP result stays sharp without holding it in memory. [strength] < 1 previews the export
/// blend (FR-ENH-005): the result over the original at that opacity, the core's lerp.
///
/// Accessibility (A11Y-CMP-001, FR-CMP-003, A11Y-GEN-007): the border is adjustable by the
/// screen reader in 10% steps, a "Show original" toggle is the alternative to the gesture,
/// [resultLabel] describes the result ("Result, 4096×3072, enhanced by AI"), and the border's
/// handle is a 48 dp target.
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.before,
    required this.after,
    required this.aspectRatio,
    this.strength = 1,
    this.resultLabel,
    this.tiles,
    this.resultWidth,
    this.resultHeight,
    this.previewSide = 2048,
  });

  final ImageProvider before, after;
  final double aspectRatio, strength;
  final String? resultLabel;

  /// Without tiles (or the result's size) the viewer zooms the previews only.
  final CompareTiles? tiles;
  final int? resultWidth, resultHeight;

  /// The previews' longer side: tiles are drawn once the zoom needs more pixels than that.
  final int previewSide;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  double _pos = 0.5;
  bool _original = false;
  final _tc = TransformationController();
  final _cache = _TileCache(); // its painters repaint when a tile arrives
  Offset? _doubleTapAt;

  @override
  void didUpdateWidget(CompareSlider old) {
    super.didUpdateWidget(old);
    if (old.tiles != widget.tiles) _cache.clear();
  }

  @override
  void dispose() {
    _tc.dispose();
    _cache
      ..clear()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String pct(double v) => l10n.comparePercentOriginal((v.clamp(0.0, 1.0) * 100).round());
    final pos = _original ? 1.0 : _pos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _viewer(l10n, pct, pos),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _original = !_original),
            icon: Icon(_original ? Icons.auto_fix_high : Icons.image_outlined),
            label: Text(_original ? l10n.compareShowResult : l10n.compareShowOriginal),
          ),
        ),
      ],
    );
  }

  /// Screen (device) pixels per result pixel at scale 1, for a viewer [width] wide.
  double _fitDensity(double width) {
    final rw = widget.resultWidth;
    return rw == null ? 1 : width * MediaQuery.devicePixelRatioOf(context) / rw;
  }

  void _toggleZoom(Size size) {
    final at = _doubleTapAt ?? size.center(Offset.zero);
    if (_tc.value.getMaxScaleOnAxis() > 1.01) {
      _tc.value = Matrix4.identity();
      return;
    }
    // 1:1 pixels of the result under the tap (at least 2x when the result is small).
    final s = math.max(2.0, 1 / _fitDensity(size.width));
    _tc.value = Matrix4.identity()
      ..translateByDouble(at.dx * (1 - s), at.dy * (1 - s), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Widget _viewer(AppLocalizations l10n, String Function(double) pct, double pos) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          // Up to 4:1 of the result's pixels (06 §5), and at least 4x of the previews.
          final maxScale = math.max(4.0, 4 / _fitDensity(size.width));
          Widget layer(int source, ImageProvider base) => _Layer(
            source: source,
            base: base,
            controller: _tc,
            size: size,
            widget: widget,
            cache: _cache,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          );
          return Semantics(
            label: l10n.compareLabel,
            hint: widget.resultLabel,
            value: pct(pos),
            increasedValue: pct(_pos + 0.1),
            decreasedValue: pct(_pos - 0.1),
            onIncrease: () => setState(() => _pos = (_pos + 0.1).clamp(0.0, 1.0)),
            onDecrease: () => setState(() => _pos = (_pos - 0.1).clamp(0.0, 1.0)),
            // The images and tags are described by the label, hint and value above.
            child: ExcludeSemantics(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
                      onDoubleTap: () => _toggleZoom(size),
                      child: InteractiveViewer(
                        transformationController: _tc,
                        maxScale: maxScale,
                        child: SizedBox.fromSize(
                          size: size,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (widget.strength < 1) layer(1, widget.before),
                              Opacity(opacity: widget.strength, child: layer(0, widget.after)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // The original left of the border, in screen space over the same zoom.
                    IgnorePointer(
                      child: ClipRect(
                        clipper: _LeftClipper(pos),
                        child: AnimatedBuilder(
                          animation: _tc,
                          builder: (_, child) => Transform(
                            transform: _tc.value,
                            child: SizedBox.fromSize(size: size, child: child),
                          ),
                          child: layer(1, widget.before),
                        ),
                      ),
                    ),
                    Positioned(
                      left: c.maxWidth * pos - 1,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(child: Container(width: 2, color: Colors.white70)),
                    ),
                    // The border's handle (48 dp): dragging it moves the border.
                    Positioned(
                      left: c.maxWidth * pos - 24,
                      top: c.maxHeight / 2 - 24,
                      width: 48,
                      height: 48,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (d) => setState(() {
                          _original = false;
                          _pos = (_pos + d.delta.dx / c.maxWidth).clamp(0.0, 1.0);
                        }),
                        child: const Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white70,
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(Icons.compare_arrows, size: 20, color: Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: IgnorePointer(child: _Tag(l10n.tagOriginal)),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IgnorePointer(child: _Tag(l10n.tagEnhanced)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One side: its preview, and over it the tiles the current zoom needs.
class _Layer extends StatelessWidget {
  const _Layer({
    required this.source,
    required this.base,
    required this.controller,
    required this.size,
    required this.widget,
    required this.cache,
    required this.devicePixelRatio,
  });

  final int source;
  final ImageProvider base;
  final TransformationController controller;
  final Size size;
  final CompareSlider widget;
  final _TileCache cache;
  final double devicePixelRatio;

  @override
  Widget build(BuildContext context) {
    final image = Image(
      image: base,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    final tiles = widget.tiles, rw = widget.resultWidth, rh = widget.resultHeight;
    if (tiles == null || rw == null || rh == null) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        AnimatedBuilder(
          animation: controller,
          builder: (_, _) => CustomPaint(
            painter: _TilesPainter(
              source: source,
              tiles: tiles,
              cache: cache,
              transform: controller.value,
              size: size,
              resultWidth: rw,
              resultHeight: rh,
              previewSide: widget.previewSide,
              devicePixelRatio: devicePixelRatio,
            ),
          ),
        ),
      ],
    );
  }
}

class _TilesPainter extends CustomPainter {
  _TilesPainter({
    required this.source,
    required this.tiles,
    required this.cache,
    required this.transform,
    required this.size,
    required this.resultWidth,
    required this.resultHeight,
    required this.previewSide,
    required this.devicePixelRatio,
  }) : super(repaint: cache);

  static const tileSide = 256;

  final int source, resultWidth, resultHeight, previewSide;
  final CompareTiles tiles;
  final _TileCache cache;
  final Matrix4 transform;
  final Size size;
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size _) {
    final zoom = transform.getMaxScaleOnAxis();
    final k = size.width / resultWidth; // layout px per result px
    final density = k * zoom * devicePixelRatio; // device px per result px
    final previewDensity = previewSide / math.max(resultWidth, resultHeight);
    if (density <= previewDensity * 1.2) return; // the preview has enough pixels
    // The largest power of two of result pixels per device pixel (1 when zoomed past 1:1).
    var factor = 1;
    while (factor * 2 <= 1 / density && factor < 4096) {
      factor *= 2;
    }
    final t = tileSide * factor; // result px per tile
    // The visible part of the layout, in result pixels.
    final inv = Matrix4.inverted(transform);
    final a = MatrixUtils.transformPoint(inv, Offset.zero) / k;
    final b = MatrixUtils.transformPoint(inv, Offset(size.width, size.height)) / k;
    final i0 = math.max(0, a.dx ~/ t), i1 = math.min((resultWidth - 1) ~/ t, b.dx ~/ t);
    final j0 = math.max(0, a.dy ~/ t), j1 = math.min((resultHeight - 1) ~/ t, b.dy ~/ t);
    final paint = Paint()..filterQuality = density > 1 ? FilterQuality.none : FilterQuality.medium;
    for (var j = j0; j <= j1; j++) {
      for (var i = i0; i <= i1; i++) {
        final x = i * t, y = j * t;
        final w = math.min(t, resultWidth - x), h = math.min(t, resultHeight - y);
        final img = cache.get((source, factor, i, j), () => tiles.tile(source, x, y, w, h, factor));
        if (img == null) continue;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(x * k, y * k, w * k, h * k),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TilesPainter old) =>
      old.transform != transform || old.size != size || old.tiles != tiles;
}

typedef _TileKey = (int source, int factor, int i, int j);

/// Loaded tiles, least recently drawn evicted (and disposed) past [capacity]; a tile is asked
/// for once while it loads.
class _TileCache extends ChangeNotifier {
  static const capacity = 96; // 96 x 256 KB
  final _images = <_TileKey, ui.Image>{}; // a LinkedHashMap: insertion order
  final _loading = <_TileKey>{};
  int _generation = 0;

  ui.Image? get(_TileKey key, Future<ui.Image> Function() load) {
    final img = _images.remove(key);
    if (img != null) {
      _images[key] = img; // most recent last
      return img;
    }
    if (_loading.add(key)) {
      final gen = _generation;
      load().then(
        (image) {
          _loading.remove(key);
          if (gen != _generation) return image.dispose();
          _images[key] = image;
          while (_images.length > capacity) {
            _images.remove(_images.keys.first)!.dispose();
          }
          notifyListeners();
        },
        onError: (Object _) => _loading.remove(key), // drawn from the preview meanwhile
      );
    }
    return null;
  }

  void clear() {
    _generation++;
    for (final img in _images.values) {
      img.dispose();
    }
    _images.clear();
    _loading.clear();
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.f);
  final double f;
  @override
  Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width * f, s.height);
  @override
  bool shouldReclip(_LeftClipper old) => old.f != f;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ),
  );
}
