import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../bootstrap/queue.dart';
import '../../bootstrap/storage.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/errors.dart';

/// Storage (FR-SET-004, PRIV-DATA-003): size per category, clear each.
class StoragePage extends ConsumerWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final usage = ref.watch(storageUsageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storageTitle)),
      body: usage.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.storageMeasureFailed(errorReason(l10n, e)))),
        data: (u) => ListView(
          children: [
            ListTile(
              title: Text(
                l10n.storageTotal(formatBytes(context, u.total)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final c in StorageCategory.values)
              ListTile(
                title: Text(_title(l10n, c)),
                subtitle: Text('${formatBytes(context, u[c])} · ${_hint(l10n, c)}'),
                isThreeLine: true,
                trailing: StorageManager.clearable(c)
                    ? TextButton(
                        onPressed: u[c] == 0 ? null : () => _clear(context, ref, c),
                        child: Text(l10n.storageClear),
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref, StorageCategory c) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.storageClearTitle(_title(l10n, c))),
        content: Text(_consequence(l10n, c)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.storageClear)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (await ref.read(storageManagerProvider.future)).clear(c);
      ref.invalidate(jobListProvider);
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'clear ${c.name}', e, stack, l10n.storageClearFailed);
    }
    ref.invalidate(storageUsageProvider);
  }

  static String _title(AppLocalizations l10n, StorageCategory c) => switch (c) {
    StorageCategory.copies => l10n.storageCopies,
    StorageCategory.unfinished => l10n.storageUnfinished,
    StorageCategory.history => l10n.historyTitle,
    StorageCategory.cache => l10n.storageCache,
    StorageCategory.logs => l10n.storageLogs,
    StorageCategory.models => l10n.storageModels,
  };

  static String _hint(AppLocalizations l10n, StorageCategory c) => switch (c) {
    StorageCategory.copies => l10n.storageCopiesHint,
    StorageCategory.unfinished => l10n.storageUnfinishedHint,
    StorageCategory.history => l10n.storageHistoryHint,
    StorageCategory.cache => l10n.storageCacheHint,
    StorageCategory.logs => l10n.storageLogsHint,
    StorageCategory.models => l10n.storageModelsHint,
  };

  static String _consequence(AppLocalizations l10n, StorageCategory c) => switch (c) {
    StorageCategory.copies => l10n.storageCopiesClear,
    StorageCategory.unfinished => l10n.storageUnfinishedClear,
    StorageCategory.history => l10n.storageHistoryClear,
    StorageCategory.cache || StorageCategory.logs || StorageCategory.models => l10n.storageNoUndo,
  };
}

/// "12.3 MB" in the app's locale (decimal megabytes, as the system's storage settings).
String formatBytes(BuildContext context, int bytes) {
  final l10n = AppLocalizations.of(context);
  final f = NumberFormat.decimalPatternDigits(
    locale: Localizations.localeOf(context).toLanguageTag(),
    decimalDigits: 1,
  );
  if (bytes < 1000 * 1000) return l10n.sizeKb(f.format(bytes / 1000));
  if (bytes < 1000 * 1000 * 1000) return l10n.sizeMb(f.format(bytes / 1e6));
  return l10n.sizeGb(f.format(bytes / 1e9));
}
