import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../ui_kit/compare_slider.dart';
import 'enhance_controller.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, required this.input});
  final String input;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  ScaleChoice? _choice;
  ui.Size? _size;

  @override
  void initState() {
    super.initState();
    _readSize();
  }

  Future<void> _readSize() async {
    // Header only: dimensions without decoding the pixels.
    final buf = await ui.ImmutableBuffer.fromFilePath(widget.input);
    final desc = await ui.ImageDescriptor.encoded(buf);
    if (!mounted) return;
    final mp = desc.width * desc.height / 1e6;
    setState(() {
      _size = ui.Size(desc.width.toDouble(), desc.height.toDouble());
      _choice ??= mp >= 8 ? ScaleChoice.fast2 : ScaleChoice.x4; // ADR-0014
    });
    desc.dispose();
    buf.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(enhanceProvider);
    final ctl = ref.read(enhanceProvider.notifier);
    ref.listen(enhanceProvider, (prev, next) {
      if (next is AskUser && prev is! AskUser) _askUser(next.event);
    });
    final original = ResizeImage(
      FileImage(File(widget.input)),
      width: 2048,
      policy: ResizeImagePolicy.fit,
    );
    return PopScope(
      canPop: state is! Running,
      child: Scaffold(
        appBar: AppBar(title: const Text('Enhance')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (state) {
              Finished(:final result) => CompareSlider(
                before: original,
                after: FileImage(File(result.previewPath)),
                aspectRatio: result.width / result.height,
              ),
              _ => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(image: original, fit: BoxFit.contain),
              ),
            },
            const SizedBox(height: 16),
            switch (state) {
              Idle() || AskUser() => _controls(ctl),
              Running() => _progress(state, ctl),
              Finished() => _finished(state, ctl),
              Failed() => _failed(state, ctl),
            },
          ],
        ),
      ),
    );
  }

  Widget _controls(EnhanceController ctl) {
    final size = _size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (size != null)
          Text('${size.width.toInt()} × ${size.height.toInt()} px', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        SegmentedButton<ScaleChoice>(
          segments: [
            for (final c in ScaleChoice.values) ButtonSegment(value: c, label: Text(c.label)),
          ],
          selected: {?_choice},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) => setState(() => _choice = s.firstOrNull),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _choice == null ? null : () => ctl.start(widget.input, _choice!),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('Enhance'),
        ),
        const SizedBox(height: 8),
        Text(
          'AI adds plausible detail that was not in the original photo.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _progress(Running s, EnhanceController ctl) {
    final eta = s.eta;
    final label = switch (s.stage) {
      JobStage.queued => 'Waiting…',
      JobStage.decode => 'Reading the photo…',
      JobStage.upscale =>
        'Enhancing ${(s.progress * 100).round()}%'
            '${eta == null ? '' : ' · ~${eta.inSeconds + 1} s left'}',
      JobStage.finalize => 'Finishing…',
      JobStage.unknown => 'Working…',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: s.stage == JobStage.upscale ? s.progress : null),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center),
        if (s.note != null)
          Text(s.note!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: ctl.cancel, child: const Text('Cancel')),
      ],
    );
  }

  Widget _finished(Finished s, EnhanceController ctl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${s.result.width} × ${s.result.height} px', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (s.savedUri == null)
          FilledButton.icon(
            onPressed: () async {
              try {
                await ctl.save();
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Saved to Pictures/Refocal')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Save failed: $e')));
                }
              }
            },
            icon: const Icon(Icons.save_alt),
            label: const Text('Save to gallery'),
          )
        else
          const Text('Saved to Pictures/Refocal', textAlign: TextAlign.center),
        TextButton(onPressed: ctl.reset, child: const Text('Try another scale')),
      ],
    );
  }

  Widget _failed(Failed s, EnhanceController ctl) {
    final text = switch (s.status) {
      EnhStatus.cancelled => 'Cancelled.',
      EnhStatus.paused => 'Paused.',
      EnhStatus.diskFull => 'Not enough free storage for this size.',
      EnhStatus.invalid => 'This photo format is not supported yet (JPEG only).',
      EnhStatus.oom => 'Not enough memory. Try Fast 2×.',
      _ => 'Something went wrong (${s.status.name}).',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: ctl.reset, child: const Text('Back')),
      ],
    );
  }

  Future<void> _askUser(NeedsUserEvent e) async {
    final ctl = ref.read(enhanceProvider.notifier);
    final opts = e.options;
    final picked = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('This photo is too large for that scale'),
        content: const Text('Choose a smaller output size.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          for (final o in opts)
            TextButton(
              onPressed: () => Navigator.pop(context, o),
              child: Text(o['fast2'] == true ? 'Fast 2×' : '${o['scale']}×'),
            ),
        ],
      ),
    );
    if (picked == null) {
      ctl.cancel();
      return;
    }
    ctl.answer(picked);
  }
}
