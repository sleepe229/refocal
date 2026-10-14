import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import 'engine.dart';

/// AppSupport/db.sqlite (ADR-0009): settings, history, presets. Opened once per process on a
/// background isolate; tests override it with [RefocalDatabase.memory].
final databaseProvider = FutureProvider<RefocalDatabase>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final db = RefocalDatabase.open(File('${dirs.support}/db.sqlite'));
  ref.onDispose(db.close);
  return db;
});
