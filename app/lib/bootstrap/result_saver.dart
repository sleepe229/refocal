import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';
import 'package:refocal_platform/refocal_platform.dart';

import 'app_log.dart';
import 'engine.dart';
import 'files.dart';
import 'history.dart';
import 'settings.dart';

/// The result was saved ([uri]) but its history entry could not be written.
class HistoryNotRecorded implements Exception {
  const HistoryNotRecorded(this.uri, this.cause);
  final String uri;
  final Exception cause;
}

/// Where an export goes: the app album (FR-EXP-004) or a document the user picks (FR-EXP-006).
enum Destination { gallery, file }

/// Exports a finished job and records it in the history (FR-EXP-*, FR-HIST-001), for the
/// editor and the queue alike. Any number of exports from one result, without processing
/// again (FR-EXP-007).
class ResultSaver {
  ResultSaver({
    required this.engine,
    required this.platform,
    required this.settings,
    required this.history,
  });

  final Engine engine;
  final RefocalPlatformApi platform;

  /// Metadata policy (keepGps, aiMarker) at the time of the save.
  final Settings settings;

  /// Null when the history is off (FR-HIST-005).
  final HistoryStore? history;

  /// Returns the result's URI, or null when the user cancelled the file dialog. A save that
  /// reached its destination but could not be recorded throws [HistoryNotRecorded].
  Future<String?> save(
    JobResult r, {
    required String input,
    required OutputSpec output,
    required double strength,
    required Destination to,
  }) async {
    final format = output.format;
    final history = this.history;
    final entryId = newId();
    final preview = await history?.previewPathFor(entryId);
    await Directory(engine.exportDir).create(recursive: true);
    final name = 'Refocal_${r.jobId}.${format.extension}';
    final tmp = '${engine.exportDir}/$name';
    String? uri;
    try {
      await engine.session.export(
        r.jobDir,
        tmp,
        format: format.format,
        quality: output.quality ?? settings.quality, // ignored by lossless formats
        lossless: format.lossless,
        strength: strength,
        keepGps: settings.keepGps,
        aiMarker: settings.aiMarker,
        thumbnail: preview,
        thumbnailMaxSide: HistoryStore.previewMaxSide,
      );
      uri = switch (to) {
        Destination.gallery => await platform.saveToGallery(tmp, name, format.mimeType),
        Destination.file => await platform.saveToFile(tmp, name, format.mimeType),
      };
      AppLog.info(
        'export ${format.name} q${output.quality} strength $strength: '
        '${uri == null ? 'cancelled' : 'saved'}',
      );
    } catch (e, stack) {
      AppLog.error('export ${format.name} failed', e, stack);
      if (preview != null) await deleteIfPresent(preview);
      rethrow;
    } finally {
      await deleteIfPresent(tmp); // the export copy is delivered or abandoned
    }
    if (history == null || preview == null) return uri;
    if (uri == null) {
      await deleteIfPresent(preview); // cancelled: nothing was saved
      return null;
    }
    try {
      await history.repo.add(
        HistoryEntry(
          id: entryId,
          createdAt: DateTime.now(),
          recipe: Recipe(
            scale: r.scale,
            fast2: r.fast2,
            srModel: r.model,
            strength: strength,
            output: output,
          ),
          inputPath: history.relative(input),
          sourceWidth: r.inputWidth,
          sourceHeight: r.inputHeight,
          width: r.width,
          height: r.height,
          previewPath: history.relative(preview),
          resultUri: uri,
          modelIds: [r.model],
          backend: r.backend,
          duration: r.duration,
          jobId: r.jobId,
        ),
      );
    } on Exception catch (e) {
      await deleteIfPresent(preview);
      throw HistoryNotRecorded(uri, e);
    }
    return uri;
  }
}

/// A saver with the current settings.
Future<ResultSaver> readResultSaver(Ref ref) async {
  final settings = await ref.read(settingsProvider.future);
  return ResultSaver(
    engine: await ref.read(engineProvider.future),
    platform: ref.read(platformApiProvider),
    settings: settings,
    history: settings.historyEnabled ? await ref.read(historyStoreProvider.future) : null,
  );
}
