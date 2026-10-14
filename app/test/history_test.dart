import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/engine.dart';
import 'package:refocal/bootstrap/history.dart';
import 'package:refocal/bootstrap/job_store.dart';
import 'package:refocal/bootstrap/presets.dart';
import 'package:refocal/features/editor/enhance_controller.dart';
import 'package:refocal_core/refocal_core.dart';

void main() {
  late Directory root;
  late RefocalDatabase db;
  late HistoryStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('refocal-history');
    db = RefocalDatabase.memory();
    store = HistoryStore(
      HistoryRepository(db),
      root.path,
      JobStore(jobsDir: '${root.path}/jobs', inboxDir: '${root.path}/inbox'),
    );
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  /// An exported result as the editor leaves it: input copy, finished job, preview, entry.
  Future<(String input, String job, String preview)> saved(
    String id, {
    String inputName = 'in-1.jpg',
    String jobId = 'job-1',
  }) async {
    final input = File('${root.path}/inbox/$inputName')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final job = Directory('${root.path}/jobs/$jobId')..createSync(recursive: true);
    File('${job.path}/request.json').writeAsStringSync(
      jsonEncode({'schema': 1, 'job_id': jobId, 'input': input.path, 'scale': 4}),
    );
    File('${job.path}/result.json').writeAsStringSync('{}');
    final preview = File(store.previewPathFor(id))..writeAsStringSync('jpeg');
    await store.repo.add(
      HistoryEntry(
        id: id,
        createdAt: DateTime.now(),
        recipe: Recipe(
          scale: 4,
          srModel: bundledSrModel,
          output: OutputSpec(ExportFormat.jpeg, quality: 92),
        ),
        inputPath: store.relative(input.path),
        sourceWidth: 10,
        sourceHeight: 10,
        width: 40,
        height: 40,
        previewPath: store.relative(preview.path),
        resultUri: 'content://media/$id',
        modelIds: const [bundledSrModel],
        backend: 'cpu',
        duration: null,
        jobId: jobId,
      ),
    );
    return (input.path, job.path, preview.path);
  }

  test('paths in the database are relative to AppSupport', () {
    expect(store.relative('${root.path}/inbox/a.jpg'), 'inbox/a.jpg');
    expect(store.absolute('inbox/a.jpg'), '${root.path}/inbox/a.jpg');
    expect(() => store.relative('/elsewhere/a.jpg'), throwsArgumentError);
  });

  test('deleting an entry deletes its preview, BandStore and inbox copy (PRIV-DATA-004)', () async {
    final (input, job, preview) = await saved('h1');
    final (_, _, preview2) = await saved('h2'); // a second export of the same result
    await store.remove('h1');
    expect(File(preview).existsSync(), isFalse);
    expect(Directory(job).existsSync(), isTrue, reason: 'h2 still refers to the job');
    expect(File(input).existsSync(), isTrue);
    await store.remove('h2');
    expect(File(preview2).existsSync(), isFalse);
    expect(Directory(job).existsSync(), isFalse);
    expect(File(input).existsSync(), isFalse);
  });

  test('clearing leaves no orphans in inbox, jobs or previews (TEST-INT-006)', () async {
    await saved('h1');
    await saved('h2', inputName: 'in-2.jpg', jobId: 'job-2');
    await store.clear();
    expect(await store.repo.watchAll().first, isEmpty);
    for (final d in ['inbox', 'jobs', 'history']) {
      expect(Directory('${root.path}/$d').listSync(), isEmpty, reason: d);
    }
  });

  test('an inbox copy a paused job still uses is kept', () async {
    final (input, _, _) = await saved('h1');
    final paused = Directory('${root.path}/jobs/job-paused')..createSync();
    File('${paused.path}/request.json').writeAsStringSync(
      jsonEncode({'schema': 1, 'job_id': 'job-paused', 'input': input, 'scale': 2}),
    );
    await store.remove('h1');
    expect(File(input).existsSync(), isTrue);
  });

  test('the startup sweep deletes previews without an entry', () async {
    final (_, _, preview) = await saved('h1');
    final orphan = File(store.previewPathFor('crashed'))..writeAsStringSync('x');
    final part = File('${store.previewPathFor('crashed2')}.part')..writeAsStringSync('x');
    await store.sweep();
    expect(File(preview).existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
    expect(part.existsSync(), isFalse);
  });

  test('built-in presets run on the bundled model and map to scale choices', () {
    expect(ScaleChoice.of(BuiltinPreset.fast.recipe), ScaleChoice.fast2);
    expect(ScaleChoice.of(BuiltinPreset.quality.recipe), ScaleChoice.x4);
    for (final b in BuiltinPreset.values) {
      expect(b.recipe.srModel, bundledSrModel);
      expect(b.recipe.output, isNull);
    }
    for (final c in ScaleChoice.values) {
      expect(ScaleChoice.of(Recipe(scale: c.scale, fast2: c.fastPath, srModel: 'm')), c);
    }
  });
}
