import 'package:refocal_core/refocal_core.dart';
import 'package:test/test.dart';

void main() {
  late RefocalDatabase db;
  late PrefsDatabase prefs;

  setUp(() {
    db = RefocalDatabase.memory();
    prefs = PrefsDatabase.memory();
  });
  tearDown(() async {
    await db.close();
    await prefs.close();
  });

  group('settings store', () {
    test('writes, overwrites and removes keys in one go', () async {
      final store = SettingsStore(prefs);
      expect(await store.read(), isEmpty);
      await store.write({'a': '1', 'b': '2'});
      await store.write({'a': '3', 'b': null});
      expect(await store.read(), {'a': '3'});
    });
  });

  group('history', () {
    final saved = Recipe(
      scale: 2,
      fast2: true,
      srModel: 'sr.general-x4v3',
      strength: 0.8,
      output: OutputSpec(ExportFormat.jpeg, quality: 92),
    );
    HistoryEntry entry(
      String id, {
      String input = 'inbox/a.jpg',
      String job = 'job-1',
      int t = 0,
    }) => HistoryEntry(
      id: id,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000 + t),
      recipe: saved,
      inputPath: input,
      sourceWidth: 4000,
      sourceHeight: 3000,
      width: 8000,
      height: 6000,
      previewPath: 'history/$id.jpg',
      resultUri: 'content://media/$id',
      modelIds: const ['sr.general-x4v3'],
      backend: 'vulkan',
      duration: const Duration(seconds: 42),
      jobId: job,
    );

    test('stores the recipe and the input, newest first', () async {
      final repo = HistoryRepository(db);
      await repo.add(entry('h1'));
      await repo.add(entry('h2', t: 5));
      final all = await repo.watchAll().first;
      expect(all.map((e) => e.id), ['h2', 'h1']);
      final h1 = (await repo.get('h1'))!;
      expect(h1.recipe, saved);
      expect(h1.inputPath, 'inbox/a.jpg');
      expect((h1.sourceWidth, h1.sourceHeight, h1.width, h1.height), (4000, 3000, 8000, 6000));
      expect(h1.modelIds, ['sr.general-x4v3']);
      expect(h1.duration, const Duration(seconds: 42));
      expect(h1.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));
      expect(await repo.get('nope'), isNull);
      expect(await repo.previewPaths(), {'history/h1.jpg', 'history/h2.jpg'});
    });

    test('an entry needs the output it was saved with', () {
      expect(() => entry('x').recipe.output, returnsNormally);
      expect(
        () => HistoryEntry(
          id: 'x',
          createdAt: DateTime(2026),
          recipe: saved.copyWith(output: () => null),
          inputPath: 'i',
          sourceWidth: 1,
          sourceHeight: 1,
          width: 1,
          height: 1,
          previewPath: 'p',
          resultUri: 'u',
          modelIds: const [],
          backend: 'cpu',
          duration: null,
          jobId: 'j',
        ),
        throwsArgumentError,
      );
    });

    test('removal reports the files nothing refers to any more (PRIV-DATA-004)', () async {
      final repo = HistoryRepository(db);
      // Two exports of one result, and another photo.
      await repo.add(entry('h1'));
      await repo.add(entry('h2', t: 1));
      await repo.add(entry('h3', input: 'inbox/b.jpg', job: 'job-2', t: 2));

      var r = await repo.remove('h1');
      expect(r.previews, ['history/h1.jpg']);
      expect(r.jobIds, isEmpty, reason: 'h2 comes from the same job');
      expect(r.inputs, isEmpty, reason: 'h2 comes from the same photo');

      r = await repo.remove('h2');
      expect(r.jobIds, {'job-1'});
      expect(r.inputs, {'inbox/a.jpg'});

      r = await repo.remove('h2');
      expect(r.previews, isEmpty, reason: 'already gone');

      await repo.add(entry('h4', input: 'inbox/b.jpg', job: 'job-2', t: 3));
      r = await repo.removeAll();
      expect(r.previews, unorderedEquals(['history/h3.jpg', 'history/h4.jpg']));
      expect(r.jobIds, {'job-2'});
      expect(r.inputs, {'inbox/b.jpg'});
      expect(await repo.watchAll().first, isEmpty);
      expect(await db.select(db.assets).get(), isEmpty);
      expect(await db.select(db.recipes).get(), isEmpty);
    });
  });

  group('presets', () {
    final r = Recipe(scale: 4, srModel: 'sr.general-x4v3', strength: 0.6);

    test('add, rename, remove', () async {
      final repo = PresetRepository(prefs);
      final a = await repo.add('  Soft ', r, now: DateTime(2026));
      expect(a.name, 'Soft');
      await repo.add('Fast', Recipe(scale: 2, fast2: true, srModel: 'm'), now: DateTime(2027));
      var all = await repo.watchAll().first;
      expect(all.map((p) => p.name), ['Soft', 'Fast']);
      expect(all.first.recipe, r);
      await repo.rename(a.id, 'Gentle');
      await repo.remove(all.last.id);
      all = await repo.watchAll().first;
      expect(all.map((p) => p.name), ['Gentle']);
    });

    test('names are 1..40 characters; presets have no output format', () async {
      final repo = PresetRepository(prefs);
      expect(() => repo.add('   ', r), throwsArgumentError);
      expect(() => repo.add('x' * 41, r), throwsArgumentError);
      expect(
        () => repo.add('Saved', r.copyWith(output: () => OutputSpec(ExportFormat.png))),
        throwsArgumentError,
      );
      final p = await repo.add('ok', r);
      expect(() => repo.rename(p.id, ''), throwsArgumentError);
    });

    test('a presets file round-trips; names already taken get a number (FR-PRE-003)', () async {
      final repo = PresetRepository(prefs);
      await repo.add('Soft', r, now: DateTime(2026));
      final faces = Recipe(scale: 2, srModel: 'sr.general-x4v3', faceModel: 'face.gfpgan-1.4');
      await repo.add('Portrait mine', faces, now: DateTime(2027));
      final text = PresetFile.encode(await repo.watchAll().first);
      final read = PresetFile.decode(text);
      expect(read.map((p) => (p.name, p.recipe)), [('Soft', r), ('Portrait mine', faces)]);
      expect(await repo.importAll(read, now: DateTime(2028)), 2);
      expect((await repo.watchAll().first).map((p) => p.name), [
        'Soft',
        'Portrait mine',
        'Soft (2)',
        'Portrait mine (2)',
      ]);
      await repo.importAll([
        (name: 'x' * 40, recipe: r),
        (name: 'x' * 40, recipe: r),
      ], now: DateTime(2029));
      expect((await repo.watchAll().first).last.name, '${'x' * 36} (2)');
    });

    test('a presets file is checked before anything is added', () {
      for (final bad in [
        'not json',
        '{"presets": []}',
        '{"refocal_presets": 2, "presets": []}',
        '{"refocal_presets": 1, "presets": [{"name": "", "recipe": {}}]}',
        '{"refocal_presets": 1, "presets": [{"name": "a", "recipe": {"scale": 3}}]}',
        '{"refocal_presets": 1, "presets": [1]}',
      ]) {
        expect(() => PresetFile.decode(bad), throwsFormatException, reason: bad);
      }
      expect(PresetFile.decode('{"refocal_presets": 1, "presets": []}'), isEmpty);
    });
  });
}
