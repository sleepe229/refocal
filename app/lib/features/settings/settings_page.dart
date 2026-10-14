import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';

/// Export format and quality, metadata policy, language (FR-SET-001/002/006, FR-META-003/005).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
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
                onChanged: (f) => f == null ? null : ctl.save(s.copyWith(format: f)),
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
              min: Settings.minQuality.toDouble(),
              max: Settings.maxQuality.toDouble(),
              divisions: Settings.maxQuality - Settings.minQuality,
              label: '${s.quality}',
              onChanged: s.format.hasQuality
                  ? (v) => ctl.save(s.copyWith(quality: v.round()))
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
              onChanged: (v) => ctl.save(s.copyWith(keepGps: v)),
            ),
            SwitchListTile(
              title: Text(l10n.settingsAiMarker),
              subtitle: Text(l10n.settingsAiMarkerSub),
              value: s.aiMarker,
              onChanged: (v) async {
                if (!v && !await _confirmMarkerOff(context)) return;
                await ctl.save(s.copyWith(aiMarker: v));
              },
            ),
            const Divider(),
            ListTile(
              title: Text(l10n.settingsLanguage),
              trailing: DropdownButton<String?>(
                value: s.languageCode,
                onChanged: (code) => ctl.save(s.copyWith(languageCode: () => code)),
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
