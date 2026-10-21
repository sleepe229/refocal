import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../update/update_ui.dart';
import '../../bootstrap/engine.dart';
import '../../l10n/app_localizations.dart';

const sourceUrl = 'https://github.com/sleepe229/refocal';
const privacyUrl = 'https://sleepe229.github.io/refocal/privacy';

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
    final version = ref.watch(engineProvider).value?.version ?? '…';
    final t = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Refocal $version', style: t.titleLarge),
          const SizedBox(height: 16),
          const AboutUpdateTile(),
          Text(l10n.aboutAlpha),
          const SizedBox(height: 16),
          Text(l10n.aboutPrivacy),
          const SizedBox(height: 8),
          SelectableText(l10n.aboutPrivacyPolicy(privacyUrl)),
          const SizedBox(height: 16),
          Text(l10n.aboutAiWarning),
          const SizedBox(height: 24),
          Text(l10n.aboutCredits, style: t.titleMedium),
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
          SelectableText(l10n.aboutSource(sourceUrl)),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Refocal',
              applicationVersion: version,
              applicationLegalese: '© 2026 The Refocal Authors · Apache-2.0',
            ),
            child: Text(l10n.aboutLicenses),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.reportEntry),
            subtitle: Text(l10n.reportEntrySub),
            onTap: () => context.push('/report'),
          ),
        ],
      ),
    );
  }
}
