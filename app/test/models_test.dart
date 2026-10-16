import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/models.dart';
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
    expect(keys, manifestKeys);
    if (File(sigPath).readAsStringSync() != 'good') throw EnhException(EnhStatus.signature);
  }
}

/// The archive checks are the core's (TEST-SEC-005); this one only unpacks.
class _Unpacker implements PackUnpacker {
  @override
  Future<void> extract(String rfpack, String entry, String dst, int maxBytes) async {
    final r = Process.runSync('unzip', ['-p', rfpack, entry], stdoutEncoding: null);
    final out = r.stdout as List<int>;
    if (r.exitCode != 0) throw EnhException(EnhStatus.invalid);
    if (out.length > maxBytes) throw EnhException(EnhStatus.limit);
    File(dst).writeAsBytesSync(out);
  }
}

/// A .rfpack: a zip of [entries] (name -> bytes).
String _rfpack(String path, Map<String, List<int>> entries) {
  final dir = Directory('$path.d')..createSync(recursive: true);
  for (final e in entries.entries) {
    File('${dir.path}/${e.key}').writeAsBytesSync(e.value);
  }
  final r = Process.runSync('python3', [
    '-I',
    '-c',
    'import sys,zipfile,os\n'
        'with zipfile.ZipFile(sys.argv[1],"w",zipfile.ZIP_DEFLATED) as z:\n'
        '  [z.write(os.path.join(sys.argv[2],n),n) for n in sys.argv[3:]]',
    path,
    dir.path,
    ...entries.keys,
  ]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  dir.deleteSync(recursive: true);
  return path;
}

String _sha(List<int> b) {
  final f = File('${Directory.systemTemp.path}/sha-${b.length}-${b.hashCode}')..writeAsBytesSync(b);
  final s = (Process.runSync('sha256sum', [f.path]).stdout as String).split(' ').first;
  f.deleteSync();
  return s;
}

void main() {
  late Directory root;
  late HttpServer server;
  late ModelManager manager;
  late RefocalDatabase db;
  final files = <String, List<int>>{};
  final ranges = <String>[];
  var signature = 'good';
  late String base;

  final weights = List<int>.generate(300000, (i) => i * 7 % 251);
  final param = utf8.encode('7767517\n1 1\nInput in0 0 1 in0\n');
  final license = utf8.encode('Non-commercial use only.\n');

  Map<String, Object?> pack(String id, {bool nc = false, String? binSha, bool badMirror = false}) =>
      {
        'id': id,
        'version': '1.0.0',
        'category': 'sr',
        'title': {'en': 'Pack $id', 'ru': 'Пак $id'},
        'tier_min': 'T0',
        'license': {
          'spdx': nc ? 'LicenseRef-NC' : 'BSD-3-Clause',
          'url': '$base/license.txt',
          'text_sha256': _sha(license),
          'commercial': !nc,
          'requires_acceptance': nc,
        },
        'io': {'inputs': <Object>[], 'outputs': <Object>[], 'scale': 4},
        'files': [
          {
            'platform': 'any',
            'backend': 'ncnn',
            'precision': 'fp16',
            'path': 'model.ncnn.param',
            'size': param.length,
            'sha256': _sha(param),
            'urls': ['$base/param'],
          },
          {
            'platform': 'any',
            'backend': 'ncnn',
            'precision': 'fp16',
            'path': 'model.ncnn.bin',
            'size': weights.length,
            'sha256': binSha ?? _sha(weights),
            'urls': [if (badMirror) '$base/missing', '$base/bin'],
          },
        ],
        'provenance': {'upstream': 'x', 'upstream_sha256': 'y', 'conversion_commit': 'z'},
      };

  String manifest(int serial, List<Map<String, Object?>> packs) => jsonEncode({
    'schema': 1,
    'serial': serial,
    'generated_at': '2026-10-15T12:00:00Z',
    'min_app_version': '0.0.6',
    'packs': packs,
  });

  setUp(() async {
    root = Directory.systemTemp.createTempSync('refocal-models');
    // A self-signed certificate: the manager speaks https only.
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
      ..['/param'] = param
      ..['/bin'] = weights
      ..['/license.txt'] = license;
    ranges.clear();
    signature = 'good';
    server.listen((req) async {
      final path = req.uri.path;
      final body = path == '/manifest.json.minisig' ? utf8.encode(signature) : files[path];
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range != null) {
          ranges.add('$path $range');
          final from = int.parse(range.substring(6, range.length - 1));
          req.response
            ..statusCode = 206
            ..add(body.sublist(from));
        } else {
          req.response.add(body);
        }
      }
      await req.response.close();
    });
    db = RefocalDatabase.memory();
    final client = HttpClient()..badCertificateCallback = (_, host, _) => host == 'localhost';
    manager = ModelManager(
      repo: ModelRepository(db),
      verifier: _Verifier(),
      unpacker: _Unpacker(),
      supportDir: '${root.path}/support',
      tmpDir: '${root.path}/tmp',
      http: client,
      platform: const ModelPlatform('android', 'ncnn'),
      manifestBase: [base],
    );
  });
  tearDown(() async {
    await server.close(force: true);
    await db.close();
    root.deleteSync(recursive: true);
  });

  test(
    'the manifest is used only with a valid signature and a serial that does not go back',
    () async {
      files['/manifest.json'] = utf8.encode(manifest(2, [pack('sr.a')]));
      signature = 'forged';
      await expectLater(
        manager.refresh(),
        throwsA(isA<ModelError>().having((e) => e.kind, 'kind', ModelErrorKind.integrity)),
      );
      expect(await manager.repo.current(), isNull);
      signature = 'good';
      expect((await manager.refresh()).serial, 2);
      files['/manifest.json'] = utf8.encode(manifest(1, [pack('sr.a')]));
      await expectLater(
        manager.refresh(),
        throwsA(isA<ModelError>().having((e) => e.kind, 'kind', ModelErrorKind.rollback)),
      );
    },
  );

  test(
    'install: resumes a partial file, falls back to the next mirror, moves the pack into place',
    () async {
      final p = pack('sr.a', badMirror: true);
      files['/manifest.json'] = utf8.encode(manifest(1, [p]));
      final m = await manager.refresh();
      // A download interrupted earlier.
      final staging = Directory('${manager.modelsDir}/.sr.a.partial')..createSync(recursive: true);
      File('${staging.path}/model.ncnn.bin.part').writeAsBytesSync(weights.sublist(0, 100000));
      final progress = <double>[];
      await manager.install(m.pack('sr.a')!, onProgress: (x) => progress.add(x.fraction));
      expect(ranges, ['/bin bytes=100000-']);
      expect(File('${manager.dirOf('sr.a')}/model.ncnn.bin').readAsBytesSync(), weights);
      expect(staging.existsSync(), isFalse);
      expect(progress.last, 1.0);
      expect((await manager.repo.installed()).single.id, 'sr.a');
      await manager.remove('sr.a');
      expect(Directory(manager.dirOf('sr.a')).existsSync(), isFalse);
      expect(await manager.repo.installed(), isEmpty);
    },
  );

  test('a file that does not match its hash is not installed', () async {
    files['/manifest.json'] = utf8.encode(manifest(1, [pack('sr.a', binSha: 'a' * 64)]));
    final m = await manager.refresh();
    await expectLater(
      manager.install(m.pack('sr.a')!),
      throwsA(isA<ModelError>().having((e) => e.kind, 'kind', ModelErrorKind.integrity)),
    );
    expect(Directory(manager.dirOf('sr.a')).existsSync(), isFalse);
    expect(await manager.repo.installed(), isEmpty);
  });

  test('a non-commercial pack needs consent to its verified license text (ADR-0022)', () async {
    files['/manifest.json'] = utf8.encode(manifest(1, [pack('face.x', nc: true)]));
    final face = (await manager.refresh()).pack('face.x')!;
    expect(() => manager.install(face), throwsStateError);
    expect(await manager.licenseText(face), 'Non-commercial use only.\n');
    files['/license.txt'] = utf8.encode('Other text');
    await expectLater(
      manager.licenseText(face),
      throwsA(isA<ModelError>().having((e) => e.kind, 'kind', ModelErrorKind.integrity)),
    );
    await manager.repo.recordConsent(face);
    await manager.install(face);
    expect((await manager.repo.installed()).single.id, 'face.x');
  });

  Map<String, List<int>> offline(
    List<Map<String, Object?>> packs, {
    String sig = 'good',
    List<int>? bin,
  }) => {
    'manifest.json': utf8.encode(manifest(2, packs)),
    'manifest.json.minisig': utf8.encode(sig),
    'license.txt': license,
    'model.ncnn.param': param,
    'model.ncnn.bin': bin ?? weights,
  };

  test('an offline pack installs without the network manifest (FR-MODEL-006)', () async {
    final path = _rfpack('${root.path}/face.rfpack', offline([pack('face.x', nc: true)]));
    final p = await manager.openOffline(path);
    expect((p.pack.id, p.licenseText), ('face.x', 'Non-commercial use only.\n'));
    expect(() => manager.installOffline(p), throwsStateError); // consent first (ADR-0022)
    await manager.repo.recordConsent(p.pack);
    final progress = <double>[];
    await manager.installOffline(p, onProgress: (x) => progress.add(x.fraction));
    expect(progress.last, 1.0);
    final installed = (await manager.repo.installed()).single;
    expect(
      (installed.id, installed.titleFor('ru'), installed.titleFor('de')),
      ('face.x', 'Пак face.x', 'Pack face.x'),
    );
    expect(File('${manager.dirOf('face.x')}/model.ncnn.bin').readAsBytesSync(), weights);
    expect(await manager.repo.current(), isNull); // the network manifest is untouched
    expect(Directory('${root.path}/tmp/rfpack').existsSync(), isFalse);
  });

  test('offline packs: same checks as the network ones', () async {
    Future<void> refused(Map<String, List<int>> entries, ModelErrorKind kind) async {
      final path = _rfpack('${root.path}/p${entries.hashCode}.rfpack', entries);
      await expectLater(
        () async => manager.installOffline(await manager.openOffline(path)),
        throwsA(isA<ModelError>().having((e) => e.kind, 'kind', kind)),
      );
      expect(await manager.repo.installed(), isEmpty);
    }

    await refused(offline([pack('sr.a')], sig: 'forged'), ModelErrorKind.integrity);
    await refused(offline([pack('sr.a'), pack('sr.b')]), ModelErrorKind.notAPack);
    await refused(
      offline([pack('sr.a')], bin: List.filled(weights.length, 1)),
      ModelErrorKind.integrity,
    );
    await refused(offline([pack('sr.a')])..remove('license.txt'), ModelErrorKind.notAPack);
    await refused(
      offline([pack('sr.a')])..['license.txt'] = utf8.encode('Another license'),
      ModelErrorKind.integrity,
    );
    final garbage = File('${root.path}/garbage.rfpack')..writeAsStringSync('not a zip');
    await expectLater(
      manager.openOffline(garbage.path),
      throwsA(isA<ModelError>().having((e) => e.kind, 'kind', ModelErrorKind.notAPack)),
    );
  });

  test('an offline pack older than the installed version is refused', () async {
    final v2 = {...pack('sr.a'), 'version': '1.10.0'};
    await manager.installOffline(
      await manager.openOffline(_rfpack('${root.path}/v2.rfpack', offline([v2]))),
    );
    await expectLater(
      manager.openOffline(_rfpack('${root.path}/v1.rfpack', offline([pack('sr.a')]))),
      throwsA(isA<ModelError>().having((e) => e.kind, 'kind', ModelErrorKind.rollback)),
    );
  });

  test('the public keys are the ones in tools/models/keys', () {
    for (final (i, name) in ['A', 'B'].indexed) {
      expect(File('../tools/models/keys/$name.pub').readAsLinesSync()[1], manifestKeys[i]);
    }
  });
}
