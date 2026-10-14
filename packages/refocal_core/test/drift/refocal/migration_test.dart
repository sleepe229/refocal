// TEST-DB-001 / PRIV-DATA-001: every schema version migrates to every later one. The schema
// dumps (drift_schemas/refocal) and generated/ come from `dart run drift_dev make-migrations`;
// with a second version it also adds the step-by-step data template (see drift's docs).
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:refocal_core/src/db/database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = RefocalDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('the current schema is the last dump (a change needs a new version)', () async {
    final current = RefocalDatabase(NativeDatabase.memory());
    addTearDown(current.close);
    expect(GeneratedHelper.versions.last, current.schemaVersion);
    final schema = await verifier.schemaAt(GeneratedHelper.versions.last);
    final db = RefocalDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
    await db.close();
  });

  test('a new database matches the last dump', () async {
    final db = RefocalDatabase(NativeDatabase.memory());
    await db.validateDatabaseSchema();
    await db.close();
  });

  test('a database of a newer app version is not opened', () async {
    final db = RefocalDatabase(
      NativeDatabase.memory(setup: (raw) => raw.userVersion = GeneratedHelper.versions.last + 1),
    );
    await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
    await db.close();
  });
}
