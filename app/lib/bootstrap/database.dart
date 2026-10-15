import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import 'engine.dart';

/// prefs.sqlite (ADR-0009, PRIV-DATA-005): settings and user presets, in the backed-up
/// directory. Opened once per process on a background isolate.
final prefsDatabaseProvider = FutureProvider<PrefsDatabase>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final db = PrefsDatabase.open(File('${dirs.backedUp}/prefs.sqlite'));
  ref.onDispose(db.close);
  return db;
});

/// AppSupport/db.sqlite (ADR-0009): history and the queue, not backed up. Its migration to
/// schema 2 moves the settings and presets of 0.0.4 previews into prefs.sqlite.
final databaseProvider = FutureProvider<RefocalDatabase>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final prefs = await ref.watch(prefsDatabaseProvider.future);
  final db = RefocalDatabase.open(File('${dirs.support}/db.sqlite'), movePrefs: prefs.importLegacy);
  ref.onDispose(db.close);
  return db;
});
