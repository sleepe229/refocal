import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'engine.dart';

/// Output formats of the native export (FR-EXP-001). HEIC output is 0.5+ (FR-EXP-002).
enum ExportFormat {
  jpeg('jpeg', false, 'jpg', 'image/jpeg'),
  png('png', false, 'png', 'image/png'),
  webp('webp', false, 'webp', 'image/webp'),
  webpLossless('webp', true, 'webp', 'image/webp');

  const ExportFormat(this.format, this.lossless, this.extension, this.mimeType);

  /// `format` of enh_export.
  final String format;
  final bool lossless;
  final String extension, mimeType;

  /// Uses the quality setting (lossy).
  bool get hasQuality => this == jpeg || this == webp;

  /// WebP encodes a whole picture in memory: the core refuses larger results (ENH_E_LIMIT).
  double get maxMegapixels => switch (this) {
    webp => 50,
    webpLossless => 24,
    _ => double.infinity,
  };
}

/// Export and metadata policy, language, first-run state (FR-SET-001/002/006, FR-ONB-001).
/// A JSON file until the drift database arrives with history (ADR-0009): a few flags do not
/// justify bundling SQLite into a 30 MB APK.
class Settings {
  const Settings({
    this.keepGps = false,
    this.aiMarker = true,
    this.format = ExportFormat.jpeg,
    this.quality = 92,
    this.languageCode,
    this.onboardingDone = false,
  });

  /// PRIV-META-001: location is removed from results unless the user asks to keep it.
  final bool keepGps;

  /// FR-META-004/005: XMP DigitalSourceType marker; can be turned off with a warning.
  final bool aiMarker;

  /// Default format of "Save to gallery" (FR-SET-001).
  final ExportFormat format;

  /// JPEG and lossy WebP, 60..100 (FR-EXP-001).
  final int quality;

  /// null: the system language (FR-SET-006).
  final String? languageCode;

  final bool onboardingDone;

  static const minQuality = 60, maxQuality = 100;

  Settings copyWith({
    bool? keepGps,
    bool? aiMarker,
    ExportFormat? format,
    int? quality,
    String? Function()? languageCode,
    bool? onboardingDone,
  }) => Settings(
    keepGps: keepGps ?? this.keepGps,
    aiMarker: aiMarker ?? this.aiMarker,
    format: format ?? this.format,
    quality: quality ?? this.quality,
    languageCode: languageCode != null ? languageCode() : this.languageCode,
    onboardingDone: onboardingDone ?? this.onboardingDone,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'keep_gps': keepGps,
    'ai_marker': aiMarker,
    'format': format.name,
    'quality': quality,
    'language': languageCode,
    'onboarding_done': onboardingDone,
  };

  factory Settings.fromJson(Map<String, Object?> j) {
    final lang = j['language'];
    return Settings(
      keepGps: j['keep_gps'] == true,
      aiMarker: j['ai_marker'] != false,
      format: ExportFormat.values.asNameMap()[j['format']] ?? ExportFormat.jpeg,
      quality: ((j['quality'] as num?)?.toInt() ?? 92).clamp(minQuality, maxQuality),
      languageCode: AppLocalizations.supportedLocales.any((l) => l.languageCode == lang)
          ? lang as String
          : null,
      // Version 1 files come from 0.0.2: those users have seen the app already.
      onboardingDone: j['onboarding_done'] == true || j['version'] == 1,
    );
  }
}

class SettingsController extends AsyncNotifier<Settings> {
  File? _file;

  @override
  Future<Settings> build() async {
    final dirs = await ref.watch(appDirsProvider.future);
    final f = _file = File('${dirs.support}/settings.json');
    try {
      return Settings.fromJson(jsonDecode(await f.readAsString()) as Map<String, Object?>);
    } on Object {
      return const Settings(); // missing or unreadable: defaults are the private ones
    }
  }

  Future<void> save(Settings s) async {
    state = AsyncData(s);
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.part');
    await tmp.writeAsString(jsonEncode(s.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, Settings>(
  SettingsController.new,
);

/// Strings outside the widget tree (notification texts): the chosen language, else the
/// system's, else English.
final l10nProvider = Provider<AppLocalizations>((ref) {
  final code = ref.watch(settingsProvider).value?.languageCode;
  final locale = code != null
      ? Locale(code)
      : basicLocaleListResolution(
          PlatformDispatcher.instance.locales,
          AppLocalizations.supportedLocales,
        );
  return lookupAppLocalizations(locale);
});
