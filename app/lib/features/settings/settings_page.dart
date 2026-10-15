import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/history.dart';
import '../../bootstrap/settings.dart';
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
              trailing: DropdownButton<ExportFormat>(
                value: s.format,
                onChanged: (f) => f == null ? null : change((c) => c.copyWith(format: f)),
                items: [
                  for (final f in ExportFormat.values)
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
            ListTile(title: Text(l10n.historyTitle), onTap: () => context.push('/history')),
            ListTile(title: Text(l10n.presetsTitle), onTap: () => context.push('/presets')),
            const Divider(),
            ListTile(
              title: Text(l10n.settingsLanguage),
              trailing: DropdownButton<String?>(
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
