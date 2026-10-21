import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/app_update.dart';
import 'package:refocal/bootstrap/https_fetch.dart';
import 'package:refocal/bootstrap/models.dart' show ModelVerifier;
import 'package:refocal_ffi/refocal_ffi.dart';

/// sha256sum stands in for the native core; a signature is "valid" when the .minisig file
/// says "good" (the real check is covered by native/tests/test_integrity and refocal_ffi).
class _Verifier implements ModelVerifier {
  @override
  Future<void> file(String path, String sha256Hex) async {
    final got = (Process.runSync('sha256sum', [path]).stdout as String).split(' ').first;
    if (got != sha256Hex) throw EnhException(EnhStatus.signature);
  }

  @override
  void signature(String msgPath, String sigPath, List<String> keys) {
    expect(keys, appUpdateKeys);
    if (File(sigPath).readAsStringSync() != 'good') throw EnhException(EnhStatus.signature);
  }
}

String _sha(List<int> bytes) {
  final f = File('${Directory.systemTemp.path}/refocal-sha-${bytes.hashCode}')
    ..writeAsBytesSync(bytes);
  final s = (Process.runSync('sha256sum', [f.path]).stdout as String).split(' ').first;
  f.deleteSync();
  return s;
}

Map<String, Object?> _release(
  int code, {
  String base = 'https://example.org',
  int size = 10,
  String sha = 'aa',
  int minSdk = 29,
  List<String>? urls,
}) => {
  'version_code': code,
  'version_name': '1.0.$code',
  'urls': urls ?? ['$base/apk'],
  'size': size,
  'sha256': sha.length == 64 ? sha : sha.padRight(64, '0'),
  'min_sdk': minSdk,
  'notes': {'en': 'Fixes for $code', 'ru': 'Исправления $code'},
};

void main() {
  test('the keys are the ones in tools/release/keys', () {
    for (final (i, name) in ['U', 'V'].indexed) {
      expect(File('../tools/release/keys/$name.pub').readAsLinesSync()[1], appUpdateKeys[i]);
    }
  });

  group('UpdateFeed', () {
    String feed({Object? stable, Object? beta, int schema = 1}) =>
        jsonEncode({'schema': schema, 'stable': stable, 'beta': beta});

    test('offers the newest release of the channel that runs on the device', () {
      final f = UpdateFeed.parse(feed(stable: _release(16), beta: _release(18)));
      expect(f.newer(15, 34, channelBeta: false)?.versionCode, 16);
      expect(f.newer(15, 34, channelBeta: true)?.versionCode, 18);
      expect(f.newer(16, 34, channelBeta: false), isNull);
      expect(f.newer(18, 34, channelBeta: true), isNull);
      final high = UpdateFeed.parse(feed(stable: _release(16, minSdk: 35)));
      expect(high.newer(15, 34, channelBeta: false), isNull);
      expect(f.byCode(18)?.notesFor('ru'), 'Исправления 18');
      expect(f.byCode(18)?.notesFor('de'), 'Fixes for 18');
    });

    test('rejects anything malformed', () {
      for (final bad in [
        feed(schema: 2, stable: _release(16)),
        feed(stable: _release(16, urls: ['http://example.org/apk'])),
        feed(stable: _release(16, urls: [])),
        feed(stable: {..._release(16), 'sha256': 'not hex'}),
        feed(
          stable: {
            ..._release(16),
            'notes': {'ru': 'только ru'},
          },
        ),
        feed(stable: {..._release(16), 'version_code': '16'}),
        feed(stable: _release(16, size: 0)),
        feed(stable: _release(16, size: 300 << 20)),
        '[]',
      ]) {
        expect(() => UpdateFeed.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('AppUpdater', () {
    late Directory root;
    late HttpServer server;
    late String base;
    late AppUpdater updater;
    final files = <String, List<int>>{};
    final ranges = <String>[];
    var signature = 'good';
    final apk = List<int>.generate(200000, (i) => i * 13 % 251);

    setUp(() async {
      root = Directory.systemTemp.createTempSync('refocal-update');
      final key = '${root.path}/key.pem', cert = '${root.path}/cert.pem';
      Process.runSync('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, //
        '-days', '1', '-subj', '/CN=localhost',
      ]);
      final ctx = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
      base = 'https://localhost:${server.port}';
      files
        ..clear()
        ..['/apk'] = apk;
      ranges.clear();
      signature = 'good';
      server.listen((req) async {
        final path = req.uri.path;
        final body = path == '/app-update.json.minisig' ? utf8.encode(signature) : files[path];
        if (body == null) {
          req.response.statusCode = 404;
        } else if (req.headers.value(HttpHeaders.rangeHeader) case final range?) {
          ranges.add('$path $range');
          req.response
            ..statusCode = 206
            ..add(body.sublist(int.parse(range.substring(6, range.length - 1))));
        } else {
          req.response.add(body);
        }
        await req.response.close();
      });
      updater = AppUpdater(
        dir: '${root.path}/update',
        verifier: _Verifier(),
        fetcher: HttpsFetcher(
          HttpClient()..badCertificateCallback = (_, host, _) => host == 'localhost',
        ),
        base: [base],
      );
    });

    tearDown(() async {
      await server.close(force: true);
      root.deleteSync(recursive: true);
    });

    void publish(Map<String, Object?> stable) =>
        files['/app-update.json'] = utf8.encode(jsonEncode({'schema': 1, 'stable': stable}));

    test('fetches a signed feed and keeps it; a bad signature changes nothing', () async {
      publish(_release(16, base: base, size: apk.length, sha: _sha(apk)));
      expect((await updater.fetch()).stable?.versionCode, 16);
      expect((await updater.cached())?.stable?.versionCode, 16);

      publish(_release(17, base: base, size: apk.length, sha: _sha(apk)));
      signature = 'forged';
      await expectLater(updater.fetch(), throwsA(isA<EnhException>()));
      expect((await updater.cached())?.stable?.versionCode, 16);
    });

    test('downloads, resumes, checks the hash and keeps one APK', () async {
      final r = AppRelease.fromJson(_release(16, base: base, size: apk.length, sha: _sha(apk)));
      Directory('${root.path}/update').createSync(recursive: true);
      File('${root.path}/update/refocal-12.apk').writeAsBytesSync([1, 2, 3]);
      File('${updater.apkOf(r).path}.part').writeAsBytesSync(apk.sublist(0, 50000));

      final fractions = <double>[];
      final file = await updater.download(r, onProgress: fractions.add);
      expect(file.readAsBytesSync(), apk);
      expect(ranges, ['/apk bytes=50000-']);
      expect(fractions.last, 1.0);
      expect(File('${root.path}/update/refocal-12.apk').existsSync(), isFalse);
      expect((await updater.downloaded(r))?.path, file.path);
    });

    test('a mirror with a wrong file is skipped; none right is an error', () async {
      files['/bad'] = List<int>.filled(apk.length, 0);
      final good = AppRelease.fromJson(
        _release(16, size: apk.length, sha: _sha(apk), urls: ['$base/bad', '$base/apk']),
      );
      expect((await updater.download(good)).readAsBytesSync(), apk);

      final none = AppRelease.fromJson(
        _release(17, size: apk.length, sha: _sha(apk), urls: ['$base/bad']),
      );
      await expectLater(updater.download(none), throwsA(isA<FileSystemException>()));
      expect(await updater.downloaded(none), isNull);
    });
  });
}
