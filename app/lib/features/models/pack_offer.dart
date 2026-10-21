import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/engine.dart';
import '../../bootstrap/models.dart';
import '../../bootstrap/settings.dart';
import '../../bootstrap/tier.dart';
import '../../l10n/app_localizations.dart';
import '../storage/storage_page.dart' show formatBytes;
import 'models_page.dart' show consentTo, modelErrorText;

/// Packs [r] needs that the device does not have (a pack's id is its model's, 04 §2). The
/// detector is built in: a recipe that needs it without it is not offered.
List<String> missingPacks(Recipe r, Set<String> available) => [
  for (final m in [
    r.srModel,
    r.faceModel,
    r.jpegModel,
    r.scratchModel,
    r.inpaintModel,
    r.lowlightModel,
  ])
    if (m != null && m != bundledDetector && !available.contains(m)) m,
];

/// How far the download of [ids] is: null when none of them is downloading, else 0..1 over
/// all of them (an installed one counts as done).
double? packsProgress(WidgetRef ref, List<String> ids) {
  final downloads = ref.watch(modelsProvider).value?.downloads ?? const {};
  if (!ids.any(downloads.containsKey)) return null;
  final available = ref.watch(availableModelsProvider);
  var sum = 0.0;
  for (final id in ids) {
    sum += available.contains(id) ? 1 : downloads[id]?.fraction ?? 0;
  }
  return sum / ids.length;
}

/// A pack made for a faster device than this one (ADR-0017: its tier_min is a speed class,
/// not a limit): offered with a warning, never hidden or refused.
bool _slowOn(PackInfo pack, DeviceTier tier) =>
    tier.index < (DeviceTier.parse(pack.tierMin) ?? DeviceTier.t0).index;

/// FR-FACE-003, FR-ONB-003 (06 §3.3): what a mode or switch needs, offered where it is wanted.
/// One question (size, licence kind); the manifest is fetched on "Download" if the device has
/// none (ADR-0020: the user's action), the licence text is accepted for a restricted pack
/// (ADR-0022), then [ids] download one after another while the editor stays usable (a pack for
/// a faster device says it will be slow here, ADR-0017): the
/// progress is [ModelsController]'s, shown by the caller with [packsProgress]. True once all
/// of them are installed.
Future<bool> offerPacks(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  required String title,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final lang =
      ref.read(settingsProvider).value?.languageCode ??
      Localizations.localeOf(context).languageCode;
  // Read now: the screen may be left while the models download.
  final models = ref.read(modelsProvider.notifier);
  final engine = ref.read(engineProvider.future);
  final tier = ref.read(tierProvider.future);
  final manager = await ref.read(modelManagerProvider.future);
  void tell(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  var manifest = await manager.repo.current();
  List<PackInfo>? packsOf(Manifest? m) {
    final packs = [for (final id in ids) m?.pack(id)];
    return packs.contains(null) ? null : packs.cast<PackInfo>();
  }

  final known = packsOf(manifest);
  final device = (await tier).tier;
  bool slow(List<PackInfo> packs) => packs.any((p) => _slowOn(p, device));
  if (!context.mounted) return false;
  final size = known?.fold(0, (n, p) => n + manager.filesFor(p).fold(0, (n, f) => n + f.size));
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              size == null
                  ? l10n.packOfferBodyNoSize
                  : l10n.packOfferBody(formatBytes(context, size)),
            ),
            if (known != null && slow(known)) ...[
              const SizedBox(height: 4),
              Text(l10n.packSlow, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (known?.any((p) => p.license.requiresAcceptance) ?? false) ...[
              const SizedBox(height: 4),
              Text(l10n.packOfferNonCommercial, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.modelsDownload),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.faceOfferLater),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true) return false;

  try {
    if (known == null) {
      await models.refresh();
      manifest = await manager.repo.current();
    }
    final packs = packsOf(manifest);
    final appVersion = (await engine).version;
    if (packs == null || packs.any((p) => !p.supportedBy(appVersion))) {
      tell(l10n.packUnavailable);
      return false;
    }
    // Not said in the offer: it had no manifest to tell.
    if (known == null && slow(packs)) {
      if (!context.mounted || !await _slowConfirmed(context, l10n)) return false;
    }
    for (final p in packs) {
      if (!context.mounted) return false;
      final title = p.titleFor(lang);
      if (!await consentTo(context, manager, p, title, () => manager.licenseText(p))) return false;
    }
    for (final p in packs) {
      await models.install(p);
    }
  } on ModelError catch (e) {
    tell(modelErrorText(l10n, e));
    return false;
  }
  final installed = {for (final i in await manager.repo.installed()) i.id};
  return ids.every(installed.contains);
}

Future<bool> _slowConfirmed(BuildContext context, AppLocalizations l10n) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.packSlow),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.faceOfferLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.modelsDownload),
          ),
        ],
      ),
    ) ==
    true;
