import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'prefs_database.g.dart';

// prefs.sqlite (ADR-0009, PRIV-DATA-005): settings and user presets, the part of the app's
// state the platform backup takes. Kept apart from db.sqlite, whose rows refer to photos and
// files that are not backed up.
//
// Changing a table: bump [PrefsDatabase.schemaVersion], run `dart run drift_dev
// make-migrations` in packages/refocal_core, write the step and fill the generated test data.

/// Settings and presets of schema 1 of db.sqlite, moved here by its migration to v2.
class LegacyPrefs {
  const LegacyPrefs({this.settings = const {}, this.presets = const []});

  final Map<String, String> settings;
  final List<PresetRow> presets;

  bool get isEmpty => settings.isEmpty && presets.isEmpty;
}

@DriftDatabase(tables: [SettingEntries, Presets])
class PrefsDatabase extends _$PrefsDatabase {
  PrefsDatabase(super.e);

  /// The database file, opened on a background isolate.
  PrefsDatabase.open(File file) : super(NativeDatabase.createInBackground(file));

  /// For tests.
  PrefsDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // See RefocalDatabase: an older app does not touch a newer file.
      if (from > to) throw StateError('prefs schema $from is newer than this app ($to)');
      throw StateError('no migration from prefs schema $from to $to');
    },
  );

  /// Takes the rows db.sqlite v1 held. Rows already here win: the move may be repeated after
  /// it was interrupted, and anything written here since is newer.
  Future<void> importLegacy(LegacyPrefs p) => transaction(() async {
    await batch((b) {
      b.insertAll(settingEntries, [
        for (final MapEntry(:key, :value) in p.settings.entries)
          SettingEntriesCompanion.insert(key: key, value: value),
      ], mode: InsertMode.insertOrIgnore);
      b.insertAll(presets, p.presets, mode: InsertMode.insertOrIgnore);
    });
  });
}
