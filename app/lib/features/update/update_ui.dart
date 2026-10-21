import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/app_update.dart';
import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';

/// The home screen's card for an app update (FR-UPD-*, ADR-0027): shown only while there is
/// something to say; nothing at all in builds without self-update.
class AppUpdateCard extends ConsumerWidget {
  const AppUpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!selfUpdate) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final ctl = ref.read(appUpdateProvider.notifier);
    final (title, subtitle, action) = switch (ref.watch(appUpdateProvider)) {
      UpdateNone() => (null, null, null),
      UpdateFound(:final release) => (
        l10n.updateFound(release.versionName),
        null,
        (l10n.updateDownload, ctl.download),
      ),
      UpdateDownloading(:final release) => (
        l10n.updateDownloading(release.versionName),
        null,
        null,
      ),
      UpdateReady(:final release, :final waiting, :final needsPermission) => (
        l10n.updateReady(release.versionName),
        waiting
            ? l10n.updateWaiting
            : needsPermission
            ? l10n.updatePermission
            : null,
        waiting ? null : (l10n.updateInstall, ctl.install),
      ),
      UpdateInstalling() => (l10n.updateInstalling, null, null),
      UpdateFailed(:final release?) => (l10n.updateFailed, null, (l10n.retry, ctl.download)),
      UpdateFailed() => (null, null, null),
    };
    if (title == null) return const SizedBox.shrink();
    final progress = switch (ref.watch(appUpdateProvider)) {
      UpdateDownloading(:final fraction) => fraction,
      UpdateInstalling() => null,
      _ => -1.0,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.system_update),
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: action == null
                ? null
                : FilledButton.tonal(onPressed: action.$2, child: Text(action.$1)),
          ),
          if (progress == null || progress >= 0) LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}

/// "Check for updates" in About (FR-UPD-001): a user action, the switch is not needed.
class AboutUpdateTile extends ConsumerStatefulWidget {
  const AboutUpdateTile({super.key});

  @override
  ConsumerState<AboutUpdateTile> createState() => _AboutUpdateTileState();
}

class _AboutUpdateTileState extends ConsumerState<AboutUpdateTile> {
  /// The user checked here: "latest version" answers that.
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    if (!selfUpdate) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(appUpdateProvider);
    final checking = state is UpdateNone && state.checking;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: checking
                ? null
                : () {
                    setState(() => _asked = true);
                    unawaited(ref.read(appUpdateProvider.notifier).checkNow());
                  },
            child: Text(checking ? l10n.aboutChecking : l10n.aboutCheckUpdates),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(switch (state) {
              UpdateNone(checking: false) when _asked => l10n.aboutUpToDate,
              UpdateFailed(release: null) => l10n.updateFailed,
              UpdateNone() || UpdateFailed() => '',
              // An update was found: the home screen's card offers it.
              _ => l10n.updateFound(_version(state)),
            }),
          ),
        ],
      ),
    );
  }

  static String _version(AppUpdateState s) => switch (s) {
    UpdateFound(:final release) ||
    UpdateDownloading(:final release) ||
    UpdateReady(:final release) ||
    UpdateInstalling(:final release) => release.versionName,
    _ => '',
  };
}

/// Once after an update: what changed (FR-UPD-005).
Future<void> showWhatsNew(BuildContext context, WidgetRef ref) async {
  final release = await ref.read(appUpdateProvider.notifier).takeWhatsNew();
  if (release == null || !context.mounted) return;
  final l10n = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.whatsNewTitle(release.versionName)),
      content: SingleChildScrollView(
        child: Text(release.notesFor(Localizations.localeOf(context).languageCode)),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close))],
    ),
  );
}

/// After the first saved result (ADR-0027): one question to turn on update checks, asked once.
Future<void> offerUpdateChecks(BuildContext context, WidgetRef ref) async {
  if (!selfUpdate) return;
  final settings = await ref.read(settingsProvider.future);
  if (settings.packUpdateCheck || settings.updateOfferShown || !context.mounted) return;
  await ref.read(settingsProvider.notifier).change((s) => s.copyWith(updateOfferShown: true));
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context);
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.updateOfferTitle),
      content: Text(l10n.updateOfferBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.updateOfferNo)),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.updateOfferYes),
        ),
      ],
    ),
  );
  if (yes ?? false) {
    await ref.read(settingsProvider.notifier).change((s) => s.copyWith(packUpdateCheck: true));
    await ref.read(appUpdateProvider.notifier).autoCheck();
  }
}
