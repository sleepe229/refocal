import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'manifest.dart';

/// A manifest older than the last accepted one (ADR-0011): a replayed or rolled-back file.
class ManifestRollback implements Exception {
  const ManifestRollback(this.serial, this.current);
  final int serial, current;

  @override
  String toString() => 'ManifestRollback($serial < $current)';
}

/// An installed pack, as recorded after its files were verified.
class InstalledPack {
  const InstalledPack({
    required this.id,
    required this.version,
    required this.path,
    required this.size,
    required this.installedAt,
    this.title = const {},
  });

  final String id, version;

  /// Language code -> title, from the manifest entry it was installed from (empty before
  /// schema 5); see [titleFor].
  final Map<String, String> title;

  /// The title in [lang], else English, else the id (as [PackInfo.titleFor]).
  String titleFor(String lang) => title[lang] ?? title['en'] ?? id;

  /// Relative to AppSupport.
  final String path;
  final int size;
  final DateTime installedAt;
}

/// Manifest state, installed packs and license consents (07 §3: manifest_state, model_packs,
/// consents). Signatures are checked before anything reaches here.
class ModelRepository {
  ModelRepository(this._db);

  final RefocalDatabase _db;

  /// Stores a manifest whose signature was verified. Throws [ManifestRollback] for a serial
  /// below the stored one, or the same serial with other content; [FormatException] if it is
  /// not a manifest this version reads.
  Future<Manifest> accept(String verifiedJson, {DateTime? now}) => _db.transaction(() async {
    final m = Manifest.parse(verifiedJson);
    final cur = await _db.select(_db.manifestState).getSingleOrNull();
    if (cur != null &&
        (m.serial < cur.serial || (m.serial == cur.serial && verifiedJson != cur.json))) {
      throw ManifestRollback(m.serial, cur.serial);
    }
    await _db
        .into(_db.manifestState)
        .insertOnConflictUpdate(
          ManifestStateCompanion.insert(
            id: const Value(1),
            serial: m.serial,
            fetchedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
            json: verifiedJson,
          ),
        );
    return m;
  });

  /// The last accepted manifest (for offline use), or null.
  Future<Manifest?> current() async {
    final cur = await _db.select(_db.manifestState).getSingleOrNull();
    return cur == null ? null : Manifest.parse(cur.json);
  }

  Stream<List<InstalledPack>> watchInstalled() =>
      (_db.select(_db.modelPacks)..orderBy([(p) => OrderingTerm.asc(p.id)])).watch().map(
        (rows) => [
          for (final r in rows)
            InstalledPack(
              id: r.id,
              version: r.version,
              path: r.path,
              size: r.size,
              installedAt: DateTime.fromMillisecondsSinceEpoch(r.installedAt),
              title: _title(r.title),
            ),
        ],
      );

  Future<List<InstalledPack>> installed() => watchInstalled().first;

  /// The stored titles; anything unreadable is no title (the id is shown).
  static Map<String, String> _title(String? json) {
    if (json == null) return const {};
    try {
      return (jsonDecode(json) as Map).map((k, v) => MapEntry(k as String, v as String));
    } on Object {
      return const {};
    }
  }

  /// After every file of [files] was verified and moved into [path].
  Future<void> recordInstalled(PackInfo pack, List<PackFile> files, String path, {DateTime? now}) =>
      _db
          .into(_db.modelPacks)
          .insertOnConflictUpdate(
            ModelPacksCompanion.insert(
              id: pack.id,
              version: pack.version,
              category: pack.category.name,
              path: path,
              size: files.fold(0, (n, f) => n + f.size),
              sha256: files.map((f) => f.sha256).join(','),
              licenseSpdx: pack.license.spdx,
              installedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
              title: Value(jsonEncode(pack.title)),
            ),
          );

  /// Returns the directory to delete, or null if it was not installed.
  Future<String?> removeInstalled(String id) => _db.transaction(() async {
    final r = await (_db.select(_db.modelPacks)..where((p) => p.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    await (_db.delete(_db.modelPacks)..where((p) => p.id.equals(id))).go();
    return r.path;
  });

  /// Consent for the license text this pack ships now (a changed text needs a new consent).
  Future<bool> hasConsent(PackInfo pack) async =>
      await (_db.select(_db.consents)..where(
            (c) => c.packId.equals(pack.id) & c.licenseSha256.equals(pack.license.textSha256),
          ))
          .getSingleOrNull() !=
      null;

  Future<void> recordConsent(PackInfo pack, {DateTime? now}) => _db
      .into(_db.consents)
      .insertOnConflictUpdate(
        ConsentsCompanion.insert(
          packId: pack.id,
          packVersion: pack.version,
          licenseSha256: pack.license.textSha256,
          acceptedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
        ),
      );
}
