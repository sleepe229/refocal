import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/features/editor/fragment_preview.dart';
import 'package:refocal_core/refocal_core.dart';

void main() {
  Recipe r(int scale, {bool fast2 = false}) => Recipe(scale: scale, fast2: fast2, srModel: 'sr.x');

  test('the part gives at most 512 px of the result (FR-ENH-015)', () {
    expect(FragmentPreview.cropFor(r(4), 4000, 3000, const Offset(0.5, 0.5)), (
      x: 1936,
      y: 1436,
      w: 128,
      h: 128,
    ));
    expect(FragmentPreview.cropFor(r(2), 4000, 3000, const Offset(0.5, 0.5)).w, 256);
    expect(FragmentPreview.cropFor(r(2, fast2: true), 4000, 3000, const Offset(0.5, 0.5)).w, 256);
    expect(FragmentPreview.cropFor(r(1), 4000, 3000, const Offset(0.5, 0.5)).w, 512);
  });

  test('the part stays inside the photo', () {
    expect(FragmentPreview.cropFor(r(4), 4000, 3000, Offset.zero), (x: 0, y: 0, w: 128, h: 128));
    expect(FragmentPreview.cropFor(r(4), 4000, 3000, const Offset(1, 1)), (
      x: 3872,
      y: 2872,
      w: 128,
      h: 128,
    ));
    // A photo smaller than the part: all of it.
    expect(FragmentPreview.cropFor(r(1), 300, 200, const Offset(0.3, 0.9)), (
      x: 0,
      y: 0,
      w: 300,
      h: 200,
    ));
  });
}
