import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Before/after slider over two images of the same aspect ratio (0.1: previews; the tiled
/// zoomable CompareViewer is S7). [strength] < 1 previews the export blend (FR-ENH-005): the
/// result drawn over the original at that opacity is the same lerp the core applies.
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.before,
    required this.after,
    required this.aspectRatio,
    this.strength = 1,
  });

  final ImageProvider before, after;
  final double aspectRatio, strength;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  double _pos = 0.5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String pct(double v) => l10n.comparePercentOriginal((v.clamp(0.0, 1.0) * 100).round());
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: LayoutBuilder(
        builder: (context, c) {
          void move(Offset local) => setState(() => _pos = (local.dx / c.maxWidth).clamp(0.0, 1.0));
          return Semantics(
            label: l10n.compareLabel,
            value: pct(_pos),
            increasedValue: pct(_pos + 0.1),
            decreasedValue: pct(_pos - 0.1),
            onIncrease: () => setState(() => _pos = (_pos + 0.1).clamp(0.0, 1.0)),
            onDecrease: () => setState(() => _pos = (_pos - 0.1).clamp(0.0, 1.0)),
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => move(d.localPosition),
              onTapDown: (d) => move(d.localPosition),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.strength < 1)
                    Image(
                      image: widget.before,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  Opacity(
                    opacity: widget.strength,
                    child: Image(image: widget.after, fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                  ClipRect(
                    clipper: _LeftClipper(_pos),
                    child: Image(
                      image: widget.before,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  Positioned(
                    left: c.maxWidth * _pos - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: Colors.white70),
                  ),
                  Positioned(left: 8, top: 8, child: _Tag(l10n.tagOriginal)),
                  Positioned(right: 8, top: 8, child: _Tag(l10n.tagEnhanced)),
                ],
              ),
            ),
          );
        },
      ),
    );
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
