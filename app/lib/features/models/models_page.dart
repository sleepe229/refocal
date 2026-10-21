import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/models.dart';
import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../storage/storage_page.dart' show formatBytes;

/// Models (06 §1 `/models`, ADR-0011): packs of the last verified manifest, download with
/// progress and cancel, delete; license acceptance for restricted packs (ADR-0022). The
/// network is used only when the user checks for models or downloads one (ADR-0020). Offline
/// packs (.rfpack, FR-MODEL-006) are imported from a file with the same checks.
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
    // Packs that need a newer app are not offered (min_app_version).
    final appVersion = ref.watch(engineProvider).value?.version;
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton.icon(
                    onPressed: () => _import(context, ref, lang),
                    icon: const Icon(Icons.file_open_outlined),
                    label: Text(l10n.modelsImport),
                  ),
                ),
                if (s?.manifest == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.modelsNotChecked, textAlign: TextAlign.center),
                  )
                else
                  for (final p in s!.manifest!.packs)
                    // A pack that is also bundled (ADR-0025: denoise level 0) is not offered.
                    if (appVersion != null &&
                        p.supportedBy(appVersion) &&
                        !bundledModelIds.contains(p.id))
                      _PackTile(
                        pack: p,
                        lang: lang,
                        installed: installed[p.id],
                        progress: s.downloads[p.id],
                      ),
                // Installed from a file, or no longer in the manifest: still listed, to delete.
                for (final i in installed.values)
                  if (s?.manifest?.pack(i.id) == null)
                    ListTile(
                      title: Text(i.titleFor(lang)),
                      subtitle: Text('${i.version} · ${l10n.modelsInstalled}'),
                      trailing: IconButton(
                        tooltip: l10n.modelsDelete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref.read(modelsProvider.notifier).remove(i.id),
                      ),
                    ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.modelsPrivacy, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
    );
  }

  /// FR-MODEL-006: a .rfpack from the device, no network.
  Future<void> _import(BuildContext context, WidgetRef ref, String lang) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final manager = await ref.read(modelManagerProvider.future);
    String? path;
    try {
      path = await ref
          .read(platformApiProvider)
          .pickFile('${manager.tmpDir}/import', _maxRfpackBytes);
      if (path == null) return;
      final p = await manager.openOffline(path);
      if (!context.mounted) return;
      final title = p.pack.titleFor(lang);
      if (!await consentTo(context, manager, p.pack, title, () async => p.licenseText)) return;
      await ref.read(modelsProvider.notifier).installOffline(p);
      messenger.showSnackBar(SnackBar(content: Text(l10n.modelsImported(p.pack.titleFor(lang)))));
    } on ModelError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(modelErrorText(l10n, e))));
    } on PlatformException catch (e) {
      AppLog.warn('rfpack pick: ${e.code}');
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.code == 'limit' ? l10n.modelsErrorNotAPack : l10n.modelsErrorStorage),
        ),
      );
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException catch (e) {
          AppLog.warn('rfpack copy: ${e.message}'); // in the cache: cleared with it
        }
      }
    }
  }

  /// SEC-INP-005: what the core unpacks at most.
  static const _maxRfpackBytes = 2 << 30;

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
  ModelErrorKind.notAPack => l10n.modelsErrorNotAPack,
};

/// ADR-0022: a restricted pack's licence [text] is accepted once (again when the text
/// changes); true when [pack] may be installed.
Future<bool> consentTo(
  BuildContext context,
  ModelManager manager,
  PackInfo pack,
  String title,
  Future<String> Function() text,
) async {
  if (!pack.license.requiresAcceptance || await manager.repo.hasConsent(pack)) return true;
  final body = await text();
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  if (await _acceptLicense(context, l10n, title, body) != true) return false;
  await manager.repo.recordConsent(pack);
  AppLog.info('consent: ${pack.id} ${pack.license.spdx}');
  return true;
}

/// The license text before a restricted pack is installed (ADR-0022); true when accepted.
Future<bool?> _acceptLicense(
  BuildContext context,
  AppLocalizations l10n,
  String title,
  String text,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(l10n.modelsLicenseTitle(title)),
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
      if (!context.mounted) return;
      final title = pack.titleFor(lang);
      if (!await consentTo(context, manager, pack, title, () => manager.licenseText(pack))) return;
      await ref.read(modelsProvider.notifier).install(pack);
    } on ModelError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(modelErrorText(l10n, e))));
    }
  }
}
