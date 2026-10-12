import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

void main() {
  test('known codes round-trip', () {
    for (final s in EnhStatus.values) {
      expect(EnhStatus.fromCode(s.code), s);
    }
  });

  test('unknown code maps to internal instead of throwing', () {
    expect(EnhStatus.fromCode(13), EnhStatus.internal);
    expect(EnhStatus.fromCode(-1), EnhStatus.internal);
  });
}
