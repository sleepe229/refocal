import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

// Packs that need a newer app are not offered (manifest min_app_version, 04 §6).
void main() {
  test('app versions in semantic-version order', () {
    int c(String a, String b) => compareAppVersions(a, b).sign;
    expect(c('0.5.0-beta.2', '0.6.0-beta.1'), -1);
    expect(c('0.6.0-beta.1', '0.6.0'), -1, reason: 'a pre-release comes before its release');
    expect(c('0.6.0-beta.10', '0.6.0-beta.9'), 1, reason: 'numeric parts');
    expect(c('0.6.0-alpha.1', '0.6.0-beta.1'), -1);
    expect(c('1.0.0', '0.99.9'), 1);
    expect(c('1.2.3', '1.2.3'), 0);
    expect(c('garbage', '0.0.1'), -1, reason: 'an unparsable version is the oldest');
  });
}
