import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';
import 'package:refocal_platform/refocal_platform.dart';

import 'app_log.dart';
import 'processing.dart';

/// Model bundled with the app (04-ml-models: sr.general-x4v3, denoise 0.5). The weights are not
/// in git; tools/models/fetch.sh puts them into assets/models before a build.
const bundledSrModel = 'sr.general-x4v3';

/// Face detector bundled with the app (ADR-0011: YuNet, MIT); face restoration comes in packs.
const bundledDetector = 'det.yunet-2023mar';

/// ADR-0025: denoise level 0 is bundled too (Auto picks it for clean photos, ADR-0015). The id
/// and files are those of the pack `sr.general-x4v3-dn0`, which installed copies keep using.
const bundledNoDenoiseModel = 'sr.general-x4v3-dn0';

/// Files of the bundled models in `assets/models/<id>/` (tools/models/fetch.sh, models.lock).
const _bundled = {
  bundledSrModel: ['model.ncnn.param', 'model.ncnn.bin', 'model.json'],
  bundledDetector: ['model.ncnn.param', 'model.ncnn.bin'],
  bundledNoDenoiseModel: ['model.ncnn.param', 'model.ncnn.bin', 'model.json'],
};

/// The ids of the bundled models (the model list does not offer them as packs).
final bundledModelIds = _bundled.keys.toSet();

final platformApiProvider = Provider((_) => RefocalPlatformApi());

/// Whether HEIC can be offered on this device (FR-EXP-002, Q-12); asked once.
final heicSupportedProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.read(platformApiProvider).heicSupported();
  } on Exception catch (e) {
    AppLog.warn('heicSupported: $e');
    return false;
  }
});

final appDirsProvider = FutureProvider<AppDirs>((ref) => ref.watch(platformApiProvider).getDirs());

class Engine {
  Engine(
    this.native,
    this.session,
    this.dirs,
    this.modelReady, {
    this.detectorReady = false,
    this.noDenoiseReady = false,
  });

  final RefocalNative native;
  final RefocalSession session;
  final AppDirs dirs;
  final bool modelReady;

  /// The face detector is installed: face restoration can run once a face pack is.
  final bool detectorReady;

  /// The bundled denoise level 0 is installed (ADR-0025).
  final bool noDenoiseReady;

  /// The app version: `version:` of app/pubspec.yaml without `+build`, compiled into the core
  /// by native/CMakeLists.txt (the only copy).
  String get version => native.version;

  String get inboxDir => '${dirs.support}/inbox';
  String get jobsDir => '${dirs.support}/jobs';
  String get exportDir => '${dirs.cache}/export';
}

/// Opens the native core once per process and installs the bundled model on first run.
final engineProvider = FutureProvider<Engine>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final models = '${dirs.support}/models';
  final ready = await _installBundledModel(models, bundledSrModel);
  final detector = await _installBundledModel(models, bundledDetector);
  final noDenoise = await _installBundledModel(models, bundledNoDenoiseModel);
  final native = RefocalNative.open();
  try {
    final logs = await Directory('${dirs.support}/logs').create(recursive: true);
    AppLog.open(native, logs.path);
  } on FileSystemException catch (e) {
    debugPrint('log file unavailable: ${e.message}'); // the app works without it
  } on EnhException catch (e) {
    debugPrint('log file unavailable: ${e.status.name}'); // the app works without it
  }
  final previousExit = await ref.read(platformApiProvider).lastExitReason();
  AppLog.info(
    'start: Refocal ${native.version}, '
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
    'previous exit ${previousExit ?? 'unknown'}, model ${ready ? 'ok' : 'missing'}',
  );
  final session = native.openSession(
    modelsDir: models,
    workDir: '${dirs.support}/jobs',
    // Crash sentinel + local GPU rules live here (kept across cache clears, ADR-0016).
    cacheDir: '${dirs.support}/core',
    previousExit: previousExit,
  );
  ref.onDispose(session.dispose);
  // NFR-THERM-002: the core throttles or waits on the platform's thermal level.
  final platform = ref.read(platformApiProvider);
  final thermal = ProcessingActions.instance.thermal.listen(session.setThermal);
  ref.onDispose(thermal.cancel);
  // NFR-MEM-004: a memory warning halves the next tile of the running job.
  final memory = ProcessingActions.instance.memory.listen((level) {
    AppLog.warn('memory pressure $level');
    session.setMemoryPressure(level);
  });
  ref.onDispose(memory.cancel);
  try {
    session.setThermal(await platform.thermalLevel());
  } on PlatformException catch (e) {
    AppLog.warn('thermal level: ${e.code}'); // nominal until the first change
  }
  return Engine(native, session, dirs, ready, detectorReady: detector, noDenoiseReady: noDenoise);
});

Future<bool> _installBundledModel(String modelsDir, String id) async {
  final files = _bundled[id]!;
  final dir = Directory('$modelsDir/$id');
  final present = await Future.wait(files.map((f) => File('${dir.path}/$f').exists()));
  if (present.every((p) => p)) return true;
  try {
    await dir.create(recursive: true);
    for (final f in files) {
      final data = await rootBundle.load('assets/models/$id/$f');
      final tmp = File('${dir.path}/$f.part');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await tmp.rename('${dir.path}/$f');
    }
    return true;
  } on FlutterError {
    return false; // asset missing: built without tools/models/fetch.sh
  }
}
