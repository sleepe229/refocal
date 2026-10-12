import 'package:flutter/material.dart';

/// Before/after slider over two images of the same aspect ratio (0.1: previews; the tiled
/// zoomable CompareViewer is S7).
class CompareSlider extends StatefulWidget {
  const CompareSlider({
    super.key,
    required this.before,
    required this.after,
    required this.aspectRatio,
  });

  final ImageProvider before, after;
  final double aspectRatio;

  @override
  State<CompareSlider> createState() => _CompareSliderState();
}

class _CompareSliderState extends State<CompareSlider> {
  double _pos = 0.5;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: LayoutBuilder(
        builder: (context, c) {
          void move(Offset local) => setState(() => _pos = (local.dx / c.maxWidth).clamp(0.0, 1.0));
          return Semantics(
            label: 'Before and after comparison',
            value: '${(_pos * 100).round()}% original',
            increasedValue: '${((_pos + 0.1).clamp(0, 1) * 100).round()}% original',
            decreasedValue: '${((_pos - 0.1).clamp(0, 1) * 100).round()}% original',
            onIncrease: () => setState(() => _pos = (_pos + 0.1).clamp(0.0, 1.0)),
            onDecrease: () => setState(() => _pos = (_pos - 0.1).clamp(0.0, 1.0)),
            child: GestureDetector(
              onHorizontalDragUpdate: (d) => move(d.localPosition),
              onTapDown: (d) => move(d.localPosition),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(image: widget.after, fit: BoxFit.contain, gaplessPlayback: true),
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
                  const Positioned(left: 8, top: 8, child: _Tag('Original')),
                  const Positioned(right: 8, top: 8, child: _Tag('Enhanced')),
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
