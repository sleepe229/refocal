import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:refocal_core/refocal_core.dart';
import 'package:refocal_platform/refocal_platform.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/history.dart';
import '../../bootstrap/job_store.dart';
import '../../bootstrap/models.dart';
import '../../bootstrap/processing.dart';
import '../../bootstrap/queue.dart';
import '../../bootstrap/tier.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/errors.dart';
import '../../ui_kit/labels.dart';
import '../editor/editor_page.dart';
import '../history/history_page.dart';
import '../queue/batch_sheet.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _picking = false;
  bool _editorOpen = false;
  StreamSubscription<void>? _shares;

  @override
  void initState() {
    super.initState();
    _shares = ref.read(sharedImageEventsProvider).listen((_) => _openShared());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openShared();
      // ADR-0017: benchmark (or its cached result) in the background once the app is up.
      ref.read(tierProvider.future).ignore();
    });
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  Future<void> _openEditor(EditorArgs args) async {
    _editorOpen = true;
    try {
      await context.push('/editor', extra: args);
    } finally {
      _editorOpen = false;
    }
    ref.invalidate(jobListProvider); // the editor may have finished, paused or cleaned up jobs
    await _openShared(); // shared while the editor was open
  }

  /// Photos shared to the app (FR-SHARE-001): one opens the editor, several the queue. One
  /// editor at a time: a share that arrives while one is open waits on the platform side.
  Future<void> _openShared() async {
    if (_editorOpen || _picking || !mounted) return;
    await _take(() async {
      final engine = await ref.read(startupProvider.future);
      if (!engine.modelReady) return null;
      return ref.read(platformApiProvider).takeSharedImages(engine.inboxDir);
    });
  }

  Future<void> _pick({required bool several}) => _take(() async {
    final engine = await ref.read(startupProvider.future);
    return ref.read(platformApiProvider).pickImages(engine.inboxDir, several ? maxBatch : 1);
  });

  /// One batch at most (the system picker allows up to 100 on most devices).
  static const maxBatch = 100;

  /// Copies come from the startup provider's engine: the sweep of inbox/ has run before.
  Future<void> _take(Future<PickedImages?> Function() take) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _picking = true);
    PickedImages? picked;
    try {
      picked = await take();
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'open photo', e, stack, l10n.homeOpenFailed);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (picked == null) return;
    if (picked.failed > 0) {
      final reason = picked.failure == 'limit' ? l10n.failLimit : l10n.errorStorage;
      AppLog.warn('pick: ${picked.failed} not copied (${picked.failure})');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            picked.images.isEmpty
                ? l10n.homeOpenFailed(reason)
                : l10n.pickPartial(picked.failed, reason),
          ),
        ),
      );
    }
    final paths = [for (final i in picked.images) i.path];
    if (!mounted || paths.isEmpty) return;
    if (paths.length == 1) {
      await _openEditor(EditorArgs(paths.single));
    } else {
      await _enqueue(paths);
    }
  }

  /// Batch sheet → queue (06 §3.4); dismissed: the copies are deleted again.
  Future<void> _enqueue(List<String> paths) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final recipe = await showBatchSheet(context, paths.length);
    final service = await ref.read(queueServiceProvider.future);
    if (recipe == null) {
      // Not deleted outright: with FR-IMP-004 a copy may be one a paused job or the queue has.
      final jobs = await ref.read(jobStoreProvider.future);
      for (final p in paths) {
        try {
          await jobs.releaseInput(p);
        } on FileSystemException catch (e) {
          AppLog.warn('release copy: ${e.message}'); // the startup sweep removes it
        }
      }
      return;
    }
    try {
      await service.enqueue(paths, recipe);
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'enqueue', e, stack, l10n.queueActionFailed);
      return;
    }
    unawaited(service.start()); // a user action: the foreground service may start (ADR-0019)
    if (mounted) await context.push('/queue');
  }

  /// Jobs deleted from the list, hidden while their Undo is on screen (06 §1 (8)).
  final _hidden = <String>{};

  /// Hides [j] at once; its files go when the snack bar does, unless Undo was tapped. A
  /// process killed meanwhile keeps the job: the list shows it again.
  void _discard(JobEntry j) {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final store = ref.read(startupProvider.future).then((_) => ref.read(jobStoreProvider.future));
    setState(() => _hidden.add(j.dir));
    messenger.hideCurrentSnackBar();
    final bar = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.jobDeleted),
        persist: false,
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            if (mounted) setState(() => _hidden.remove(j.dir));
          },
        ),
      ),
    );
    bar.closed.then((reason) async {
      if (reason == SnackBarClosedReason.action) return;
      try {
        await (await store).discard(j.dir);
      } on FileSystemException catch (e, stack) {
        showError(messenger, l10n, 'discard job', e, stack, l10n.historyDeleteFailed);
      }
      if (!mounted) return;
      _hidden.remove(j.dir);
      ref.invalidate(jobListProvider);
    });
  }

  /// FR-MODEL-008: updates found by the opt-in check (FR-SET-005).
  Widget? _packUpdates(AppLocalizations l10n) {
    final n = ref.watch(packUpdatesProvider).value?.length ?? 0;
    if (n == 0) return null;
    return Card(
      margin: const EdgeInsets.only(bottom: 24),
      child: ListTile(
        leading: const Icon(Icons.system_update_alt),
        title: Text(l10n.packUpdatesAvailable(n)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/models'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final engine = ref.watch(startupProvider);
    final queued = ref.watch(queueItemsProvider).value?.length ?? 0;
    final jobs = [
      for (final j in ref.watch(jobListProvider).value ?? const <JobEntry>[])
        if (!_hidden.contains(j.dir)) j,
    ];
    final empty = jobs.isEmpty && queued == 0 && (ref.watch(historyProvider).value ?? []).isEmpty;
    final ready = engine.value?.modelReady ?? false;
    final title = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: engine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.homeCoreUnavailable(errorReason(l10n, e))),
          ),
        ),
        // 06 §3.1: what the user made and left, then the photo picker below.
        data: (e) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            ?_packUpdates(l10n),
            if (!e.modelReady)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.homeModelMissing,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            if (queued > 0)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_outlined),
                title: Text(l10n.homeQueue(queued)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/queue'),
              ),
            if (jobs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(l10n.homeNotFinished, style: title),
              ),
              for (final j in jobs) _JobTile(job: j, onOpen: _openEditor, onDiscard: _discard),
              const SizedBox(height: 16),
            ],
            const _Recent(),
            // 06 §6: an empty screen says what to do, in one line.
            if (empty && e.modelReady)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 96, horizontal: 24),
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.homeEmpty, textAlign: TextAlign.center, style: title),
                  ],
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _picking || !ready ? null : () => _pick(several: false),
                child: Text(l10n.homeChoosePhoto),
              ),
              TextButton(
                onPressed: _picking || !ready ? null : () => _pick(several: true),
                child: Text(l10n.homeChooseSeveral),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The latest saved results (06 §3.1), as a grid of their previews; all of them in History.
class _Recent extends ConsumerWidget {
  const _Recent();

  static const _shown = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
    final store = ref.watch(historyStoreProvider).value;
    if (entries.isEmpty || store == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.historyTitle, style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(onPressed: () => context.push('/history'), child: Text(l10n.homeSeeAll)),
          ],
        ),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final e in entries.take(_shown))
              Semantics(
                button: true,
                label: formatDateTime(context, e.createdAt),
                child: InkWell(
                  onTap: () => context.push('/history/entry', extra: e.id),
                  child: LayoutBuilder(
                    builder: (context, c) =>
                        HistoryPreview(file: File(store.absolute(e.previewPath)), size: c.maxWidth),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onOpen, required this.onDiscard});

  final JobEntry job;
  final void Function(EditorArgs) onOpen;
  final void Function(JobEntry) onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = scaleLabel(l10n, job.request.scale, fast2: job.request.fast2);
    final subtitle = job.finished
        ? l10n.jobReadyNotSaved(scale)
        : job.inputExists
        ? l10n.jobPausedAt(scale, (job.progress * 100).round())
        : l10n.jobOriginalGone(scale);
    final thumb = job.finished ? File(job.previewPath) : File(job.input);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image(
          image: ResizeImage(FileImage(thumb), width: 96, policy: ResizeImagePolicy.fit),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              const SizedBox(width: 48, height: 48, child: Icon(Icons.image)),
        ),
      ),
      title: Text(job.finished ? l10n.jobTitleFinished : l10n.jobTitlePaused),
      subtitle: Text(subtitle),
      onTap: job.finished || job.resumable
          ? () => onOpen(EditorArgs(job.input, jobDir: job.dir, finished: job.finished))
          : null,
      trailing: IconButton(
        tooltip: l10n.deleteTooltip,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => onDiscard(job),
      ),
    );
  }
}
