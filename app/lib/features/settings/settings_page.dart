import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/engine.dart';
import '../../bootstrap/history.dart';
import '../../bootstrap/settings.dart';
import '../../bootstrap/tier.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';
import '../../ui_kit/errors.dart';

/// Export format and quality, location, history and presets, storage, language
/// (FR-SET-001/002/004/006, FR-META-003, FR-HIST-005, FR-PRE-002); the rest in Advanced.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    // The control shows the stored value; a failed write leaves it and says why.
    Future<bool> change(Settings Function(Settings) f) async {
      try {
        await ref.read(settingsProvider.notifier).change(f);
        return true;
      } on Exception catch (e, stack) {
        showError(messenger, l10n, 'save setting', e, stack, l10n.settingsSaveFailed);
        return false;
      }
    }

    final heic = ref.watch(heicSupportedProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        // 06 §1.1: what a person changes; the rest is in Advanced.
        data: (s) => ListView(
          children: [
            SettingsSection(
              title: l10n.settingsSavedPhotos,
              children: [
                ListTile(
                  title: Text(l10n.settingsFormat),
                  // Under the title, full width: at 200% text a trailing menu leaves no room for
                  // the title (A11Y-GEN-004).
                  subtitle: DropdownButton<ExportFormat>(
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    // A HEIC setting restored on a phone without an encoder is saved as JPEG.
                    value: s.format == ExportFormat.heic && !heic ? ExportFormat.jpeg : s.format,
                    onChanged: (f) => f == null ? null : change((c) => c.copyWith(format: f)),
                    items: [
                      for (final f in availableFormats(heic: heic))
                        DropdownMenuItem(value: f, child: Text(formatLabel(l10n, f))),
                    ],
                  ),
                ),
                if (s.format.hasQuality)
                  ListTile(
                    title: Text(l10n.settingsQuality),
                    trailing: Text('${s.quality}'),
                    subtitle: Slider(
                      value: s.quality.toDouble(),
                      min: ExportFormat.minQuality.toDouble(),
                      max: ExportFormat.maxQuality.toDouble(),
                      divisions: ExportFormat.maxQuality - ExportFormat.minQuality,
                      label: '${s.quality}',
                      onChanged: (v) => change((c) => c.copyWith(quality: v.round())),
                    ),
                  ),
                SwitchListTile(
                  title: Text(l10n.settingsKeepLocation),
                  value: s.keepGps,
                  onChanged: (v) => change((c) => c.copyWith(keepGps: v)),
                ),
              ],
            ),
            SettingsSection(
              children: [
                SwitchListTile(
                  title: Text(l10n.settingsKeepHistory),
                  subtitle: Text(l10n.settingsKeepHistorySub),
                  value: s.historyEnabled,
                  onChanged: (v) async {
                    if (v) {
                      await change((c) => c.copyWith(historyEnabled: true));
                      return;
                    }
                    if (!await _confirmHistoryOff(context)) return;
                    // Recording stops first, so nothing is added while the history is cleared.
                    if (!await change((c) => c.copyWith(historyEnabled: false))) return;
                    try {
                      await (await ref.read(historyStoreProvider.future)).clear();
                    } on Exception catch (e, stack) {
                      showError(
                        messenger,
                        l10n,
                        'clear history',
                        e,
                        stack,
                        l10n.historyDeleteFailed,
                      );
                    }
                  },
                ),
                _Link(l10n.presetsTitle, '/presets'),
                _Link(l10n.settingsStorage, '/storage'),
              ],
            ),
            SettingsSection(
              children: [
                ListTile(
                  title: Text(l10n.settingsLanguage),
                  subtitle: DropdownButton<String?>(
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    value: s.languageCode,
                    onChanged: (code) => change((c) => c.copyWith(languageCode: () => code)),
                    items: [
                      DropdownMenuItem(child: Text(l10n.languageSystem)),
                      for (final l in AppLocalizations.supportedLocales)
                        DropdownMenuItem(
                          value: l.languageCode,
                          child: Text(lookupAppLocalizations(l).languageName),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              children: [
                _Link(l10n.settingsAdvanced, '/settings/advanced'),
                _Link(l10n.aboutTitle, '/about'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmHistoryOff(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.historyOffTitle),
            content: Text(l10n.historyOffBody),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.historyOffConfirm),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/// What few people change (06 §1.1): the AI marker, the queue, models and their updates, the
/// device class, the introduction.
class AdvancedSettingsPage extends ConsumerWidget {
  const AdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    Future<bool> change(Settings Function(Settings) f) async {
      try {
        await ref.read(settingsProvider.notifier).change(f);
        return true;
      } on Exception catch (e, stack) {
        showError(messenger, l10n, 'save setting', e, stack, l10n.settingsSaveFailed);
        return false;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAdvanced)),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) => ListView(
          children: [
            SettingsSection(
              title: l10n.settingsMetadata,
              footer: l10n.settingsMetadataBody,
              children: [
                SwitchListTile(
                  title: Text(l10n.settingsAiMarker),
                  subtitle: Text(l10n.settingsAiMarkerSub),
                  value: s.aiMarker,
                  onChanged: (v) async {
                    if (!v && !await _confirmMarkerOff(context)) return;
                    await change((c) => c.copyWith(aiMarker: v));
                  },
                ),
              ],
            ),
            SettingsSection(
              children: [
                SwitchListTile(
                  title: Text(l10n.settingsBatchAutosave),
                  subtitle: Text(l10n.settingsBatchAutosaveHint),
                  value: s.batchAutosave,
                  onChanged: (v) => change((c) => c.copyWith(batchAutosave: v)),
                ),
              ],
            ),
            SettingsSection(
              children: [
                _Link(l10n.settingsModels, '/models'),
                SwitchListTile(
                  title: Text(l10n.settingsPackUpdates),
                  subtitle: Text(l10n.settingsPackUpdatesHint),
                  value: s.packUpdateCheck,
                  onChanged: (v) => change((c) => c.copyWith(packUpdateCheck: v)),
                ),
                _TierTile(chosen: s.tierOverride, change: change),
              ],
            ),
            SettingsSection(children: [_Link(l10n.settingsShowIntro, '/onboarding')]),
          ],
        ),
      ),
    );
  }
}

/// A row that opens another screen.
class _Link extends StatelessWidget {
  const _Link(this.title, this.route);
  final String title, route;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.push(route),
  );
}

/// A group of rows on a tonal card, with an optional title above and a note below (iOS-like
/// grouped settings, 06 §7).
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, this.footer, required this.children});
  final String? title, footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Text(title!, style: theme.textTheme.titleSmall),
            ),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(footer!, style: muted),
            ),
        ],
      ),
    );
  }
}

/// FR-SET-003: the device tier the benchmark found, and the user's override (ADR-0017).
class _TierTile extends ConsumerWidget {
  const _TierTile({required this.chosen, required this.change});
  final String? chosen;
  final Future<bool> Function(Settings Function(Settings)) change;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = ref.watch(tierProvider);
    final b = t.value?.benchmark;
    final found = switch (t) {
      AsyncData(:final value) when b != null => l10n.tierMeasured(
        value.benchmark!.tier.label,
        b.gpu ? l10n.tierGpu : l10n.tierCpu,
        b.tile128Ms.round(),
      ),
      AsyncData() => l10n.tierUnknown,
      AsyncError() => l10n.tierUnknown,
      _ => l10n.tierMeasuring,
    };
    return ListTile(
      title: Text(l10n.tierTitle),
      subtitle: Text(found),
      isThreeLine: true,
      trailing: DropdownButton<String?>(
        value: chosen,
        onChanged: (v) => change((c) => c.copyWith(tierOverride: () => v)),
        items: [
          DropdownMenuItem(child: Text(l10n.tierAuto)),
          for (final x in DeviceTier.values) DropdownMenuItem(value: x.label, child: Text(x.label)),
        ],
      ),
    );
  }
}

/// FR-META-005: turning the AI marker off is confirmed (15 §2).
Future<bool> _confirmMarkerOff(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.markerOffTitle),
          content: Text(l10n.markerOffBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.markerKeep),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.markerTurnOff),
            ),
          ],
        ),
      ) ??
      false;
}
