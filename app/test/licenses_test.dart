import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/features/about/about_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native and model licenses are registered from the asset', () async {
    registerNativeLicenses();
    final packages = <String>{};
    await for (final e in LicenseRegistry.licenses) {
      packages.addAll(e.packages);
    }
    expect(
      packages,
      containsAll([
        'ncnn',
        'libjpeg-turbo (IJG)',
        'SQLite',
        'Monocypher',
        'Real-ESRGAN (model weights: sr.general-x4v3)',
      ]),
    );
  });
}
