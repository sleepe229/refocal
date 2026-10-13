import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/engine.dart';
import '../../bootstrap/job_store.dart';
import '../editor/editor_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _picking = false;

  Future<void> _openEditor(EditorArgs args) async {
    await context.push('/editor', extra: args);
    ref.invalidate(jobListProvider); // the editor may have finished, paused or cleaned up jobs
  }

  Future<void> _pick() async {
    final engine = await ref.read(engineProvider.future);
    setState(() => _picking = true);
    try {
      final picked = await ref.read(platformApiProvider).pickImage(engine.inboxDir);
      if (picked != null && mounted) await _openEditor(EditorArgs(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open the photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
    final engine = ref.watch(engineProvider);
    final jobs = ref.watch(jobListProvider).value ?? const <JobEntry>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refocal'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'About',
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
            child: Text('Native core unavailable: $e'),
          ),
        ),
        data: (e) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.auto_fix_high, size: 64),
            const SizedBox(height: 16),
            Text(
              'Bring your photos back into focus.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Everything runs on this phone. Photos never leave it.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (!e.modelReady)
              const Text(
                'The enhancement model is missing from this build.',
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              )
            else
              Center(
                child: FilledButton.icon(
                  onPressed: _picking ? null : _pick,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose a photo'),
                ),
              ),
            if (jobs.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text('Not finished', style: Theme.of(context).textTheme.titleSmall),
              for (final j in jobs) _JobTile(job: j, onOpen: _openEditor, onDiscard: _discard),
            ],
            const SizedBox(height: 24),
            Text(
              'Core ${e.native.version}',
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
    final subtitle = job.finished
        ? '${job.scaleLabel} · ready, not saved'
        : job.inputExists
        ? '${job.scaleLabel} · paused at ${(job.progress * 100).round()}%'
        : '${job.scaleLabel} · the original is gone, cannot continue';
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
      title: Text(job.finished ? 'Enhanced photo' : 'Paused enhancement'),
      subtitle: Text(subtitle),
      onTap: job.finished || job.resumable
          ? () => onOpen(EditorArgs(job.input, jobDir: job.dir, finished: job.finished))
          : null,
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => onDiscard(job),
      ),
    );
  }
}
