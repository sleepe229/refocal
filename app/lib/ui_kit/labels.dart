import 'dart:math' as math;

import 'package:refocal_core/refocal_core.dart';

import '../bootstrap/presets.dart';
import '../l10n/app_localizations.dart';

/// "8×", "4×", "2×", "Fast 2×", "1×" (ADR-0014).
String scaleLabel(AppLocalizations l10n, int scale, {bool fast2 = false}) => switch (scale) {
  _ when fast2 => l10n.scaleFast2,
  8 => l10n.scaleX8,
  4 => l10n.scaleX4,
  2 => l10n.scaleX2,
  1 => l10n.scaleX1,
  _ => '$scale×',
};

String formatLabel(AppLocalizations l10n, ExportFormat f) => switch (f) {
  ExportFormat.jpeg => l10n.formatJpeg,
  ExportFormat.png => l10n.formatPng,
  ExportFormat.webp => l10n.formatWebp,
  ExportFormat.webpLossless => l10n.formatWebpLossless,
  ExportFormat.heic => l10n.formatHeic,
};

/// Why [f] cannot hold a result this large (ExportFormat.maxMegapixels).
String formatTooLargeLabel(AppLocalizations l10n, ExportFormat f) =>
    f == ExportFormat.heic ? l10n.formatHeicTooLarge : l10n.formatWebpTooLarge;

/// The formats this device can write: HEIC only with an encoder (FR-EXP-002, Q-12).
Iterable<ExportFormat> availableFormats({required bool heic}) =>
    ExportFormat.values.where((f) => f != ExportFormat.heic || heic);

String builtinPresetLabel(AppLocalizations l10n, BuiltinPreset p) => switch (p) {
  BuiltinPreset.fast => l10n.presetFast,
  BuiltinPreset.quality => l10n.presetQuality,
  BuiltinPreset.portrait => l10n.presetPortrait,
  BuiltinPreset.oldPhoto => l10n.presetOldPhoto,
  BuiltinPreset.anime => l10n.presetAnime,
};

/// "Standard", "High quality", "Anime" (FR-ENH-008).
String srModelLabel(AppLocalizations l10n, SrModel m) => switch (m) {
  SrModel.compact => l10n.srModelCompact,
  SrModel.hq => l10n.srModelHq,
  SrModel.anime => l10n.srModelAnime,
};

/// "Fast 2× · 80%", plus " · JPEG 92" when the recipe was saved.
String recipeLabel(AppLocalizations l10n, Recipe r) {
  final parts = [
    scaleLabel(l10n, r.scale, fast2: r.fast2),
    l10n.strengthValue((r.strength * 100).round()),
    if (r.faceModel != null) l10n.recipeFaces((r.faceStrength * 100).round()),
    if (r.facesOnly) l10n.regionFaces,
    if (r.output case final o?)
      o.quality == null
          ? formatLabel(l10n, o.format)
          : '${formatLabel(l10n, o.format)} ${o.quality}',
  ];
  return parts.join(' · ');
}

/// Why Auto chose its recipe (FR-ENH-007, 06 §3.2): "4×, faces: 2, denoise medium".
String autoExplanation(AppLocalizations l10n, PhotoAnalysis a, AutoDecision d) {
  final r = d.recipe;
  final parts = [
    scaleLabel(l10n, r.scale, fast2: r.fast2),
    if (a.detector && a.faces > 0) l10n.autoFaces(a.faces),
    if (d.reasons.contains(AutoReason.tooManyFacesForTier))
      l10n.autoFacesNotRestored
    else if (a.faces > 0 && r.faceModel == null)
      l10n.autoFacesNeedPack,
    if (r.facesOnly) l10n.autoFacesOnly,
    if (r.jpegModel != null) l10n.autoJpeg(a.jpegQuality),
    switch (DenoiseLevel.of(r.srModel)) {
      DenoiseLevel.none => l10n.autoDenoiseNone,
      DenoiseLevel.strong => l10n.autoDenoiseStrong,
      DenoiseLevel.standard || null => l10n.autoDenoiseStandard,
    },
  ];
  return parts.join(', ');
}

/// What made the result (FR-CMP-007): "Denoise: Normal · graphics processor · 12 s".
String resultInfo(AppLocalizations l10n, JobResult r) {
  final model = switch (DenoiseLevel.of(r.model)) {
    DenoiseLevel.none => '${l10n.denoise}: ${l10n.denoiseNone}',
    DenoiseLevel.standard => '${l10n.denoise}: ${l10n.denoiseStandard}',
    DenoiseLevel.strong => '${l10n.denoise}: ${l10n.denoiseStrong}',
    null => switch (SrModel.of(r.model)) {
      final m? => '${l10n.srModel}: ${srModelLabel(l10n, m)}',
      null => r.model, // a face pack (region Faces) or another installed model
    },
  };
  final backend = switch (r.backend) {
    final b when b.startsWith('vulkan') => l10n.tierGpu,
    final b when b.startsWith('cpu') => l10n.tierCpu,
    'lanczos' => l10n.regionFaces,
    final b => b,
  };
  return [
    model,
    backend,
    if (r.duration case final d?)
      l10n.resultSeconds(math.max(1, (d.inMilliseconds / 1000).round())),
  ].join(' · ');
}
