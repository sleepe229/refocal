import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import 'database.dart';
import 'engine.dart';

/// Built-in presets (FR-PRE-001). "Portrait" and "Old photo" need the face pack (and "Old
/// photo" the strong denoise pack), "Anime" the anime pack (FR-ENH-016).
enum BuiltinPreset {
  fast,
  quality,
  portrait,
  oldPhoto,
  anime;

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
    anime => Recipe(scale: 4, srModel: SrModel.anime.model),
  };
}

/// SR models to choose from (FR-ENH-008, 04 §1): the compact one, whose denoise levels are
/// [DenoiseLevel]s, and the RRDBNet packs, each from its tier up (ADR-0017).
enum SrModel {
  compact(bundledSrModel, DeviceTier.t0),
  hq('sr.x4plus', DeviceTier.t2),
  anime('sr.x4plus-anime6b', DeviceTier.t1);

  const SrModel(this.model, this.tierMin);
  final String model;
  final DeviceTier tierMin;

  /// Null for a model that is none of these (a face pack).
  static SrModel? of(String model) =>
      DenoiseLevel.of(model) != null ? compact : values.where((m) => m.model == model).firstOrNull;
}

/// Denoise levels (ADR-0015): baked into separate models; 0.5 and 0 built in (0 since ADR-0025,
/// also still a pack), 1.0 in a Compact+ pack.
enum DenoiseLevel {
  none(bundledNoDenoiseModel),
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
