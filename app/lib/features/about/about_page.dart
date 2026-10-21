import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../update/update_ui.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/models.dart';
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

/// Credited packs (CC-BY, ADR-0026) already in the license registry.
final _credited = <String>{};

/// Adds the credit of every installed credited pack to Flutter's license registry, once each
/// (ADR-0026: the author, the link and the licence, next to the app's own licences).
Future<void> registerPackCredits(WidgetRef ref) async {
  final manager = await ref.read(modelManagerProvider.future);
  final manifest = await manager.repo.current();
  if (manifest == null) return;
  final installed = {for (final i in await manager.repo.installed()) i.id};
  for (final p in manifest.packs) {
    final credit = p.license.attribution;
    if (credit == null || !installed.contains(p.id) || !_credited.add(p.id)) continue;
    final title = p.titleFor('en');
    LicenseRegistry.addLicense(
      () => Stream.value(
        LicenseEntryWithLineBreaks(
          ['Model: $title'],
          '$title by ${credit.author}\n${credit.url}\n\n'
          'Licensed under ${p.license.spdx}: ${p.license.url}',
        ),
      ),
    );
  }
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
            onPressed: () async {
              await registerPackCredits(ref);
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: 'Refocal',
                applicationVersion: version,
                applicationLegalese: '© 2026 The Refocal Authors · Apache-2.0',
              );
            },
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
