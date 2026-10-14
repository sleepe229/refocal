import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/settings.dart';

void main() {
  test('defaults are private and JPEG 92', () {
    const s = Settings();
    expect(s.keepGps, isFalse);
    expect(s.aiMarker, isTrue);
    expect(s.format, ExportFormat.jpeg);
    expect(s.quality, 92);
    expect(s.languageCode, isNull);
  });

  test('round trip', () {
    final s = const Settings().copyWith(
      keepGps: true,
      format: ExportFormat.webpLossless,
      quality: 75,
      languageCode: () => 'ru',
      onboardingDone: true,
    );
    final r = Settings.fromJson(s.toJson());
    expect(r.keepGps, isTrue);
    expect(r.format, ExportFormat.webpLossless);
    expect(r.quality, 75);
    expect(r.languageCode, 'ru');
    expect(r.onboardingDone, isTrue);
    expect(r.copyWith(languageCode: () => null).languageCode, isNull);
  });

  test('0.0.2 files skip the introduction; bad values fall back', () {
    final v1 = Settings.fromJson({'version': 1, 'keep_gps': false, 'ai_marker': true});
    expect(v1.onboardingDone, isTrue);
    expect(v1.format, ExportFormat.jpeg);
    final bad = Settings.fromJson({'version': 2, 'format': 'gif', 'quality': 5, 'language': 'xx'});
    expect(bad.format, ExportFormat.jpeg);
    expect(bad.quality, Settings.minQuality);
    expect(bad.languageCode, isNull);
    expect(bad.onboardingDone, isFalse);
  });

  test('WebP size limits match the core', () {
    expect(ExportFormat.webp.maxMegapixels, 50);
    expect(ExportFormat.webpLossless.maxMegapixels, 24);
    expect(ExportFormat.png.maxMegapixels, double.infinity);
  });
}
