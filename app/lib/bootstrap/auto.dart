import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import 'app_log.dart';
import 'engine.dart';
import 'models.dart';
import 'presets.dart';
import 'tier.dart';

/// enh_analyze of a photo (FR-ENH-007), once per input while the editor shows it.
final photoAnalysisProvider = FutureProvider.autoDispose.family<PhotoAnalysis, String>((
  ref,
  input,
) async {
  final engine = await ref.watch(engineProvider.future);
  final a = await engine.session.analyze(input);
  AppLog.info(
    'analyze: ${a.megapixels.toStringAsFixed(1)} MP, noise ${a.noiseSigma.toStringAsFixed(1)}, '
    'faces ${a.detector ? a.faces : '-'}',
  );
  return a;
});

class AutoProposal {
  const AutoProposal(this.analysis, this.decision);
  final PhotoAnalysis analysis;
  final AutoDecision decision;
}

/// What Auto v1 proposes for [input] on this device with the models installed now; follows
/// the tier and installed packs as they settle.
final autoProvider = Provider.autoDispose.family<AsyncValue<AutoProposal>, String>((ref, input) {
  final available = ref.watch(availableModelsProvider);
  final models = AutoModels(
    standard: bundledSrModel,
    none: available.contains(DenoiseLevel.none.model) ? DenoiseLevel.none.model : null,
    strong: available.contains(DenoiseLevel.strong.model) ? DenoiseLevel.strong.model : null,
    facePack: available.contains(defaultFacePack) && available.contains(bundledDetector)
        ? defaultFacePack
        : null,
    jpegPack: available.contains(jpegPack) ? jpegPack : null,
  );
  final analysis = ref.watch(photoAnalysisProvider(input));
  final tier = switch (ref.watch(tierProvider)) {
    AsyncData(:final value) => value.tier,
    AsyncError() => DeviceTier.t0, // the safe tier, as the session's
    _ => null,
  };
  return switch ((analysis, tier)) {
    (AsyncData(value: final a), final t?) => AsyncData(
      AutoProposal(a, const AutoPolicy().decide(a, t, models)),
    ),
    (AsyncError(:final error, :final stackTrace), _) => AsyncError(error, stackTrace),
    _ => const AsyncLoading(),
  };
});
