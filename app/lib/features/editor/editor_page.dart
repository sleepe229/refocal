import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:refocal_core/refocal_core.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/auto.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/app_log.dart';
import '../../bootstrap/files.dart';
import '../../bootstrap/models.dart';
import '../../bootstrap/presets.dart';
import '../../bootstrap/result_saver.dart';
import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/compare_slider.dart';
import '../../ui_kit/errors.dart';
import '../../ui_kit/labels.dart';
import '../presets/preset_name_dialog.dart';
import 'enhance_controller.dart';

/// What the editor opens: a new photo, or a job from the home screen list.
class EditorArgs {
  const EditorArgs(this.input, {this.jobDir, this.finished = false, this.recipe});
  final String input;

  /// Set: continue this job (paused/interrupted) or show its result ([finished]).
  final String? jobDir;
  final bool finished;

  /// Parameters to start from, changeable before Enhance (a history entry, FR-HIST-003).
  final Recipe? recipe;
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

  /// Strength the result starts with: from a preset or a history entry, else 100%.
  double _strength = 1;

  /// A new photo starts with Auto (06 §3.2): Enhance waits for its first proposal.
  late bool _autoFirst = widget.args.recipe == null && widget.args.jobDir == null;

  @override
  void initState() {
    super.initState();
    if (widget.args.recipe case final r?) _apply(r);
    _readSize();
    if (widget.args.jobDir == null) {
      ref.listenManual(autoProvider(widget.input), _onAuto, fireImmediately: true);
    }
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

  /// Applies Auto's proposal first, and again when it changes (the tier is measured, a pack is
  /// installed) while the settings still are Auto's.
  void _onAuto(AsyncValue<AutoProposal>? prev, AsyncValue<AutoProposal> next) {
    final p = next.value;
    if (p == null) {
      if (next.hasError) {
        AppLog.warn('analyze: ${next.error}');
        setState(() => _autoFirst = false); // the size-based default stays
      }
      return;
    }
    final followed = switch (prev?.value) {
      final old? => _matches(old.decision.recipe),
      null => false,
    };
    if (_autoFirst || followed) {
      setState(() {
        _autoFirst = false;
        _apply(p.decision.recipe);
      });
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
                resultLabel: l10n.resultAlt(result.width, result.height),
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

  void _apply(Recipe r) {
    _choice = ScaleChoice.of(r);
    _strength = r.strength;
    _model = r.srModel;
    _faces = r.faceModel != null;
    _faceStrength = r.faceStrength;
    _facesOnly = r.facesOnly;
  }

  bool _matches(Recipe r) =>
      _choice == ScaleChoice.of(r) &&
      _strength == r.strength &&
      _model == r.srModel &&
      _faces == (r.faceModel != null) &&
      (!_faces || (_faceStrength == r.faceStrength && _facesOnly == r.facesOnly));

  /// FR-FACE-002/004: restore faces with the face pack, at this strength.
  bool _faces = false;
  double _faceStrength = Recipe.defaultFaceStrength;

  /// FR-FACE-006 region "Faces": the rest of the photo is only upscaled (Lanczos), faster.
  bool _facesOnly = false;

  /// The SR model: the bundled one, or an installed pack (a denoise level, ADR-0015).
  String _model = bundledSrModel;

  /// What Enhance runs; [_model] is one the device has (installed or bundled).
  Recipe? get _recipe {
    final c = _choice;
    if (c == null || _autoFirst) return null;
    final r = Recipe(
      scale: c.scale,
      fast2: c.fastPath,
      srModel: _model,
      strength: _strength,
      faceModel: _faces ? defaultFacePack : null,
      faceStrength: _faceStrength,
      facesOnly: _faces && _facesOnly,
    );
    return canRun(r, ref.read(availableModelsProvider)) ? r : null;
  }

  /// Faces (FR-FACE-002..004): a switch and the strength once the face pack is installed; else
  /// what is needed and the way to the Models screen (FR-FACE-003).
  Widget _facesControls(AppLocalizations l10n) {
    final available = ref.watch(availableModelsProvider);
    if (!available.contains(bundledDetector)) return const SizedBox.shrink();
    if (!available.contains(defaultFacePack)) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.face_retouching_natural),
        title: Text(l10n.faces),
        subtitle: Text(l10n.facesNeedPack),
        trailing: TextButton(
          onPressed: () => context.push('/models'),
          child: Text(l10n.facesGetPack),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.face_retouching_natural),
          title: Text(l10n.faces),
          subtitle: Text(l10n.facesHint),
          value: _faces,
          onChanged: (v) => setState(() => _faces = v),
        ),
        if (_faces)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l10n.regionAll)),
              ButtonSegment(value: true, label: Text(l10n.regionFaces)),
            ],
            selected: {_facesOnly},
            onSelectionChanged: (s) => setState(() => _facesOnly = s.first),
          ),
        if (_faces)
          Row(
            children: [
              Text(l10n.facesStrength),
              Expanded(
                child: Slider(
                  value: _faceStrength,
                  divisions: 20,
                  label: l10n.strengthValue((_faceStrength * 100).round()),
                  semanticFormatterCallback: (v) => l10n.strengthValue((v * 100).round()),
                  onChanged: (v) => setState(() => _faceStrength = v),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// ADR-0022: before faces are restored the first time (by the switch, a preset or Auto),
  /// what face restoration does.
  Future<bool> _faceNotice(AppLocalizations l10n) async {
    final settings = await ref.read(settingsProvider.future);
    if (settings.faceNoticeSeen || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.facesNoticeTitle),
        content: Text(l10n.facesNoticeBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.facesNoticeOk),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await ref.read(settingsProvider.notifier).change((s) => s.copyWith(faceNoticeSeen: true));
    } on Exception catch (e) {
      AppLog.warn('face notice: ${e.runtimeType}'); // shown again next time
    }
    return true;
  }

  /// Denoise levels the installed packs offer (ADR-0015); hidden with only the built-in one.
  Widget? _denoise(AppLocalizations l10n) {
    final available = ref.watch(availableModelsProvider);
    final levels = [
      for (final d in DenoiseLevel.values)
        if (available.contains(d.model)) d,
    ];
    if (levels.length < 2) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(l10n.denoise, textAlign: TextAlign.center),
        SegmentedButton<DenoiseLevel>(
          segments: [
            for (final d in levels)
              ButtonSegment(
                value: d,
                label: Text(switch (d) {
                  DenoiseLevel.none => l10n.denoiseNone,
                  DenoiseLevel.standard => l10n.denoiseStandard,
                  DenoiseLevel.strong => l10n.denoiseStrong,
                }),
              ),
          ],
          selected: {?DenoiseLevel.of(_model)},
          onSelectionChanged: (s) => setState(() => _model = s.first.model),
        ),
      ],
    );
  }

  /// Presets apply before Enhance (FR-PRE-001/002); one of a model the device does not have
  /// (a pack not installed) cannot run.
  Widget _presets(AppLocalizations l10n) {
    final user = ref.watch(presetsProvider).value ?? const <Preset>[];
    final available = ref.watch(availableModelsProvider);
    final messenger = ScaffoldMessenger.of(context);
    Widget chip(String label, Recipe r) => ChoiceChip(
      label: Text(label),
      selected: _matches(r),
      onSelected: (_) {
        if (!canRun(r, available)) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.presetModelMissing)));
          return;
        }
        setState(() => _apply(r));
      },
    );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        if (widget.args.jobDir == null) _autoChip(l10n),
        for (final b in BuiltinPreset.values) chip(builtinPresetLabel(l10n, b), b.recipe),
        for (final p in user) chip(p.name, p.recipe),
      ],
    );
  }

  /// Auto (FR-ENH-007): enh_analyze + AutoPolicy; disabled until the analysis is done.
  Widget _autoChip(AppLocalizations l10n) {
    final auto = ref.watch(autoProvider(widget.input));
    final p = auto.value;
    return ChoiceChip(
      avatar: auto.isLoading
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      label: Text(l10n.autoChip),
      selected: p != null && _matches(p.decision.recipe),
      onSelected: p == null ? null : (_) => setState(() => _apply(p.decision.recipe)),
    );
  }

  /// What Auto found and chose (06 §3.2), while Auto is selected.
  Widget? _autoExplanation(AppLocalizations l10n) {
    if (widget.args.jobDir != null) return null;
    final text = switch (ref.watch(autoProvider(widget.input))) {
      AsyncData(value: final p) when _matches(p.decision.recipe) => autoExplanation(
        l10n,
        p.analysis,
        p.decision,
      ),
      AsyncData() => null,
      AsyncError() => l10n.autoFailed,
      _ => l10n.autoAnalyzing,
    };
    if (text == null) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
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
        _presets(l10n),
        ?_autoExplanation(l10n),
        ?_denoise(l10n),
        _facesControls(l10n),
        const SizedBox(height: 8),
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
        if (_strength != 1) ...[
          const SizedBox(height: 8),
          Text(
            l10n.presetStrengthAfter(l10n.strengthValue((_strength * 100).round())),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: switch (_recipe) {
            final r? => () => _enhance(ctl, r, l10n),
            null => null,
          },
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

  Future<void> _enhance(EnhanceController ctl, Recipe r, AppLocalizations l10n) async {
    if (r.faceModel != null && !await _faceNotice(l10n)) return;
    if (!mounted) return;
    await ctl.start(widget.input, r);
  }

  Widget _progress(Running s, EnhanceController ctl, AppLocalizations l10n) {
    final eta = s.eta;
    final percent = (s.progress * 100).round();
    final label = switch (s.stage) {
      JobStage.queued => l10n.stageWaiting,
      JobStage.decode => l10n.stageReading,
      JobStage.faces => l10n.stageFaces(percent),
      JobStage.upscale =>
        eta == null
            ? l10n.stageEnhancing(percent)
            : l10n.stageEnhancingEta(percent, eta.inSeconds + 1),
      JobStage.finalize => l10n.stageFinishing,
      JobStage.unknown => l10n.stageWorking,
    };
    // A11Y-PRG-001: the screen reader hears the progress at most once per 10%.
    final spoken = switch (s.stage) {
      JobStage.upscale => l10n.stageEnhancing((s.progress * 10).floor() * 10),
      _ => label,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          label: spoken,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(
                  value: s.stage == JobStage.upscale || s.stage == JobStage.faces
                      ? s.progress
                      : null,
                ),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        if (s.note != null) // A11Y-PRG-002: fallback and thermal notes are announced
          Semantics(
            liveRegion: true,
            child: Text(
              s.note!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
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
    // The input is the blend base below 100% strength.
    final hasOriginal = ref.watch(fileExistsProvider(widget.input)).value ?? false;
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
        TextButton(
          onPressed: busy ? null : () => _saveAsPreset(ctl, l10n),
          child: Text(l10n.presetSaveAs),
        ),
        TextButton(onPressed: busy ? null : ctl.reset, child: Text(l10n.tryAnotherScale)),
      ],
    );
  }

  Future<void> _saveAsPreset(EnhanceController ctl, AppLocalizations l10n) async {
    final recipe = ctl.recipe;
    if (recipe == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = await showPresetNameDialog(context, title: l10n.presetSaveAs);
    if (name == null) return;
    try {
      final repo = await ref.read(presetRepositoryProvider.future);
      await repo.add(name, recipe);
      messenger.showSnackBar(SnackBar(content: Text(l10n.presetSaved)));
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'save preset', e, stack, l10n.presetSaveFailed);
    }
  }

  Future<void> _save(Future<String?> Function() save, String done) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await save() != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } on HistoryNotRecorded catch (e, stack) {
      showError(messenger, l10n, 'record history', e.cause, stack, l10n.historyNotRecorded);
    } on EnhException catch (e, stack) {
      if (e.status == EnhStatus.limit) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.formatWebpTooLarge)));
      } else {
        showError(messenger, l10n, 'save', e, stack, l10n.saveFailed);
      }
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'save', e, stack, l10n.saveFailed);
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
    final text = statusText(l10n, s.status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(liveRegion: true, child: Text(text, textAlign: TextAlign.center)),
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
