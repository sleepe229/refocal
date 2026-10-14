import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/compare_slider.dart';
import '../../ui_kit/labels.dart';
import 'enhance_controller.dart';

/// What the editor opens: a new photo, or a job from the home screen list.
class EditorArgs {
  const EditorArgs(this.input, {this.jobDir, this.finished = false});
  final String input;

  /// Set: continue this job (paused/interrupted) or show its result ([finished]).
  final String? jobDir;
  final bool finished;
}

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, required this.args});
  final EditorArgs args;

  String get input => args.input;

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
    final dir = widget.args.jobDir;
    if (dir != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctl = ref.read(enhanceProvider.notifier);
        widget.args.finished ? ctl.open(dir, widget.input) : ctl.resume(dir, widget.input);
      });
    }
  }

  Future<void> _readSize() async {
    // Header only: dimensions without decoding the pixels.
    try {
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
    } on Object {
      // Flutter cannot decode every input the core can (e.g. AVIF on older Android).
      if (mounted) setState(() => _choice ??= ScaleChoice.fast2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        appBar: AppBar(title: Text(l10n.editorTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (state) {
              Finished(:final result, :final strength) => CompareSlider(
                before: original,
                after: FileImage(File(result.previewPath)),
                aspectRatio: result.width / result.height,
                strength: strength,
              ),
              _ => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image(
                  image: original,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 200,
                    child: Center(child: Icon(Icons.image_outlined, size: 64)),
                  ),
                ),
              ),
            },
            const SizedBox(height: 16),
            switch (state) {
              Idle() || AskUser() => _controls(ctl, l10n),
              Running() => _progress(state, ctl, l10n),
              Paused() => _paused(state, ctl, l10n),
              Finished() => _finished(state, ctl, l10n),
              Failed() => _failed(state, ctl, l10n),
            },
          ],
        ),
      ),
    );
  }

  Widget _controls(EnhanceController ctl, AppLocalizations l10n) {
    final size = _size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (size != null)
          Text(l10n.sizePx(size.width.toInt(), size.height.toInt()), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        SegmentedButton<ScaleChoice>(
          segments: [
            for (final c in ScaleChoice.values)
              ButtonSegment(
                value: c,
                label: Text(scaleLabel(l10n, c.scale, fast2: c.fastPath)),
              ),
          ],
          selected: {?_choice},
          emptySelectionAllowed: true,
          onSelectionChanged: (s) => setState(() => _choice = s.firstOrNull),
        ),
        if (_choice == ScaleChoice.x1) ...[
          const SizedBox(height: 8),
          Text(l10n.scaleX1Hint, textAlign: TextAlign.center),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _choice == null ? null : () => ctl.start(widget.input, _choice!),
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l10n.enhance),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.aiDisclaimer,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _progress(Running s, EnhanceController ctl, AppLocalizations l10n) {
    final eta = s.eta;
    final percent = (s.progress * 100).round();
    final label = switch (s.stage) {
      JobStage.queued => l10n.stageWaiting,
      JobStage.decode => l10n.stageReading,
      JobStage.upscale =>
        eta == null
            ? l10n.stageEnhancing(percent)
            : l10n.stageEnhancingEta(percent, eta.inSeconds + 1),
      JobStage.finalize => l10n.stageFinishing,
      JobStage.unknown => l10n.stageWorking,
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
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: s.stage == JobStage.upscale ? ctl.pause : null,
                child: Text(l10n.pause),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(onPressed: ctl.cancel, child: Text(l10n.cancel)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.backgroundHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _paused(Paused s, EnhanceController ctl, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: s.progress),
        const SizedBox(height: 8),
        Text(
          s.byTimeout ? l10n.pausedByTimeout : l10n.pausedAt((s.progress * 100).round()),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => ctl.resume(s.jobDir, widget.input),
          icon: const Icon(Icons.play_arrow),
          label: Text(l10n.continueAction),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text(l10n.continueLater),
        ),
      ],
    );
  }

  Widget _finished(Finished s, EnhanceController ctl, AppLocalizations l10n) {
    final hasOriginal = ctl.originalExists;
    final busy = s.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.sizePx(s.result.width, s.result.height), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(l10n.strength),
            Expanded(
              child: Slider(
                value: s.strength,
                divisions: 20,
                label: l10n.strengthValue((s.strength * 100).round()),
                semanticFormatterCallback: (v) => l10n.strengthValue((v * 100).round()),
                onChanged: hasOriginal && !busy ? ctl.setStrength : null,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(l10n.strengthValue((s.strength * 100).round()), textAlign: TextAlign.end),
            ),
          ],
        ),
        if (!hasOriginal)
          Text(
            l10n.strengthNeedsOriginal,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        FilledButton.icon(
          onPressed: busy ? null : () => _save(() => ctl.saveToGallery(), l10n.savedToGallery),
          icon: const Icon(Icons.save_alt),
          label: Text(l10n.saveToGallery),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : () => _saveAs(s, ctl, l10n),
          icon: const Icon(Icons.description_outlined),
          label: Text(l10n.saveAsFile),
        ),
        TextButton(onPressed: busy ? null : ctl.reset, child: Text(l10n.tryAnotherScale)),
      ],
    );
  }

  Future<void> _save(Future<String?> Function() save, String done) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await save() != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on EnhException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.status == EnhStatus.limit ? l10n.formatWebpTooLarge : l10n.saveFailed(e.toString()),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.saveFailed('$e'))));
    }
  }

  Future<void> _saveAs(Finished s, EnhanceController ctl, AppLocalizations l10n) async {
    final mp = s.result.width * s.result.height / 1e6;
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.saveAsTitle)),
            for (final f in ExportFormat.values)
              ListTile(
                title: Text(formatLabel(l10n, f)),
                subtitle: mp > f.maxMegapixels ? Text(l10n.formatWebpTooLarge) : null,
                enabled: mp <= f.maxMegapixels,
                onTap: () => Navigator.pop(context, f),
              ),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;
    await _save(() => ctl.saveToFile(format), l10n.savedToFile);
  }

  Widget _failed(Failed s, EnhanceController ctl, AppLocalizations l10n) {
    final text = switch (s.status) {
      EnhStatus.cancelled => l10n.failCancelled,
      EnhStatus.paused => l10n.failPaused,
      EnhStatus.diskFull => l10n.failDiskFull,
      EnhStatus.invalid => l10n.failInvalid,
      EnhStatus.limit => l10n.failLimit,
      EnhStatus.oom => l10n.failOom,
      _ => l10n.failOther(s.status.name),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: ctl.reset, child: Text(l10n.back)),
      ],
    );
  }

  Future<void> _askUser(NeedsUserEvent e) async {
    final l10n = AppLocalizations.of(context);
    final ctl = ref.read(enhanceProvider.notifier);
    final opts = e.options;
    final picked = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.tooLargeTitle),
        content: Text(l10n.tooLargeBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          for (final o in opts)
            TextButton(
              onPressed: () => Navigator.pop(context, o),
              child: Text(
                scaleLabel(l10n, (o['scale'] as num?)?.toInt() ?? 4, fast2: o['fast2'] == true),
              ),
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
