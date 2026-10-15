import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:refocal_platform/refocal_platform.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/job_store.dart';
import '../../bootstrap/processing.dart';
import '../../bootstrap/queue.dart';
import '../../bootstrap/tier.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/errors.dart';
import '../../ui_kit/labels.dart';
import '../editor/editor_page.dart';
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

  Future<void> _discard(JobEntry j) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await ref.read(startupProvider.future);
    final jobs = await ref.read(jobStoreProvider.future);
    try {
      await jobs.discard(j.dir);
    } on FileSystemException catch (e, stack) {
      showError(messenger, l10n, 'discard job', e, stack, l10n.historyDeleteFailed);
    }
    ref.invalidate(jobListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final engine = ref.watch(startupProvider);
    final jobs = ref.watch(jobListProvider).value ?? const <JobEntry>[];
    final queued = ref.watch(queueItemsProvider).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.historyTitle,
            onPressed: () => context.push('/history'),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: l10n.aboutTooltip,
            onPressed: () => context.push('/about'),
            icon: const Icon(Icons.info_outline),
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
        data: (e) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.auto_fix_high, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.homeTagline,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.homePrivacy, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (!e.modelReady)
              Text(
                l10n.homeModelMissing,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              )
            else
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: _picking ? null : () => _pick(several: false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(l10n.homeChoosePhoto),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _picking ? null : () => _pick(several: true),
                    icon: const Icon(Icons.burst_mode_outlined),
                    label: Text(l10n.homeChooseSeveral),
                  ),
                  if (queued > 0) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => context.push('/queue'),
                      icon: const Icon(Icons.queue_outlined),
                      label: Text(l10n.homeQueue(queued)),
                    ),
                  ],
                ],
              ),
            if (jobs.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(l10n.homeNotFinished, style: Theme.of(context).textTheme.titleSmall),
              for (final j in jobs) _JobTile(job: j, onOpen: _openEditor, onDiscard: _discard),
            ],
            const SizedBox(height: 24),
            Text(
              l10n.homeCore(e.native.version),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
