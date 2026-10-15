import 'package:refocal_core/refocal_core.dart';

import '../bootstrap/presets.dart';
import '../l10n/app_localizations.dart';

/// "4×", "2×", "Fast 2×", "1×" (ADR-0014).
String scaleLabel(AppLocalizations l10n, int scale, {bool fast2 = false}) => switch (scale) {
  _ when fast2 => l10n.scaleFast2,
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
};

String builtinPresetLabel(AppLocalizations l10n, BuiltinPreset p) => switch (p) {
  BuiltinPreset.fast => l10n.presetFast,
  BuiltinPreset.quality => l10n.presetQuality,
  BuiltinPreset.portrait => l10n.presetPortrait,
  BuiltinPreset.oldPhoto => l10n.presetOldPhoto,
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
