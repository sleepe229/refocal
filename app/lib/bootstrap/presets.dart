import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import 'database.dart';
import 'engine.dart';

/// Built-in presets (FR-PRE-001). "Portrait" and "Old photo" need the face pack (and "Old
/// photo" the strong denoise pack); "Anime" arrives with the anime pack (0.5).
enum BuiltinPreset {
  fast,
  quality,
  portrait,
  oldPhoto;

  Recipe get recipe => switch (this) {
    fast => Recipe(scale: 2, fast2: true, srModel: bundledSrModel),
    quality => Recipe(scale: 4, srModel: bundledSrModel),
    portrait => Recipe(scale: 2, srModel: bundledSrModel, faceModel: 'face.gfpgan-1.4'),
    oldPhoto => Recipe(
      scale: 2,
      srModel: DenoiseLevel.strong.model,
      faceModel: 'face.gfpgan-1.4',
      faceStrength: 0.7,
    ),
  };
}

/// Denoise levels (ADR-0015): baked into separate models, 0.5 built in, 0 and 1.0 in the
/// Compact+ packs.
enum DenoiseLevel {
  none('sr.general-x4v3-dn0'),
  standard(bundledSrModel),
  strong('sr.general-x4v3-dn100');

  const DenoiseLevel(this.model);
  final String model;

  static DenoiseLevel? of(String model) => values.where((d) => d.model == model).firstOrNull;
}

final presetRepositoryProvider = FutureProvider<PresetRepository>(
  (ref) async => PresetRepository(await ref.watch(prefsDatabaseProvider.future)),
);

/// User presets (FR-PRE-002) in the order they were saved.
final presetsProvider = StreamProvider<List<Preset>>((ref) async* {
  final repo = await ref.watch(presetRepositoryProvider.future);
  yield* repo.watchAll();
});
