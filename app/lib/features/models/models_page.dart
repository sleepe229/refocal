import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/models.dart';
import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../storage/storage_page.dart' show formatBytes;

/// Models (06 §1 `/models`, ADR-0011): packs of the last verified manifest, download with
/// progress and cancel, delete; license acceptance for restricted packs (ADR-0022). The
/// network is used only when the user checks for models or downloads one (ADR-0020).
class ModelsPage extends ConsumerWidget {
  const ModelsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final models = ref.watch(modelsProvider);
    final installed = {
      for (final p in ref.watch(installedPacksProvider).value ?? const <InstalledPack>[]) p.id: p,
    };
    final lang =
        ref.watch(settingsProvider).value?.languageCode ??
        Localizations.localeOf(context).languageCode;
    final s = models.value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.modelsTitle)),
      body: models.isLoading && s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  title: Text(l10n.modelsBuiltIn),
                  subtitle: Text(l10n.modelsBuiltInHint),
                  leading: const Icon(Icons.check_circle_outline),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: OutlinedButton.icon(
                    onPressed: s?.checking ?? false ? null : () => _refresh(context, ref),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.modelsCheck),
                  ),
                ),
                if (s?.manifest == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.modelsNotChecked, textAlign: TextAlign.center),
                  )
                else
                  for (final p in s!.manifest!.packs)
                    _PackTile(
                      pack: p,
                      lang: lang,
                      installed: installed[p.id],
                      progress: s.downloads[p.id],
                    ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.modelsPrivacy, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(modelsProvider.notifier).refresh();
    } on ModelError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(modelErrorText(l10n, e))));
    }
  }
}

String modelErrorText(AppLocalizations l10n, ModelError e) => switch (e.kind) {
  ModelErrorKind.network => l10n.modelsErrorNetwork,
  ModelErrorKind.integrity => l10n.modelsErrorIntegrity,
  ModelErrorKind.rollback => l10n.modelsErrorRollback,
  ModelErrorKind.storage => l10n.failDiskFull,
};

class _PackTile extends ConsumerWidget {
  const _PackTile({
    required this.pack,
    required this.lang,
    required this.installed,
    required this.progress,
  });

  final PackInfo pack;
  final String lang;
  final InstalledPack? installed;
  final PackProgress? progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final manager = ref.watch(modelManagerProvider).value;
    final size = manager == null ? 0 : manager.filesFor(pack).fold(0, (n, f) => n + f.size);
    final ctl = ref.read(modelsProvider.notifier);
    final i = installed, p = progress;
    final update = i != null && i.version != pack.version;
    final status = [
      formatBytes(context, size),
      pack.license.spdx,
      if (pack.license.requiresAcceptance) l10n.modelsNonCommercial,
      if (i != null) update ? l10n.modelsUpdate(i.version, pack.version) : l10n.modelsInstalled,
    ].join(' · ');
    return ListTile(
      title: Text(pack.titleFor(lang)),
      isThreeLine: true,
      subtitle: p == null
          ? Text([?pack.descriptionFor(lang), status].join('\n'))
          : Semantics(
              liveRegion: true,
              label: l10n.modelsDownloading((p.fraction * 10).floor() * 10),
              child: ExcludeSemantics(child: LinearProgressIndicator(value: p.fraction)),
            ),
      trailing: p != null
          ? IconButton(
              tooltip: l10n.cancel,
              icon: const Icon(Icons.close),
              onPressed: () => ctl.cancel(pack.id),
            )
          : i != null && !update
          ? IconButton(
              tooltip: l10n.modelsDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ctl.remove(pack.id),
            )
          : IconButton(
              tooltip: update ? l10n.modelsUpdateAction : l10n.modelsDownload,
              icon: const Icon(Icons.download),
              onPressed: () => _download(context, ref),
            ),
    );
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final manager = await ref.read(modelManagerProvider.future);
    try {
      if (pack.license.requiresAcceptance && !await manager.repo.hasConsent(pack)) {
        final text = await manager.licenseText(pack);
        if (!context.mounted) return;
        if (await _accept(context, l10n, text) != true) return;
        await manager.repo.recordConsent(pack);
        AppLog.info('consent: ${pack.id} ${pack.license.spdx}');
      }
      await ref.read(modelsProvider.notifier).install(pack);
    } on ModelError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(modelErrorText(l10n, e))));
    }
  }

  Future<bool?> _accept(BuildContext context, AppLocalizations l10n, String text) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.modelsLicenseTitle(pack.titleFor(lang))),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(l10n.modelsLicenseIntro),
                const SizedBox(height: 12),
                SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.modelsLicenseAccept),
            ),
          ],
        ),
      );
}
