import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/settings.dart';

/// Metadata policy of saved photos (FR-SET-002, FR-META-003/005).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) => ListView(
          children: [
            const ListTile(
              title: Text('Saved photos'),
              subtitle: Text(
                'Date, camera and color profile are kept. Camera serial numbers and the '
                'maker notes are always removed.',
              ),
            ),
            SwitchListTile(
              title: const Text('Keep location'),
              subtitle: const Text('Off: GPS coordinates are removed from the result.'),
              value: s.keepGps,
              onChanged: (v) => ctl.save(s.copyWith(keepGps: v)),
            ),
            SwitchListTile(
              title: const Text('Mark as AI-enhanced'),
              subtitle: const Text(
                'Writes the IPTC "trained algorithmic media" tag, which other apps can show.',
              ),
              value: s.aiMarker,
              onChanged: (v) async {
                if (!v && !await _confirmMarkerOff(context)) return;
                await ctl.save(s.copyWith(aiMarker: v));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmMarkerOff(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Turn off the AI marker?'),
          content: const Text(
            'Enhanced photos contain detail the AI invented. Without the marker, people who '
            'see the photo cannot tell it was changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Turn off'),
            ),
          ],
        ),
      ) ??
      false;
}
