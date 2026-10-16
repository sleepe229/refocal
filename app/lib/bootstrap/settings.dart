import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../l10n/app_localizations.dart';
import 'database.dart';
import 'engine.dart';

/// Export and metadata policy, language, history, batch autosave, first-run state
/// (FR-SET-001/002/006, FR-HIST-005, FR-BATCH-006, FR-ONB-001). Stored in the `settings` table (ADR-0009, 07 §3) as strings.
class Settings {
  const Settings({
    this.keepGps = false,
    this.aiMarker = true,
    this.format = ExportFormat.jpeg,
    this.quality = 92,
    this.languageCode,
    this.onboardingDone = false,
    this.historyEnabled = true,
    this.batchAutosave = true,
    this.faceNoticeSeen = false,
    this.faceOfferDismissed = false,
    this.tierOverride,
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

  /// FR-HIST-005: off records nothing (and the history is cleared when it is turned off).
  final bool historyEnabled;

  /// FR-BATCH-006: a batch saves each result to the app album in [format] when it is done.
  final bool batchAutosave;

  /// ADR-0022: the warning about face restoration was shown (first use only).
  final bool faceNoticeSeen;

  /// FR-ONB-003: the home screen's offer of the face model was dismissed.
  final bool faceOfferDismissed;

  /// FR-SET-003: "T0".."T2" chosen by the user; null: the benchmark decides.
  final String? tierOverride;

  Settings copyWith({
    bool? keepGps,
    bool? aiMarker,
    ExportFormat? format,
    int? quality,
    String? Function()? languageCode,
    bool? onboardingDone,
    bool? historyEnabled,
    bool? batchAutosave,
    bool? faceNoticeSeen,
    bool? faceOfferDismissed,
    String? Function()? tierOverride,
  }) => Settings(
    keepGps: keepGps ?? this.keepGps,
    aiMarker: aiMarker ?? this.aiMarker,
    format: format ?? this.format,
    quality: quality ?? this.quality,
    languageCode: languageCode != null ? languageCode() : this.languageCode,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    historyEnabled: historyEnabled ?? this.historyEnabled,
    batchAutosave: batchAutosave ?? this.batchAutosave,
    faceNoticeSeen: faceNoticeSeen ?? this.faceNoticeSeen,
    faceOfferDismissed: faceOfferDismissed ?? this.faceOfferDismissed,
    tierOverride: tierOverride != null ? tierOverride() : this.tierOverride,
  );

  /// Rows of the `settings` table; null removes the key (the system language).
  Map<String, String?> toStore() => {
    'keep_gps': '$keepGps',
    'ai_marker': '$aiMarker',
    'format': format.name,
    'quality': '$quality',
    'language': languageCode,
    'onboarding_done': '$onboardingDone',
    'history_enabled': '$historyEnabled',
    'batch_autosave': '$batchAutosave',
    'face_notice_seen': '$faceNoticeSeen',
    'face_offer_dismissed': '$faceOfferDismissed',
    'tier_override': tierOverride,
  };

  /// The values are validated here, once: anything missing, unknown or out of range is the
  /// default, and the defaults are the private choices.
  factory Settings.fromStore(Map<String, String> m) {
    const d = Settings();
    bool flag(String key, bool fallback) => switch (m[key]) {
      'true' => true,
      'false' => false,
      _ => fallback,
    };
    final quality = int.tryParse(m['quality'] ?? '');
    return Settings(
      keepGps: flag('keep_gps', d.keepGps),
      aiMarker: flag('ai_marker', d.aiMarker),
      format: ExportFormat.values.asNameMap()[m['format']] ?? d.format,
      quality: quality?.clamp(ExportFormat.minQuality, ExportFormat.maxQuality) ?? d.quality,
      languageCode: _supported(m['language']),
      onboardingDone: flag('onboarding_done', d.onboardingDone),
      historyEnabled: flag('history_enabled', d.historyEnabled),
      batchAutosave: flag('batch_autosave', d.batchAutosave),
      faceNoticeSeen: flag('face_notice_seen', d.faceNoticeSeen),
      faceOfferDismissed: flag('face_offer_dismissed', d.faceOfferDismissed),
      tierOverride: const {'T0', 'T1', 'T2'}.contains(m['tier_override'])
          ? m['tier_override']
          : null,
    );
  }

  /// settings.json of 0.0.2–0.0.3 (see [importLegacySettings]).
  factory Settings.fromLegacyJson(Map<String, Object?> j) {
    final lang = j['language'];
    return Settings(
      keepGps: j['keep_gps'] == true,
      aiMarker: j['ai_marker'] != false,
      format: ExportFormat.values.asNameMap()[j['format']] ?? ExportFormat.jpeg,
      quality: ((j['quality'] as num?)?.toInt() ?? 92).clamp(
        ExportFormat.minQuality,
        ExportFormat.maxQuality,
      ),
      languageCode: _supported(lang is String ? lang : null),
      // Version 1 files come from 0.0.2: those users have seen the app already.
      onboardingDone: j['onboarding_done'] == true || j['version'] == 1,
    );
  }

  static String? _supported(String? code) =>
      AppLocalizations.supportedLocales.any((l) => l.languageCode == code) ? code : null;
}

/// Moves settings.json of 0.0.2–0.0.3 into the database once (ADR-0009) and deletes it.
///
/// The file is imported only into an empty table: settings already in the database were
/// imported or changed after an earlier import whose delete failed. A file that is not JSON
/// holds nothing to import (0.0.3 read it as the defaults) and is deleted as well. A file that
/// cannot be read or deleted now stays for the next start: the app runs on the database values.
Future<void> importLegacySettings(SettingsStore store, String supportDir) async {
  final file = File('$supportDir/settings.json');
  // The temporary file of an interrupted 0.0.3 save: never the current settings.
  final part = File('${file.path}.part');
  try {
    if (await part.exists()) await part.delete();
    if (!await file.exists()) return;
    Map<String, Object?>? legacy;
    try {
      final decoded = jsonDecode(await file.readAsString());
      legacy = decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      legacy = null;
    }
    if (legacy != null && (await store.read()).isEmpty) {
      await store.write(Settings.fromLegacyJson(legacy).toStore());
    }
    await file.delete();
  } on FileSystemException {
    // Retried on the next start (see above).
  }
}

class SettingsController extends AsyncNotifier<Settings> {
  late SettingsStore _store;

  /// The last queued write; updates run one after another.
  Future<void> _writes = Future.value();

  @override
  Future<Settings> build() async {
    final db = await ref.watch(prefsDatabaseProvider.future);
    final dirs = await ref.watch(appDirsProvider.future);
    _store = SettingsStore(db);
    await importLegacySettings(_store, dirs.support);
    return Settings.fromStore(await _store.read());
  }

  /// Applies [edit] to the stored settings. Updates are serialized, each starts from the
  /// result of the previous one, and the state changes only after the write: it always shows
  /// what is stored. A failed write throws here and leaves the state as it was.
  Future<void> change(Settings Function(Settings) edit) {
    final run = _writes.then((_) async {
      final current = await future;
      final next = edit(current);
      final before = current.toStore();
      final changed = {
        for (final MapEntry(:key, :value) in next.toStore().entries)
          if (before[key] != value) key: value,
      };
      if (changed.isEmpty) return;
      await _store.write(changed);
      state = AsyncData(next);
    });
    // The queue goes on after a failure; the caller gets the error from `run`.
    _writes = run.then<void>((_) {}, onError: (Object _) {});
    return run;
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
