import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import 'database.dart';
import 'engine.dart';

/// Built-in presets (FR-PRE-001) that the bundled model can run. "Old photo", "Portrait" and
/// "Anime" need the face and anime packs and arrive with them (0.2, 0.5).
enum BuiltinPreset {
  fast,
  quality;

  Recipe get recipe => switch (this) {
    fast => Recipe(scale: 2, fast2: true, srModel: bundledSrModel),
    quality => Recipe(scale: 4, srModel: bundledSrModel),
  };
}

final presetRepositoryProvider = FutureProvider<PresetRepository>(
  (ref) async => PresetRepository(await ref.watch(prefsDatabaseProvider.future)),
);

/// User presets (FR-PRE-002) in the order they were saved.
final presetsProvider = StreamProvider<List<Preset>>((ref) async* {
  final repo = await ref.watch(presetRepositoryProvider.future);
  yield* repo.watchAll();
});
