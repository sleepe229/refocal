import 'dart:convert';

// The model manifest (ADR-0011, 04 §6, docs/spec/appendix/manifest.schema.json), parsed once
// after its signature was verified. Anything the schema does not allow is a FormatException:
// a manifest this version cannot read is not partially used.

enum PackCategory { sr, face, det, jpeg, old, color, parse }

/// One downloadable file of a pack for a platform and backend.
class PackFile {
  const PackFile({
    required this.platform,
    required this.backend,
    required this.precision,
    required this.path,
    required this.size,
    required this.sha256,
    required this.urls,
  });

  /// android | ios | any
  final String platform;

  /// ncnn | coreml | ort_qnn
  final String backend;
  final String precision;

  /// File name inside the pack directory (`[A-Za-z0-9._-]+`: never a path).
  final String path;
  final int size;
  final String sha256;

  /// Mirrors, tried in order (https only).
  final List<String> urls;
}

class PackLicense {
  const PackLicense({
    required this.spdx,
    required this.url,
    required this.textSha256,
    required this.commercial,
    required this.requiresAcceptance,
  });

  final String spdx;

  /// The license text; its SHA-256 is [textSha256] (what a consent is given for).
  final String url;
  final String textSha256;
  final bool commercial;

  /// Non-commercial or otherwise restricted (ADR-0022): explicit consent before download.
  final bool requiresAcceptance;
}

class PackInfo {
  const PackInfo({
    required this.id,
    required this.version,
    required this.category,
    required this.title,
    required this.description,
    required this.tierMin,
    required this.minAppVersion,
    required this.license,
    required this.scale,
    required this.files,
  });

  final String id, version;
  final PackCategory category;

  /// By language code; `en` always present.
  final Map<String, String> title;
  final Map<String, String> description;

  /// T0 | T1 | T2 (ADR-0017).
  final String tierMin;
  final String? minAppVersion;
  final PackLicense license;
  final int scale;
  final List<PackFile> files;

  /// Whether an app of [appVersion] can use this pack ([minAppVersion]; none: every app).
  bool supportedBy(String appVersion) {
    final min = minAppVersion;
    return min == null || compareAppVersions(appVersion, min) >= 0;
  }

  String titleFor(String languageCode) => title[languageCode] ?? title['en']!;
  String? descriptionFor(String languageCode) => description[languageCode] ?? description['en'];

  /// The files for [platform] and [backend] ("any" platform matches every platform).
  List<PackFile> filesFor(String platform, String backend) => [
    for (final f in files)
      if ((f.platform == platform || f.platform == 'any') && f.backend == backend) f,
  ];
}

class Manifest {
  const Manifest({
    required this.serial,
    required this.generatedAt,
    required this.minAppVersion,
    required this.packs,
  });

  /// Monotonic; a lower one than the last accepted is a rollback (ADR-0011).
  final int serial;
  final DateTime generatedAt;
  final String minAppVersion;
  final List<PackInfo> packs;

  PackInfo? pack(String id) => packs.where((p) => p.id == id).firstOrNull;

  static final _packId = RegExp(r'^[a-z]+\.[a-z0-9.-]+$');
  static final _semver = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$');
  static final _sha = RegExp(r'^[0-9a-f]{64}$');
  static final _fileName = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Throws [FormatException] for anything the schema does not allow.
  factory Manifest.parse(String source) {
    final Object? j;
    try {
      j = jsonDecode(source);
    } on FormatException {
      throw const FormatException('manifest is not JSON');
    }
    final m = _obj(j, 'manifest', const {
      'schema',
      'serial',
      'generated_at',
      'min_app_version',
      'gpu_blocklist',
      'gpu_blocklist_revoke',
      'packs',
    });
    if (m['schema'] != 1) throw const FormatException('unsupported manifest schema');
    final serial = _int(m['serial'], 'serial');
    if (serial < 1) throw const FormatException('serial must be >= 1');
    final generated = DateTime.tryParse(_str(m['generated_at'], 'generated_at'));
    if (generated == null) throw const FormatException('bad generated_at');
    final packs = [for (final p in _list(m['packs'], 'packs')) _pack(p)];
    if (packs.map((p) => p.id).toSet().length != packs.length) {
      throw const FormatException('duplicate pack id');
    }
    return Manifest(
      serial: serial,
      generatedAt: generated,
      minAppVersion: _match(m['min_app_version'], _semver, 'min_app_version'),
      packs: packs,
    );
  }

  static PackInfo _pack(Object? j) {
    final p = _obj(j, 'pack', const {
      'id',
      'version',
      'category',
      'title',
      'description',
      'tier_min',
      'min_app_version',
      'license',
      'io',
      'files',
      'eval',
      'provenance',
    });
    final id = _match(p['id'], _packId, 'pack id');
    final l = _obj(p['license'], 'license', const {
      'spdx',
      'url',
      'text_sha256',
      'commercial',
      'requires_acceptance',
      'notes_key',
    });
    final io = _obj(p['io'], 'io', const {'inputs', 'outputs', 'scale', 'tiles', 'pad', 'params'});
    final scale = _int(io['scale'], 'io.scale');
    if (!const {1, 2, 4}.contains(scale)) throw FormatException('bad scale of $id');
    final tier = _str(p['tier_min'], 'tier_min');
    if (!const {'T0', 'T1', 'T2'}.contains(tier)) throw FormatException('bad tier_min of $id');
    final provenance = _obj(p['provenance'], 'provenance', const {
      'upstream',
      'upstream_sha256',
      'conversion_commit',
    });
    for (final k in const ['upstream', 'upstream_sha256', 'conversion_commit']) {
      _str(provenance[k], 'provenance.$k');
    }
    final files = [for (final f in _list(p['files'], 'files')) _file(f, id)];
    if (files.isEmpty) throw FormatException('pack $id has no files');
    return PackInfo(
      id: id,
      version: _match(p['version'], _semver, 'version'),
      category:
          PackCategory.values.asNameMap()[p['category']] ??
          (throw FormatException('bad category of $id')),
      title: _localized(p['title'], 'title'),
      description: p['description'] == null
          ? const {}
          : _localized(p['description'], 'description'),
      tierMin: tier,
      minAppVersion: p['min_app_version'] == null
          ? null
          : _str(p['min_app_version'], 'min_app_version'),
      license: PackLicense(
        spdx: _str(l['spdx'], 'license.spdx'),
        url: _https(l['url'], 'license.url'),
        textSha256: _match(l['text_sha256'], _sha, 'license.text_sha256'),
        commercial: _bool(l['commercial'], 'license.commercial'),
        requiresAcceptance: _bool(l['requires_acceptance'], 'license.requires_acceptance'),
      ),
      scale: scale,
      files: files,
    );
  }

  static PackFile _file(Object? j, String pack) {
    final f = _obj(j, 'file', const {
      'platform',
      'backend',
      'precision',
      'path',
      'size',
      'sha256',
      'urls',
    });
    String oneOf(String key, Set<String> allowed) {
      final v = _str(f[key], key);
      if (!allowed.contains(v)) throw FormatException('bad $key in $pack');
      return v;
    }

    final size = _int(f['size'], 'size');
    if (size < 1) throw FormatException('bad size in $pack');
    final urls = [for (final u in _list(f['urls'], 'urls')) _https(u, 'url')];
    if (urls.isEmpty) throw FormatException('no urls in $pack');
    return PackFile(
      platform: oneOf('platform', const {'android', 'ios', 'any'}),
      backend: oneOf('backend', const {'ncnn', 'coreml', 'ort_qnn'}),
      precision: oneOf('precision', const {'fp32', 'fp16', 'int8', 'mixed'}),
      path: _match(f['path'], _fileName, 'path'),
      size: size,
      sha256: _match(f['sha256'], _sha, 'sha256'),
      urls: urls,
    );
  }

  static Map<String, Object?> _obj(Object? j, String what, Set<String> allowed) {
    if (j is! Map<String, Object?>) throw FormatException('$what must be an object');
    for (final k in j.keys) {
      if (!allowed.contains(k)) throw FormatException('unknown field "$k" in $what');
    }
    return j;
  }

  static List<Object?> _list(Object? j, String what) =>
      j is List<Object?> ? j : throw FormatException('$what must be a list');
  static String _str(Object? j, String what) =>
      j is String ? j : throw FormatException('$what must be a string');
  static int _int(Object? j, String what) =>
      j is int ? j : throw FormatException('$what must be an integer');
  static bool _bool(Object? j, String what) =>
      j is bool ? j : throw FormatException('$what must be a boolean');
  static String _match(Object? j, RegExp re, String what) {
    final s = _str(j, what);
    return re.hasMatch(s) ? s : throw FormatException('bad $what: $s');
  }

  static String _https(Object? j, String what) {
    final s = _str(j, what);
    final u = Uri.tryParse(s);
    return u != null && u.scheme == 'https' && u.host.isNotEmpty
        ? s
        : throw FormatException('$what must be an https URL');
  }

  static Map<String, String> _localized(Object? j, String what) {
    if (j is! Map<String, Object?> || j['en'] is! String) {
      throw FormatException('$what needs an "en" text');
    }
    return {for (final MapEntry(:key, :value) in j.entries) key: _str(value, what)};
  }
}

/// Semantic-version order of two app versions (`1.2.3` or `1.2.3-beta.4`): negative when [a]
/// is older. A pre-release comes before its release (0.6.0-beta.1 < 0.6.0); pre-release parts
/// compare numerically when both are numbers. A version that does not parse is the oldest.
int compareAppVersions(String a, String b) {
  final re = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?');
  final (x, y) = (re.firstMatch(a), re.firstMatch(b));
  if (x == null || y == null) return x == null ? (y == null ? 0 : -1) : 1;
  for (var i = 1; i <= 3; i++) {
    final d = int.parse(x[i]!).compareTo(int.parse(y[i]!));
    if (d != 0) return d;
  }
  final (p, q) = (x[4], y[4]);
  if (p == null || q == null) return p == q ? 0 : (p == null ? 1 : -1);
  final (ps, qs) = (p.split('.'), q.split('.'));
  for (var i = 0; i < ps.length && i < qs.length; i++) {
    final (m, n) = (int.tryParse(ps[i]), int.tryParse(qs[i]));
    final d = m != null && n != null ? m.compareTo(n) : ps[i].compareTo(qs[i]);
    if (d != 0) return d;
  }
  return ps.length.compareTo(qs.length);
}
