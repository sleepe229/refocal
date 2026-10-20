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
    this.heicSupported = false,
  });

  final Engine engine;
  final RefocalPlatformApi platform;

  /// Metadata policy (keepGps, aiMarker) at the time of the save.
  final Settings settings;

  /// Null when the history is off (FR-HIST-005).
  final HistoryStore? history;

  /// HEIC asked on a device without an encoder (a setting restored from another phone) is saved
  /// as JPEG instead (FR-EXP-002, Q-12).
  final bool heicSupported;

  /// Returns the result's URI, or null when the user cancelled the file dialog. A save that
  /// reached its destination but could not be recorded throws [HistoryNotRecorded].
  Future<String?> save(
    JobResult r, {
    required String input,
    required OutputSpec output,
    required double strength,
    Look? look,
    required Destination to,
  }) async {
    if (output.format == ExportFormat.heic && !heicSupported) {
      output = OutputSpec(ExportFormat.jpeg, quality: output.quality ?? settings.quality);
    }
    final format = output.format;
    final history = this.history;
    final entryId = newId();
    final preview = await history?.previewPathFor(entryId);
    await Directory(engine.exportDir).create(recursive: true);
    final name = 'Refocal_${r.jobId}.${format.extension}';
    final tmp = '${engine.exportDir}/$name';
    String? uri;
    try {
      await _encode(r, tmp, output, strength: strength, look: look, thumbnail: preview);
      uri = switch (to) {
        Destination.gallery => await platform.saveToGallery(tmp, name, format.mimeType),
        Destination.file => await platform.saveToFile(tmp, name, format.mimeType),
      };
      AppLog.info(
        'export ${format.name} q${output.quality} strength $strength look ${_lookLog(look)}: '
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
            look: look,
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

extension ResultSharing on ResultSaver {
  /// Hands the result to another app through the system share sheet (06 §3.2), in [output]
  /// with the same metadata policy as a save (location, AI marker). Not a save: nothing goes to
  /// the gallery or the history. The copy stays in cache/share/ for the receiving app to read
  /// (Storage → Cache clears it).
  Future<void> share(
    JobResult r, {
    required OutputSpec output,
    required double strength,
    Look? look,
    required String title,
  }) async {
    if (output.format == ExportFormat.heic && !heicSupported) {
      output = OutputSpec(ExportFormat.jpeg, quality: output.quality ?? settings.quality);
    }
    final dir = await Directory('${engine.dirs.cache}/share').create(recursive: true);
    final path = '${dir.path}/Refocal_${r.jobId}.${output.format.extension}';
    try {
      await _encode(r, path, output, strength: strength, look: look);
    } catch (e, stack) {
      AppLog.error('share ${output.format.name} failed', e, stack);
      await deleteIfPresent(path);
      rethrow;
    }
    AppLog.info('share ${output.format.name} strength $strength look ${_lookLog(look)}');
    await platform.shareFile(path, output.format.mimeType, title);
  }
}

extension on ResultSaver {
  /// The result in [output] at [path], with the metadata of the settings; [thumbnail]: also a
  /// small preview there (the history entry).
  Future<void> _encode(
    JobResult r,
    String path,
    OutputSpec output, {
    required double strength,
    Look? look,
    String? thumbnail,
  }) async {
    final format = output.format;
    final quality = output.quality ?? settings.quality; // ignored by lossless formats
    if (format == ExportFormat.heic) {
      await _exportHeic(
        r,
        path,
        quality: quality,
        strength: strength,
        look: look,
        thumbnail: thumbnail,
      );
      return;
    }
    await engine.session.export(
      r.jobDir,
      path,
      format: format.format,
      quality: quality,
      lossless: format.lossless,
      strength: strength,
      look: look,
      keepGps: settings.keepGps,
      aiMarker: settings.aiMarker,
      thumbnail: thumbnail,
      thumbnailMaxSide: HistoryStore.previewMaxSide,
    );
  }

  /// HEIC (FR-EXP-002): the core writes raw pixels (and the thumbnail), the platform encodes
  /// them, the core adds the metadata to the encoded file (ICC, EXIF, XMP AI marker).
  Future<void> _exportHeic(
    JobResult r,
    String dst, {
    required int quality,
    required double strength,
    Look? look,
    String? thumbnail,
  }) async {
    final raw = '$dst.rgba', encoded = '$dst.enc';
    try {
      await engine.session.export(
        r.jobDir,
        raw,
        format: 'rgba',
        strength: strength,
        look: look,
        thumbnail: thumbnail,
        thumbnailMaxSide: HistoryStore.previewMaxSide,
      );
      await platform.encodeHeic(raw, r.width, r.height, quality, encoded);
      await deleteIfPresent(raw);
      await engine.session.export(
        r.jobDir,
        dst,
        format: 'heic',
        heifInput: encoded,
        strength: strength,
        keepGps: settings.keepGps,
        aiMarker: settings.aiMarker,
      );
    } finally {
      await deleteIfPresent(raw);
      await deleteIfPresent(encoded);
    }
  }
}

String _lookLog(Look? l) =>
    l == null ? 'none' : '${l.id.name} ${l.amount}${l.leaks ? ' leaks' : ''}';

/// A saver with the current settings.
Future<ResultSaver> readResultSaver(Ref ref) async {
  final settings = await ref.read(settingsProvider.future);
  return ResultSaver(
    engine: await ref.read(engineProvider.future),
    platform: ref.read(platformApiProvider),
    settings: settings,
    history: settings.historyEnabled ? await ref.read(historyStoreProvider.future) : null,
    heicSupported: await ref.read(heicSupportedProvider.future),
  );
}
