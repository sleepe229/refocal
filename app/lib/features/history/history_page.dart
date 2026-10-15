import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/history.dart';
import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';
import '../../ui_kit/errors.dart';

/// Saved results with their recipes (FR-HIST-001, 06 §2 `/history`).
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(historyProvider);
    final store = ref.watch(historyStoreProvider).value;
    final enabled = ref.watch(settingsProvider).value?.historyEnabled ?? true;
    final entries = history.value ?? const <HistoryEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          IconButton(
            tooltip: l10n.historyDeleteAll,
            onPressed: entries.isEmpty ? null : () => _deleteAll(context, ref),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(padding: const EdgeInsets.all(24), child: Text('$e')),
        ),
        data: (entries) => ListView(
          children: [
            if (!enabled)
              ListTile(leading: const Icon(Icons.history_toggle_off), title: Text(l10n.historyOff)),
            if (entries.isEmpty && enabled)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.historyEmpty, textAlign: TextAlign.center),
              ),
            if (store != null)
              for (final e in entries)
                ListTile(
                  leading: HistoryPreview(file: File(store.absolute(e.previewPath)), size: 56),
                  title: Text(formatDateTime(context, e.createdAt)),
                  subtitle: Text(recipeLabel(l10n, e.recipe)),
                  onTap: () => context.push('/history/entry', extra: e.id),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.historyDeleteAllTitle),
        content: Text(l10n.historyDeleteAllBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.historyDeleteAll),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (await ref.read(historyStoreProvider.future)).clear();
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'clear history', e, stack, l10n.historyDeleteFailed);
    }
  }
}

/// "14 Oct 2026, 18:30" in the app's language.
String formatDateTime(BuildContext context, DateTime t) {
  final m = MaterialLocalizations.of(context);
  return '${m.formatMediumDate(t)}, '
      '${m.formatTimeOfDay(TimeOfDay.fromDateTime(t), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

/// The <= 512 px preview of an entry (PRIV-DATA-002).
class HistoryPreview extends StatelessWidget {
  const HistoryPreview({super.key, required this.file, required this.size});
  final File file;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Image(
      image: ResizeImage(FileImage(file), width: (size * 2).round(), policy: ResizeImagePolicy.fit),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          SizedBox(width: size, height: size, child: const Icon(Icons.image)),
    ),
  );
}
