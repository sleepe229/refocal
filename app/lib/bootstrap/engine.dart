import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';
import 'package:refocal_platform/refocal_platform.dart';

import '../version.dart';
import 'app_log.dart';
import 'job_store.dart';

/// Model bundled with the app (04-ml-models: sr.general-x4v3, denoise 0.5). The weights are not
/// in git; tools/models/fetch.sh puts them into assets/models before a build.
const bundledSrModel = 'sr.general-x4v3';
const _modelFiles = ['model.ncnn.param', 'model.ncnn.bin', 'model.json'];

final platformApiProvider = Provider((_) => RefocalPlatformApi());

final appDirsProvider = FutureProvider<AppDirs>((ref) => ref.watch(platformApiProvider).getDirs());

/// Jobs and inbox copies under AppSupport (07 §2).
JobStore jobStoreOf(AppDirs d) =>
    JobStore(jobsDir: '${d.support}/jobs', inboxDir: '${d.support}/inbox');

class Engine {
  Engine(this.native, this.session, this.dirs, this.modelReady);

  final RefocalNative native;
  final RefocalSession session;
  final AppDirs dirs;
  final bool modelReady;

  String get inboxDir => '${dirs.support}/inbox';
  String get jobsDir => '${dirs.support}/jobs';
  String get exportDir => '${dirs.cache}/export';
  JobStore get jobs => jobStoreOf(dirs);
}

/// Opens the native core once per process and installs the bundled model on first run.
final engineProvider = FutureProvider<Engine>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final models = '${dirs.support}/models';
  final ready = await _installBundledModel(models);
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
    'start: app $appVersion, core ${native.version}, '
    '${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
    'previous exit ${previousExit ?? 'unknown'}, model ${ready ? 'ok' : 'missing'}',
  );
  try {
    await jobStoreOf(dirs).sweep(); // once per process: no screen holds an input yet
  } on FileSystemException catch (e) {
    AppLog.warn('startup sweep: ${e.message}'); // retried at the next start
  }
  final session = native.openSession(
    modelsDir: models,
    workDir: '${dirs.support}/jobs',
    // Crash sentinel + local GPU rules live here (kept across cache clears, ADR-0016).
    cacheDir: '${dirs.support}/core',
    previousExit: previousExit,
  );
  ref.onDispose(session.dispose);
  return Engine(native, session, dirs, ready);
});

Future<bool> _installBundledModel(String modelsDir) async {
  final dir = Directory('$modelsDir/$bundledSrModel');
  final present = await Future.wait(_modelFiles.map((f) => File('${dir.path}/$f').exists()));
  if (present.every((p) => p)) return true;
  try {
    await dir.create(recursive: true);
    for (final f in _modelFiles) {
      final data = await rootBundle.load('assets/models/$bundledSrModel/$f');
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

/// Unfinished and unsaved jobs for the home screen; invalidate after a change.
final jobListProvider = FutureProvider<List<JobEntry>>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  return engine.jobs.list();
});
