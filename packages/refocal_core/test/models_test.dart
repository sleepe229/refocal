import 'dart:convert';
import 'dart:io';

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

/// [_pack] in schema 2 (ADR-0026): its licence class, and the credit of a CC-BY one.
Map<String, Object?> _pack2(String id, {String cls = 'permissive', String? category}) {
  final p = _pack(id, nc: cls == 'noncommercial');
  final l = (p['license']! as Map<String, Object?>)..['class'] = cls;
  if (cls == 'attribution' || cls == 'sharealike') {
    l['spdx'] = 'CC-BY-4.0';
    l['attribution'] = {'author': 'Phhofm', 'url': 'https://openmodeldb.info/models/x'};
  }
  if (category != null) p['category'] = category;
  return p;
}

String _manifest({int serial = 3, int schema = 1, List<Map<String, Object?>>? packs}) =>
    jsonEncode({
      'schema': schema,
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

    test('the published manifest (tools/models/manifest.json) is one the app reads', () {
      final m = Manifest.parse(File('../../tools/models/manifest.json').readAsStringSync());
      expect(
        m.packs.map((p) => p.id),
        containsAll(['sr.general-x4v3-dn0', 'sr.general-x4v3-dn100', 'face.gfpgan-1.4']),
      );
      for (final p in m.packs) {
        // What the core loads: <id>/model.ncnn.*, or CodeFormer's split graph (ADR-0024);
        // model.json (scale, pad, split) is optional for one graph.
        final files = p.filesFor('android', 'ncnn').map((f) => f.path).toList();
        expect(
          files,
          p.id == 'face.codeformer'
              ? containsAll([
                  'encoder.ncnn.param',
                  'encoder.ncnn.bin',
                  'generator.ncnn.param',
                  'generator.ncnn.bin',
                  'codebook.f32',
                  'model.json',
                ])
              : containsAll(['model.ncnn.param', 'model.ncnn.bin']),
          reason: p.id,
        );
      }
    });

    test('rejects what the schema does not allow', () {
      Map<String, Object?> base() => jsonDecode(_manifest()) as Map<String, Object?>;
      Map<String, Object?> pack0(Map<String, Object?> m) =>
          ((m['packs'] as List).first as Map).cast<String, Object?>();
      Map<String, Object?> file0(Map<String, Object?> m) =>
          ((pack0(m)['files'] as List).first as Map).cast<String, Object?>();
      final cases = <String, void Function(Map<String, Object?>)>{
        'schema 3': (m) => m['schema'] = 3,
        'a licence class in schema 1': (m) => (pack0(m)['license'] as Map)['class'] = 'permissive',
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

  group('manifest schema 2 (ADR-0026)', () {
    test('licence classes, the credit of a CC-BY pack, the denoise category', () {
      final m = Manifest.parse(
        _manifest(
          schema: 2,
          packs: [
            _pack2('sr.general-x4v3-dn0'),
            _pack2('sr.lsdir-compact', cls: 'attribution'),
            _pack2('face.gfpgan-1.4', cls: 'noncommercial'),
            _pack2('denoise.scunet', category: 'denoise'),
          ],
        ),
      );
      expect(m.schema, 2);
      expect(m.pack('sr.general-x4v3-dn0')!.license.licenseClass, LicenseClass.permissive);
      final cc = m.pack('sr.lsdir-compact')!.license;
      expect(cc.licenseClass, LicenseClass.attribution);
      expect(cc.attribution!.author, 'Phhofm');
      expect(cc.requiresAcceptance, isFalse);
      expect(m.pack('face.gfpgan-1.4')!.license.licenseClass, LicenseClass.nonCommercial);
      expect(m.pack('denoise.scunet')!.category, PackCategory.denoise);
    });

    test('rejects a class that disagrees with the flags, or a missing credit', () {
      Map<String, Object?> lic(Map<String, Object?> p) => p['license']! as Map<String, Object?>;
      final cases = <String, Map<String, Object?>>{
        'no class': _pack2('a.b')..update('license', (l) => (l as Map)..remove('class')),
        'unknown class': _pack2('a.b', cls: 'unspecified'),
        'NC without consent': () {
          final p = _pack2('a.b', cls: 'noncommercial');
          lic(p)['requires_acceptance'] = false;
          return p;
        }(),
        'permissive with consent': () {
          final p = _pack2('a.b');
          lic(p)['requires_acceptance'] = true;
          return p;
        }(),
        'CC-BY without credit': () {
          final p = _pack2('a.b', cls: 'attribution');
          lic(p).remove('attribution');
          return p;
        }(),
        'credit on a permissive pack': () {
          final p = _pack2('a.b');
          lic(p)['attribution'] = {'author': 'x', 'url': 'https://x.org'};
          return p;
        }(),
      };
      for (final MapEntry(key: name, value: p) in cases.entries) {
        expect(
          () => Manifest.parse(_manifest(schema: 2, packs: [p])),
          throwsFormatException,
          reason: name,
        );
      }
    });

    test('the schema 1 projection for older apps drops what they cannot show', () {
      final r = Process.runSync('python3', [
        '../../tools/models/manifest_v1.py',
        '../../tools/models/manifest.json',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final v1 = Manifest.parse(r.stdout as String);
      final v2 = Manifest.parse(File('../../tools/models/manifest.json').readAsStringSync());
      expect(v1.schema, 1);
      expect(v1.serial, v2.serial);
      expect(v1.packs.map((p) => p.id), [
        for (final p in v2.packs)
          if (p.category != PackCategory.denoise && !p.license.licenseClass!.credited) p.id,
      ]);
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

    test('the same serial moves from schema 1 to 2, never back', () async {
      await repo.accept(_manifest(serial: 4));
      final v2 = _manifest(serial: 4, schema: 2, packs: [_pack2('sr.general-x4v3-dn0')]);
      await repo.accept(v2);
      expect((await repo.current())!.schema, 2);
      expect(() => repo.accept(_manifest(serial: 4)), throwsA(isA<ManifestRollback>()));
      expect(() => repo.accept(_manifest(serial: 5)), throwsA(isA<ManifestRollback>()));
      await repo.accept(v2);
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
