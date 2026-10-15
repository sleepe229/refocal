import 'prefs_database.dart';

/// The `settings` table as strings (FR-SET-*). The app owns the keys and parses the values.
class SettingsStore {
  SettingsStore(this._db);

  final PrefsDatabase _db;

  Future<Map<String, String>> read() async => {
    for (final r in await _db.select(_db.settingEntries).get()) r.key: r.value,
  };

  /// Applies [changes] in one transaction; a null value removes the key.
  Future<void> write(Map<String, String?> changes) => _db.transaction(() async {
    for (final MapEntry(:key, :value) in changes.entries) {
      if (value == null) {
        await (_db.delete(_db.settingEntries)..where((t) => t.key.equals(key))).go();
      } else {
        await _db
            .into(_db.settingEntries)
            .insertOnConflictUpdate(SettingEntriesCompanion.insert(key: key, value: value));
      }
    }
  });
}
