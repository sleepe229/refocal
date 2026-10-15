// TEST-DB-001 / PRIV-DATA-001 for prefs.sqlite (see ../refocal/migration_test.dart). With one
// version there is no step yet; these keep the dump and the code together and refuse a newer file.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:refocal_core/src/db/prefs_database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema is the last dump (a change needs a new version)', () async {
    final current = PrefsDatabase(NativeDatabase.memory());
    addTearDown(current.close);
    expect(GeneratedHelper.versions.last, current.schemaVersion);
    final schema = await verifier.schemaAt(GeneratedHelper.versions.last);
    final db = PrefsDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
    await db.close();
  });

  test('a database of a newer app version is not opened', () async {
    final db = PrefsDatabase(
      NativeDatabase.memory(setup: (raw) => raw.userVersion = GeneratedHelper.versions.last + 1),
    );
    await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
    await db.close();
  });
}
