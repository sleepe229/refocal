import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';
import 'package:refocal_platform/refocal_platform.dart';

/// Model bundled with the app (04-ml-models: sr.general-x4v3, denoise 0.5). The weights are not
/// in git; tools/models/fetch.sh puts them into assets/models before a build.
const bundledSrModel = 'sr.general-x4v3';
const _modelFiles = ['model.ncnn.param', 'model.ncnn.bin', 'model.json'];

final platformApiProvider = Provider((_) => RefocalPlatformApi());

final appDirsProvider = FutureProvider<AppDirs>((ref) => ref.watch(platformApiProvider).getDirs());

class Engine {
  Engine(this.native, this.session, this.dirs, this.modelReady);

  final RefocalNative native;
  final RefocalSession session;
  final AppDirs dirs;
  final bool modelReady;

  String get inboxDir => '${dirs.support}/inbox';
  String get exportDir => '${dirs.cache}/export';
}

/// Opens the native core once per process and installs the bundled model on first run.
final engineProvider = FutureProvider<Engine>((ref) async {
  final dirs = await ref.watch(appDirsProvider.future);
  final models = '${dirs.support}/models';
  final ready = await _installBundledModel(models);
  final native = RefocalNative.open();
  final session = native.openSession(
    modelsDir: models,
    workDir: '${dirs.support}/jobs',
    // Crash sentinel + local GPU rules live here (kept across cache clears, ADR-0016).
    cacheDir: '${dirs.support}/core',
    previousExit: await ref.read(platformApiProvider).lastExitReason(),
  );
  ref.onDispose(session.dispose);
  return Engine(native, session, dirs, ready);
});

Future<bool> _installBundledModel(String modelsDir) async {
  final dir = Directory('$modelsDir/$bundledSrModel');
  if (_modelFiles.every((f) => File('${dir.path}/$f').existsSync())) return true;
  try {
    dir.createSync(recursive: true);
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
