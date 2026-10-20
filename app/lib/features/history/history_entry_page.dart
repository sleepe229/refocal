import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/files.dart';
import '../../bootstrap/models.dart';
import '../../bootstrap/history.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';
import '../../ui_kit/errors.dart';
import '../editor/editor_page.dart';
import '../models/pack_offer.dart';
import 'history_page.dart';

/// One history entry: preview, recipe, sizes; process again (FR-HIST-003), delete (FR-HIST-004).
class HistoryEntryPage extends ConsumerWidget {
  const HistoryEntryPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(historyStoreProvider).value;
    final entry = ref.watch(historyEntryProvider(id));
    final e = entry.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? l10n.historyTitle : formatDateTime(context, e.createdAt)),
      ),
      body: store == null || !entry.hasValue
          ? const Center(child: CircularProgressIndicator())
          : e == null
          ? Center(child: Text(l10n.historyEntryGone))
          : _details(context, ref, l10n, store, e),
    );
  }

  Widget _details(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    HistoryStore store,
    HistoryEntry e,
  ) {
    final r = e.recipe;
    final out = r.output!;
    final input = store.absolute(e.inputPath);
    final inputExists = ref.watch(fileExistsProvider(input)).value ?? false;
    // 06 §3.3: a model the device no longer has is offered here, the download shown below.
    final srMissing = !ref.watch(availableModelsProvider).contains(r.srModel);
    final download = packsProgress(ref, [r.srModel]);
    final mono = Theme.of(context).textTheme.bodySmall;
    Widget row(String label, String value) =>
        ListTile(dense: true, title: Text(label), trailing: Text(value));
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(store.absolute(e.previewPath)),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const SizedBox(height: 200, child: Center(child: Icon(Icons.image, size: 64))),
            ),
          ),
        ),
        const SizedBox(height: 8),
        row(l10n.historyScale, scaleLabel(l10n, r.scale, fast2: r.fast2)),
        row(l10n.strength, l10n.strengthValue((r.strength * 100).round())),
        if (r.look != null) row(l10n.lookTitle, lookLabel(l10n, r.look)),
        row(
          l10n.settingsFormat,
          out.quality == null
              ? formatLabel(l10n, out.format)
              : '${formatLabel(l10n, out.format)} ${out.quality}',
        ),
        // FR-CMP-007 (06 §1.1): sizes, models, processor and time on request.
        ExpansionTile(
          title: Text(l10n.resultDetails),
          children: [
            row(l10n.historyOriginalSize, l10n.sizePx(e.sourceWidth, e.sourceHeight)),
            row(l10n.historyResultSize, l10n.sizePx(e.width, e.height)),
            row(l10n.historyModel, e.modelIds.join(', ')),
            row(l10n.historyBackend, e.backend),
            if (e.duration case final d?)
              row(l10n.historyDuration, l10n.historySeconds(d.inSeconds)),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: inputExists && download == null
                    ? () async {
                        if (srMissing) {
                          final title = l10n.historyProcessAgain;
                          if (!await offerPacks(context, ref, [r.srModel], title: title)) return;
                        }
                        if (!context.mounted) return;
                        await context.push(
                          '/editor',
                          extra: EditorArgs(input, recipe: r.copyWith(output: () => null)),
                        );
                      }
                    : null,
                child: Text(l10n.historyProcessAgain),
              ),
              if (download != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: download),
              ],
              if (!inputExists) ...[
                const SizedBox(height: 8),
                Text(l10n.historyOriginalGone, textAlign: TextAlign.center, style: mono),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _delete(context, ref, l10n),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.historyDeleteEntry),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await (await ref.read(historyStoreProvider.future)).remove(id);
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'delete history entry', e, stack, l10n.historyDeleteFailed);
    }
    router.pop();
  }
}
