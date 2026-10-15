import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/queue.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/errors.dart';
import '../../ui_kit/labels.dart';
import '../editor/editor_page.dart';

/// The batch queue (06 §1 `/queue`, §3.4): progress, order, removal, pause/continue and the
/// report "done N, failed M" (FR-BATCH-001/003/008).
class QueuePage extends ConsumerStatefulWidget {
  const QueuePage({super.key});

  @override
  ConsumerState<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends ConsumerState<QueuePage> {
  bool _onlyErrors = false;

  Future<void> _run(Future<void> Function(QueueService) f, String what) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await f(await ref.read(queueServiceProvider.future));
    } on Exception catch (e, stack) {
      showError(messenger, l10n, what, e, stack, l10n.queueActionFailed);
    }
  }

  /// A user action: Android may start the foreground service now (ADR-0019).
  Future<void> _start() async {
    final service = await ref.read(queueServiceProvider.future);
    unawaited(service.start());
  }

  Future<void> _open(QueueItem item, String supportDir, String jobsDir) async {
    await context.push(
      '/editor',
      extra: EditorArgs(
        '$supportDir/${item.inputPath}',
        jobDir: '$jobsDir/${item.jobId}',
        finished: true,
      ),
    );
    await _run((s) => s.refresh(item), 'queue refresh'); // saved from the editor
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(queueItemsProvider).value ?? const <QueueItem>[];
    final status = ref.watch(queueStatusProvider).value ?? const QueueStatus();
    final engine = ref.watch(startupProvider).value;
    final failed = items.where((i) => i.state == QueueState.failed).length;
    final finished = items
        .where((i) => i.state == QueueState.done || i.state == QueueState.saved)
        .length;
    final pending = items.where((i) => i.pending).length;
    final shown = _onlyErrors ? items.where((i) => i.state == QueueState.failed).toList() : items;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.queueTitle),
        actions: [
          IconButton(
            tooltip: l10n.queueClearFinished,
            onPressed: finished + failed == 0
                ? null
                : () => _run((s) => s.clearFinished(), 'clear finished'),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: engine == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.queueEmpty, textAlign: TextAlign.center),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.queueReport(finished, failed),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (failed > 0)
                        FilterChip(
                          label: Text(l10n.queueShowErrors),
                          selected: _onlyErrors,
                          onSelected: (v) => setState(() => _onlyErrors = v),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: status.running
                      ? OutlinedButton.icon(
                          onPressed: () => _run((s) async => s.pause(), 'pause queue'),
                          icon: const Icon(Icons.pause),
                          label: Text(l10n.queuePause),
                        )
                      : FilledButton.icon(
                          onPressed: pending == 0 ? null : _start,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.queueStart),
                        ),
                ),
                if (!_onlyErrors && items.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.queueReorderHint,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: !_onlyErrors,
                    itemCount: shown.length,
                    onReorderItem: (from, to) =>
                        _run((s) => s.repo.move(shown[from].id, to), 'reorder queue'),
                    itemBuilder: (context, i) {
                      final item = shown[i];
                      final running = item.id == status.currentId;
                      return _QueueTile(
                        key: ValueKey(item.id),
                        item: item,
                        running: running,
                        progress: running ? status.progress : item.progress,
                        supportDir: engine.dirs.support,
                        onOpen: item.state == QueueState.done
                            ? () => _open(item, engine.dirs.support, engine.jobsDir)
                            : null,
                        onRemove: running
                            ? null
                            : () => _run((s) => s.remove([item.id]), 'remove queue job'),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    super.key,
    required this.item,
    required this.running,
    required this.progress,
    required this.supportDir,
    required this.onOpen,
    required this.onRemove,
  });

  final QueueItem item;
  final bool running;
  final double progress;
  final String supportDir;
  final VoidCallback? onOpen, onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = (progress * 100).round();
    final subtitle = switch (item.state) {
      _ when running => l10n.queueStateRunning(percent),
      QueueState.queued => l10n.queueStateQueued,
      QueueState.running || QueueState.paused => l10n.queueStatePaused(percent),
      QueueState.done => l10n.queueStateDone,
      QueueState.saved => l10n.queueStateSaved,
      QueueState.failed => l10n.queueStateFailed(failureReason(l10n, item.errorCode)),
    };
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image(
          image: ResizeImage(
            FileImage(File('$supportDir/${item.inputPath}')),
            width: 96,
            policy: ResizeImagePolicy.fit,
          ),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const SizedBox(width: 48, height: 48, child: Icon(Icons.image)),
        ),
      ),
      title: Text(recipeLabel(l10n, item.recipe)),
      subtitle: running
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitle),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: progress),
              ],
            )
          : Text(subtitle),
      onTap: onOpen,
      trailing: IconButton(
        tooltip: l10n.deleteTooltip,
        icon: const Icon(Icons.delete_outline),
        onPressed: onRemove,
      ),
    );
  }
}
