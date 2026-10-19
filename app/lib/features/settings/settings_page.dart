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

/// Export format and quality, metadata policy, history and presets, language (FR-SET-001/002/006,
/// FR-META-003/005, FR-HIST-005, FR-PRE-002).
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

    final header = Theme.of(context).textTheme.titleSmall;
    final heic = ref.watch(heicSupportedProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) => ListView(
          children: [
            ListTile(title: Text(l10n.settingsSavedPhotos, style: header)),
            ListTile(
              title: Text(l10n.settingsFormat),
              // Under the title, full width: at 200% text a trailing menu leaves no room for
              // the title (A11Y-GEN-004).
              subtitle: DropdownButton<ExportFormat>(
                isExpanded: true,
                // A HEIC setting restored on a phone without an encoder is saved as JPEG.
                value: s.format == ExportFormat.heic && !heic ? ExportFormat.jpeg : s.format,
                onChanged: (f) => f == null ? null : change((c) => c.copyWith(format: f)),
                items: [
                  for (final f in availableFormats(heic: heic))
                    DropdownMenuItem(value: f, child: Text(formatLabel(l10n, f))),
                ],
              ),
            ),
            ListTile(
              enabled: s.format.hasQuality,
              title: Text(l10n.settingsQuality),
              subtitle: Text(l10n.settingsQualityHint),
              trailing: Text('${s.quality}'),
            ),
            Slider(
              value: s.quality.toDouble(),
              min: ExportFormat.minQuality.toDouble(),
              max: ExportFormat.maxQuality.toDouble(),
              divisions: ExportFormat.maxQuality - ExportFormat.minQuality,
              label: '${s.quality}',
              onChanged: s.format.hasQuality
                  ? (v) => change((c) => c.copyWith(quality: v.round()))
                  : null,
            ),
            const Divider(),
            ListTile(
              title: Text(l10n.settingsMetadata, style: header),
              subtitle: Text(l10n.settingsMetadataBody),
            ),
            SwitchListTile(
              title: Text(l10n.settingsKeepLocation),
              subtitle: Text(l10n.settingsKeepLocationSub),
              value: s.keepGps,
              onChanged: (v) => change((c) => c.copyWith(keepGps: v)),
            ),
            SwitchListTile(
              title: Text(l10n.settingsAiMarker),
              subtitle: Text(l10n.settingsAiMarkerSub),
              value: s.aiMarker,
              onChanged: (v) async {
                if (!v && !await _confirmMarkerOff(context)) return;
                await change((c) => c.copyWith(aiMarker: v));
              },
            ),
            const Divider(),
            ListTile(title: Text(l10n.historyTitle, style: header)),
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
                  showError(messenger, l10n, 'clear history', e, stack, l10n.historyDeleteFailed);
                }
              },
            ),
            SwitchListTile(
              title: Text(l10n.settingsBatchAutosave),
              subtitle: Text(l10n.settingsBatchAutosaveHint),
              value: s.batchAutosave,
              onChanged: (v) => change((c) => c.copyWith(batchAutosave: v)),
            ),
            ListTile(title: Text(l10n.historyTitle), onTap: () => context.push('/history')),
            ListTile(title: Text(l10n.presetsTitle), onTap: () => context.push('/presets')),
            ListTile(title: Text(l10n.settingsModels), onTap: () => context.push('/models')),
            SwitchListTile(
              title: Text(l10n.settingsPackUpdates),
              subtitle: Text(l10n.settingsPackUpdatesHint),
              value: s.packUpdateCheck,
              onChanged: (v) => change((c) => c.copyWith(packUpdateCheck: v)),
            ),
            _TierTile(chosen: s.tierOverride, change: change),
            ListTile(title: Text(l10n.settingsStorage), onTap: () => context.push('/storage')),
            const Divider(),
            ListTile(
              title: Text(l10n.settingsLanguage),
              subtitle: DropdownButton<String?>(
                isExpanded: true,
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
            ListTile(title: Text(l10n.settingsShowIntro), onTap: () => context.push('/onboarding')),
            ListTile(title: Text(l10n.aboutTitle), onTap: () => context.push('/about')),
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
