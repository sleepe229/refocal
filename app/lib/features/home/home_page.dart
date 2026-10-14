import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/engine.dart';
import '../../bootstrap/job_store.dart';
import '../../bootstrap/processing.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';
import '../editor/editor_page.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _openShared());
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

  /// A photo shared to the app (FR-SHARE-001). One editor at a time: a share that arrives
  /// while one is open waits on the platform side until it closes (the queue is 0.0.4).
  Future<void> _openShared() async {
    if (_editorOpen || _picking || !mounted) return;
    await _open(() async {
      final engine = await ref.read(engineProvider.future);
      if (!engine.modelReady) return null;
      return (await ref.read(platformApiProvider).takeSharedImage(engine.inboxDir))?.path;
    });
  }

  Future<void> _pick() => _open(() async {
    final engine = await ref.read(engineProvider.future);
    return (await ref.read(platformApiProvider).pickImage(engine.inboxDir))?.path;
  });

  Future<void> _open(Future<String?> Function() take) async {
    setState(() => _picking = true);
    String? path;
    try {
      path = await take();
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.homeOpenFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (path != null && mounted) await _openEditor(EditorArgs(path));
  }

  Future<void> _discard(JobEntry j) async {
    final engine = await ref.read(engineProvider.future);
    try {
      engine.jobs.discard(j.dir);
    } on FileSystemException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    ref.invalidate(jobListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final engine = ref.watch(engineProvider);
    final jobs = ref.watch(jobListProvider).value ?? const <JobEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
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
            child: Text(l10n.homeCoreUnavailable('$e')),
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
              Center(
                child: FilledButton.icon(
                  onPressed: _picking ? null : _pick,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(l10n.homeChoosePhoto),
                ),
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
    final scale = scaleLabel(l10n, job.scale, fast2: job.fast2);
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
