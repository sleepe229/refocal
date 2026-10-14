import '../bootstrap/settings.dart';
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
