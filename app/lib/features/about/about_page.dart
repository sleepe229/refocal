import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/engine.dart';
import '../../version.dart';

const sourceUrl = 'https://github.com/sleepe229/refocal';

/// Adds the licenses of the native core and the bundled model (assets/licenses/native.json,
/// tools/licenses/collect.sh) to Flutter's license registry.
void registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    final raw = await rootBundle.loadString('assets/licenses/native.json');
    for (final e in jsonDecode(raw) as List) {
      final m = e as Map<String, dynamic>;
      yield LicenseEntryWithLineBreaks([m['package'] as String], m['text'] as String);
    }
  });
}

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(engineProvider).value?.native.version ?? '…';
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Refocal $appVersion', style: t.titleLarge),
          Text('Native core $core', style: t.bodySmall),
          const SizedBox(height: 16),
          const Text(
            'Early alpha. Expect rough edges: Android only, JPEG input only, keep the app '
            'open while a photo is processed.',
          ),
          const SizedBox(height: 16),
          const Text(
            'All processing happens on this device. Refocal has no accounts, no ads and no '
            'telemetry; the network is used only to download optional models when you ask.',
          ),
          const SizedBox(height: 16),
          const Text(
            'AI enhancement adds plausible detail that was not in the original photo. Do not '
            'use results as evidence of what a scene or person looked like.',
          ),
          const SizedBox(height: 24),
          Text('Credits', style: t.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Upscaling model: Real-ESRGAN realesr-general-x4v3, © 2021 Xintao Wang, BSD-3-Clause.',
          ),
          const Text('Inference: ncnn (Tencent), BSD-3-Clause.'),
          const Text(
            'This software is based in part on the work of the Independent JPEG Group '
            '(libjpeg-turbo).',
          ),
          const SizedBox(height: 24),
          const SelectableText('Source code (Apache-2.0): $sourceUrl'),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Refocal',
              applicationVersion: appVersion,
              applicationLegalese: '© 2026 The Refocal Authors · Apache-2.0',
            ),
            child: const Text('Open-source licenses'),
          ),
        ],
      ),
    );
  }
}
