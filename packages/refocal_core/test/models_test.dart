import 'dart:convert';

import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

const _sha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Map<String, Object?> _pack(String id, {bool nc = false, String text = _sha}) => {
  'id': id,
  'version': '1.0.0',
  'category': 'sr',
  'title': {'en': 'Pack $id', 'ru': 'Пак $id'},
  'tier_min': 'T0',
  'license': {
    'spdx': nc ? 'LicenseRef-NC' : 'BSD-3-Clause',
    'url': 'https://example.org/license.txt',
    'text_sha256': text,
    'commercial': !nc,
    'requires_acceptance': nc,
  },
  'io': {
    'inputs': [
      {'name': 'input'},
    ],
    'outputs': [
      {'name': 'output'},
    ],
    'scale': 4,
  },
  'files': [
    for (final f in ['model.ncnn.param', 'model.ncnn.bin'])
      {
        'platform': 'android',
        'backend': 'ncnn',
        'precision': 'fp16',
        'path': f,
        'size': 10,
        'sha256': _sha,
        'urls': ['https://github.com/o/r/releases/download/t/$f', 'https://mirror.example/$f'],
      },
    {
      'platform': 'ios',
      'backend': 'coreml',
      'precision': 'fp16',
      'path': 'model.mlpackage.zip',
      'size': 10,
      'sha256': _sha,
      'urls': ['https://example.org/m.zip'],
    },
  ],
  'provenance': {'upstream': 'x', 'upstream_sha256': _sha, 'conversion_commit': 'abc'},
};

String _manifest({int serial = 3, List<Map<String, Object?>>? packs}) => jsonEncode({
  'schema': 1,
  'serial': serial,
  'generated_at': '2026-10-15T10:00:00Z',
  'min_app_version': '0.0.6',
  'packs': packs ?? [_pack('sr.general-x4v3-dn0'), _pack('face.gfpgan-1.4', nc: true)],
});

void main() {
  group('manifest', () {
    test('parses packs, files per platform and backend, localized titles', () {
      final m = Manifest.parse(_manifest());
      expect(m.serial, 3);
      final p = m.pack('sr.general-x4v3-dn0')!;
      expect(p.titleFor('ru'), 'Пак sr.general-x4v3-dn0');
      expect(p.titleFor('de'), 'Pack sr.general-x4v3-dn0');
      expect(p.filesFor('android', 'ncnn').map((f) => f.path), [
        'model.ncnn.param',
        'model.ncnn.bin',
      ]);
      expect(p.filesFor('android', 'ncnn').first.urls, hasLength(2));
      expect(p.filesFor('ios', 'coreml'), hasLength(1));
      expect(m.pack('face.gfpgan-1.4')!.license.requiresAcceptance, isTrue);
    });

    test('rejects what the schema does not allow', () {
      Map<String, Object?> base() => jsonDecode(_manifest()) as Map<String, Object?>;
      Map<String, Object?> pack0(Map<String, Object?> m) =>
          ((m['packs'] as List).first as Map).cast<String, Object?>();
      Map<String, Object?> file0(Map<String, Object?> m) =>
          ((pack0(m)['files'] as List).first as Map).cast<String, Object?>();
      final cases = <String, void Function(Map<String, Object?>)>{
        'schema 2': (m) => m['schema'] = 2,
        'unknown top field': (m) => m['extra'] = 1,
        'serial 0': (m) => m['serial'] = 0,
        'serial as text': (m) => m['serial'] = '3',
        'bad pack id': (m) => pack0(m)['id'] = 'Bad Id',
        'unknown pack field': (m) => pack0(m)['unknown'] = true,
        'scale 3': (m) => (pack0(m)['io'] as Map)['scale'] = 3,
        'path with a slash': (m) => file0(m)['path'] = '../model.bin',
        'http url': (m) => file0(m)['urls'] = ['http://example.org/x'],
        'no urls': (m) => file0(m)['urls'] = <String>[],
        'short sha': (m) => file0(m)['sha256'] = 'abc',
        'no english title': (m) => pack0(m)['title'] = {'ru': 'x'},
        'duplicate id': (m) => (m['packs'] as List).add(pack0(m)),
        'no files': (m) => pack0(m)['files'] = <Object>[],
      };
      for (final MapEntry(key: name, value: change) in cases.entries) {
        final m = base();
        change(m);
        expect(() => Manifest.parse(jsonEncode(m)), throwsFormatException, reason: name);
      }
      expect(() => Manifest.parse('{not json'), throwsFormatException);
    });
  });

  group('repository', () {
    late RefocalDatabase db;
    late ModelRepository repo;
    setUp(() {
      db = RefocalDatabase.memory();
      repo = ModelRepository(db);
    });
    tearDown(() => db.close());

    test('a lower serial, or the same serial with other content, is a rollback', () async {
      expect(await repo.current(), isNull);
      await repo.accept(_manifest(serial: 3));
      await repo.accept(_manifest(serial: 3)); // the same file again
      await repo.accept(_manifest(serial: 4));
      expect(() => repo.accept(_manifest(serial: 3)), throwsA(isA<ManifestRollback>()));
      expect(
        () => repo.accept(_manifest(serial: 4, packs: [_pack('sr.other')])),
        throwsA(isA<ManifestRollback>()),
      );
      expect((await repo.current())!.serial, 4);
    });

    test('installed packs and consents for the current license text', () async {
      final m = await repo.accept(_manifest());
      final face = m.pack('face.gfpgan-1.4')!;
      expect(await repo.hasConsent(face), isFalse);
      await repo.recordConsent(face);
      expect(await repo.hasConsent(face), isTrue);
      final changed = Manifest.parse(
        _manifest(packs: [_pack('face.gfpgan-1.4', nc: true, text: 'f' * 64)]),
      ).pack('face.gfpgan-1.4')!;
      expect(await repo.hasConsent(changed), isFalse, reason: 'a new license text');

      final files = face.filesFor('android', 'ncnn');
      await repo.recordInstalled(face, files, 'models/face.gfpgan-1.4');
      final installed = await repo.installed();
      expect((installed.single.id, installed.single.size), ('face.gfpgan-1.4', 20));
      expect(await repo.removeInstalled('face.gfpgan-1.4'), 'models/face.gfpgan-1.4');
      expect(await repo.installed(), isEmpty);
      expect(await repo.removeInstalled('face.gfpgan-1.4'), isNull);
    });
  });
}
