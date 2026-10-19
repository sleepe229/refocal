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
import '../../bootstrap/tier.dart';
import '../../bootstrap/viewer.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/compare_slider.dart';
import '../../ui_kit/errors.dart';
import '../../ui_kit/labels.dart';
import '../presets/preset_name_dialog.dart';
import 'enhance_controller.dart';
import 'fragment_preview.dart';
import '../report/bad_result.dart';

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
    // 06 §1, §7: the photo on a dark canvas, the controls in a panel below it (Apple's Photos).
    final base = Theme.of(context);
    final canvas = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: base.colorScheme.primary,
        brightness: Brightness.dark,
        surface: Colors.black,
      ),
    );
    return PopScope(
      canPop: state is! Running,
      child: Theme(
        data: canvas,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, actions: [?_menu(state, ctl, l10n)]),
            body: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: switch (state) {
                        Finished(:final result, :final strength) => CompareSlider(
                          before: original,
                          after: FileImage(File(result.previewPath)),
                          aspectRatio: result.width / result.height,
                          strength: strength,
                          resultLabel: l10n.resultAlt(result.width, result.height),
                          // Zoom to 1:1 of the result (FR-CMP-005): tiles from its BandStore.
                          tiles: ref.watch(viewerTilesProvider(result.jobDir)).value,
                          resultWidth: result.width,
                          resultHeight: result.height,
                        ),
                        _ => _preview(original, state is Idle || state is AskUser, l10n),
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: AnimatedSize(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      alignment: Alignment.bottomCenter,
                      child: switch (state) {
                        Idle() || AskUser() => _controls(ctl, l10n),
                        Running() => _progress(state, ctl, l10n),
                        Paused() => _paused(state, ctl, l10n),
                        Finished() => _finished(state, ctl, l10n),
                        Failed() => _failed(state, ctl, l10n),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The "…" menu (06 §3.2): what is not the screen's main action.
  Widget? _menu(EnhanceState state, EnhanceController ctl, AppLocalizations l10n) {
    final items = <(String, VoidCallback?)>[];
    switch (state) {
      case Idle() || AskUser():
        final r = _recipe;
        final a = ref.watch(photoAnalysisProvider(widget.input)).value;
        items.add((
          l10n.fragmentAction,
          r != null && a != null ? () => _previewFragment(ctl, r, l10n) : null,
        ));
      case Finished(saving: final busy):
        if (!busy) {
          items.addAll([
            (l10n.saveAsFile, () => _saveAs(state, ctl, l10n)),
            (l10n.strength, () => _strengthSheet(l10n)),
            (l10n.presetSaveAs, () => _saveAsPreset(ctl, l10n)),
            (l10n.tryAnotherScale, ctl.reset),
            (l10n.resultDetails, () => _details(state, l10n)),
            // FR-REP-001: tell the project about a bad result (15 §5).
            (l10n.reportBadAction, () => showBadResultReport(context, state.result)),
          ]);
        }
      default:
    }
    if (items.isEmpty) return null;
    return PopupMenuButton<int>(
      tooltip: l10n.moreTooltip,
      icon: const Icon(Icons.more_horiz),
      itemBuilder: (_) => [
        for (final (i, (label, action)) in items.indexed)
          PopupMenuItem(value: i, enabled: action != null, child: Text(label)),
      ],
      onSelected: (i) => items[i].$2?.call(),
    );
  }

  void _apply(Recipe r) {
    _choice = ScaleChoice.of(r);
    _strength = r.strength;
    _model = r.srModel;
    _faces = r.faceModel != null;
    _faceModel = r.faceModel ?? _faceModel;
    _faceStrength = r.faceStrength;
    _faceFidelity = r.faceFidelity;
    _facesOnly = r.facesOnly;
    _jpeg = r.jpegModel != null;
    _scratches = r.scratchModel != null;
    _lowLight = r.lowlightModel != null;
  }

  /// FR-ENH-003, ADR-0014: 8x on T2 for an input of at most 1.5 MP (a preset may still pick
  /// it elsewhere: the core then asks for a smaller scale).
  bool get _x8Allowed {
    final size = _size;
    final tier = ref.watch(tierProvider).value?.tier;
    return tier == DeviceTier.t2 && size != null && size.width * size.height <= Recipe.maxX8InputPx;
  }

  bool _matches(Recipe r) =>
      _choice == ScaleChoice.of(r) &&
      _strength == r.strength &&
      _model == r.srModel &&
      _faces == (r.faceModel != null) &&
      (!_faces ||
          (_faceModel == r.faceModel &&
              _faceStrength == r.faceStrength &&
              _faceFidelity == r.faceFidelity &&
              _facesOnly == r.facesOnly)) &&
      _jpeg == (r.jpegModel != null) &&
      _scratches == (r.scratchModel != null) &&
      _lowLight == (r.lowlightModel != null);

  /// FR-FACE-007: faces of this photo the user turned off (boxes from the analysis).
  final _facesOff = <FaceBox>{};

  /// The photo; before Enhance with face restoration on, a box over each face it would
  /// restore: a tap turns that face off or on again (FR-FACE-007).
  Widget _preview(ImageProvider original, bool editable, AppLocalizations l10n) {
    final image = Image(
      image: original,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const SizedBox(height: 200, child: Center(child: Icon(Icons.image_outlined, size: 64))),
    );
    final a = ref.watch(photoAnalysisProvider(widget.input)).value;
    if (!editable || a == null) return Center(child: image);
    final boxes = _faces && a.boxes.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final crop = _fragmentPicked ? _fragmentCrop(a) : null;
    return Center(
      child: AspectRatio(
        aspectRatio: a.width / a.height,
        child: LayoutBuilder(
          builder: (context, c) {
            final k = c.maxWidth / a.width;
            return Stack(
              fit: StackFit.expand,
              children: [
                // A tap chooses the part for the fragment preview (FR-ENH-015).
                GestureDetector(
                  onTapUp: (d) => setState(() {
                    _fragmentPicked = true;
                    _fragmentCentre = Offset(
                      d.localPosition.dx / c.maxWidth,
                      d.localPosition.dy / c.maxHeight,
                    );
                  }),
                  child: image,
                ),
                if (crop != null)
                  Positioned(
                    left: crop.x * k,
                    top: crop.y * k,
                    width: crop.w * k,
                    height: crop.h * k,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.tertiary, width: 2),
                        ),
                      ),
                    ),
                  ),
                if (boxes)
                  for (final (i, b) in a.boxes.indexed)
                    Positioned(
                      left: b.x * k,
                      top: b.y * k,
                      width: b.w * k,
                      height: b.h * k,
                      child: _faceBox(i, b, scheme, l10n),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// FR-ENH-015: the part of the photo the fragment preview runs on (the centre of the image
  /// until a tap picks another).
  Offset _fragmentCentre = const Offset(0.5, 0.5);
  bool _fragmentPicked = false;

  ({int x, int y, int w, int h}) _fragmentCrop(PhotoAnalysis a) => FragmentPreview.cropFor(
    _recipe ?? Recipe(scale: 4, srModel: bundledSrModel),
    a.width,
    a.height,
    _fragmentCentre,
  );

  Future<void> _previewFragment(EnhanceController ctl, Recipe r, AppLocalizations l10n) async {
    final a = ref.read(photoAnalysisProvider(widget.input)).value;
    if (a == null) return;
    if (r.faceModel != null && !await _faceNotice(l10n)) return;
    if (!mounted) return;
    final all = await showFragmentPreview(
      context,
      input: widget.input,
      recipe: r,
      crop: _fragmentCrop(a),
      facesOff: r.faceModel == null ? const [] : _facesOff.toList(),
    );
    if (all && mounted) await _enhance(ctl, r, l10n);
  }

  Widget _faceBox(int i, FaceBox b, ColorScheme scheme, AppLocalizations l10n) {
    final on = !_facesOff.contains(b);
    return Semantics(
      button: true,
      toggled: on,
      label: l10n.faceToggle(i + 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => on ? _facesOff.add(b) : _facesOff.remove(b)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: on ? scheme.primary : scheme.outline, width: on ? 2 : 1),
            color: on ? null : scheme.surface.withValues(alpha: 0.5),
          ),
          child: on ? null : Icon(Icons.block, color: scheme.onSurface),
        ),
      ),
    );
  }

  /// FR-FACE-002/004: restore faces with the face pack, at this strength.
  bool _faces = false;
  double _faceStrength = Recipe.defaultFaceStrength;

  /// The face pack: GFPGAN by default, CodeFormer when installed and chosen (FR-FACE-005).
  String _faceModel = defaultFacePack;
  double _faceFidelity = Recipe.defaultFaceFidelity;

  /// FR-FACE-006 region "Faces": the rest of the photo is only upscaled (Lanczos), faster.
  bool _facesOnly = false;

  /// S9: remove JPEG artifacts before SR (the quality factor read from the photo).
  bool _jpeg = false;

  /// S9: find scratches and fill them in before SR.
  bool _scratches = false;

  /// S9: brighten an under-exposed photo before SR.
  bool _lowLight = false;

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
      faceModel: _faces ? _faceModel : null,
      faceStrength: _faceStrength,
      faceFidelity: _faceFidelity,
      facesOnly: _faces && _facesOnly,
      jpegModel: _jpeg ? jpegPack : null,
      scratchModel: _scratches ? scratchPack : null,
      inpaintModel: _scratches ? inpaintPack : null,
      lowlightModel: _lowLight ? lowlightPack : null,
    );
    return canRun(r, ref.read(availableModelsProvider)) ? r : null;
  }

  /// S9: a switch once the JPEG cleanup pack is installed.
  Widget _jpegControl(AppLocalizations l10n) {
    if (!ref.watch(availableModelsProvider).contains(jpegPack)) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.blur_off),
      title: Text(l10n.jpegClean),
      subtitle: Text(l10n.jpegCleanHint),
      value: _jpeg,
      onChanged: (v) => setState(() => _jpeg = v),
    );
  }

  /// S9: a switch once the low-light pack is installed.
  Widget _lowLightControl(AppLocalizations l10n) {
    if (!ref.watch(availableModelsProvider).contains(lowlightPack)) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.wb_sunny_outlined),
      title: Text(l10n.lowLight),
      subtitle: Text(l10n.lowLightHint),
      value: _lowLight,
      onChanged: (v) => setState(() => _lowLight = v),
    );
  }

  /// S9: a switch once both scratch packs are installed.
  Widget _scratchesControl(AppLocalizations l10n) {
    final available = ref.watch(availableModelsProvider);
    if (!available.contains(scratchPack) || !available.contains(inpaintPack)) {
      return const SizedBox.shrink();
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.auto_fix_high),
      title: Text(l10n.scratches),
      subtitle: Text(l10n.scratchesHint),
      value: _scratches,
      onChanged: (v) => setState(() => _scratches = v),
    );
  }

  /// Faces (FR-FACE-002..004): a switch and the strength once the face pack is installed; else
  /// what is needed and the way to the Models screen (FR-FACE-003).
  Widget _facesControls(AppLocalizations l10n) {
    final available = ref.watch(availableModelsProvider);
    if (!available.contains(bundledDetector)) return const SizedBox.shrink();
    final packs = [
      for (final p in facePacks)
        if (available.contains(p)) p,
    ];
    if (packs.isEmpty) {
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
          onChanged: (v) => setState(() {
            _faces = v;
            if (!packs.contains(_faceModel)) _faceModel = packs.first;
          }),
        ),
        if (_faces && packs.length > 1)
          SegmentedButton<String>(
            segments: [
              for (final p in packs)
                ButtonSegment(
                  value: p,
                  label: Text(
                    p == codeformerPack ? l10n.faceModelCodeFormer : l10n.faceModelGfpgan,
                  ),
                ),
            ],
            selected: {_faceModel},
            onSelectionChanged: (s) => setState(() => _faceModel = s.first),
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
        // FR-FACE-005: CodeFormer's w — towards the photo (likeness) or the model (detail).
        if (_faces && _faceModel == codeformerPack)
          Row(
            children: [
              Text(l10n.faceFidelityDetail),
              Expanded(
                child: Slider(
                  value: _faceFidelity,
                  divisions: 10,
                  label: l10n.faceFidelityValue(_faceFidelity.toStringAsFixed(1)),
                  semanticFormatterCallback: (v) =>
                      l10n.faceFidelitySemantics(l10n.faceFidelityValue(v.toStringAsFixed(1))),
                  onChanged: (v) => setState(() => _faceFidelity = v),
                ),
              ),
              Text(l10n.faceFidelityLikeness),
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

  /// SR models the device has and its tier allows (FR-ENH-008); hidden with only the
  /// compact one.
  Widget? _srModel(AppLocalizations l10n) {
    final available = ref.watch(availableModelsProvider);
    final tier = ref.watch(tierProvider).value?.tier ?? DeviceTier.t0;
    final models = [
      for (final m in SrModel.values)
        if (available.contains(m.model) && tier.index >= m.tierMin.index) m,
    ];
    if (models.length < 2) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(l10n.srModel, textAlign: TextAlign.center),
        SegmentedButton<SrModel>(
          segments: [
            for (final m in models) ButtonSegment(value: m, label: Text(srModelLabel(l10n, m))),
          ],
          selected: {?SrModel.of(_model)},
          onSelectionChanged: (s) =>
              setState(() => _model = s.first == SrModel.compact ? bundledSrModel : s.first.model),
        ),
      ],
    );
  }

  /// Denoise levels the installed packs offer (ADR-0015); hidden with only the built-in one
  /// and for the RRDBNet models (no denoise levels).
  Widget? _denoise(AppLocalizations l10n) {
    if (SrModel.of(_model) != SrModel.compact) return null;
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

  /// The fine settings panel is open (06 §3.2 "Настроить", like Adjust in Apple's Photos).
  bool _adjusting = false;

  /// Before Enhance (06 §3.2): what Auto chose in a line, the modes as a bar, Enhance. The fine
  /// settings open in place of the bar.
  Widget _controls(EnhanceController ctl, AppLocalizations l10n) {
    final small = Theme.of(context).textTheme.bodySmall;
    final a = ref.watch(photoAnalysisProvider(widget.input)).value;
    final hint = _faces && (a?.boxes.isNotEmpty ?? false) ? l10n.facesTapHint : null;
    if (_adjusting) return _adjustPanel(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?_autoExplanation(l10n),
        if (hint != null) Text(hint, textAlign: TextAlign.center, style: small),
        const SizedBox(height: 8),
        _modeBar(l10n),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: switch (_recipe) {
            final r? => () => _enhance(ctl, r, l10n),
            null => null,
          },
          child: Text(l10n.enhance),
        ),
      ],
    );
  }

  /// Auto, Portrait, Old photo, the scale and Adjust (06 §3.2).
  Widget _modeBar(AppLocalizations l10n) {
    final auto = ref.watch(autoProvider(widget.input));
    final p = auto.value;
    Widget preset(BuiltinPreset b, IconData icon) => _Tool(
      icon: icon,
      label: builtinPresetLabel(l10n, b),
      selected: _matches(b.recipe),
      onTap: () => _choose(b.recipe, l10n),
    );
    final choice = _choice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.args.jobDir == null)
          _Tool(
            icon: Icons.hdr_auto_outlined,
            label: l10n.autoChip,
            busy: auto.isLoading,
            selected: p != null && _matches(p.decision.recipe),
            onTap: p == null ? null : () => setState(() => _apply(p.decision.recipe)),
          ),
        if (ref.watch(availableModelsProvider).contains(bundledDetector)) ...[
          preset(BuiltinPreset.portrait, Icons.face_outlined),
          preset(BuiltinPreset.oldPhoto, Icons.filter_b_and_w_outlined),
        ],
        _Tool(
          text: choice == null ? '' : scaleLabel(l10n, choice.scale, fast2: choice.fastPath),
          label: l10n.editorScale,
          onTap: () => _scaleSheet(l10n),
        ),
        _Tool(
          icon: Icons.tune,
          label: l10n.editorAdjust,
          onTap: () => setState(() => _adjusting = true),
        ),
      ],
    );
  }

  /// A preset or a mode; one that needs a model the device does not have offers the Models
  /// screen (FR-ONB-003: the face model when it is first wanted).
  Future<void> _choose(Recipe r, AppLocalizations l10n) async {
    final available = ref.read(availableModelsProvider);
    if (canRun(r, available)) {
      setState(() => _apply(r));
      return;
    }
    final face = r.faceModel != null && !available.contains(r.faceModel);
    final open = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                face ? l10n.faceOfferTitle : l10n.presetModelMissing,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (face) ...[const SizedBox(height: 8), Text(l10n.faceOfferBody)],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.faceOfferOpen),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.faceOfferLater),
              ),
            ],
          ),
        ),
      ),
    );
    if (open == true && mounted) await context.push('/models');
  }

  /// The scales this photo can take (ADR-0014; 8x on T2 for a small input).
  Future<void> _scaleSheet(AppLocalizations l10n) async {
    final picked = await showModalBottomSheet<ScaleChoice>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<ScaleChoice>(
          groupValue: _choice,
          onChanged: (c) => Navigator.pop(context, c),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in ScaleChoice.values)
                if (c != ScaleChoice.x8 || _x8Allowed || _choice == c)
                  RadioListTile<ScaleChoice>(
                    value: c,
                    title: Text(scaleLabel(l10n, c.scale, fast2: c.fastPath)),
                    subtitle: c == ScaleChoice.x1 ? Text(l10n.scaleX1Hint) : null,
                  ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _choice = picked);
  }

  /// "Настроить" (06 §3.2): the other presets, the model, denoise, faces and the S9 stages, in
  /// place of the mode bar; the photo stays in view.
  Widget _adjustPanel(AppLocalizations l10n) {
    final user = ref.watch(presetsProvider).value ?? const <Preset>[];
    final strength = _strength != 1
        ? Text(
            l10n.presetStrengthAfter(l10n.strengthValue((_strength * 100).round())),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.editorAdjust, style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => setState(() => _adjusting = false),
              child: Text(l10n.editorDone),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: ListView(
            shrinkWrap: true,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final b in [BuiltinPreset.fast, BuiltinPreset.quality, BuiltinPreset.anime])
                    ChoiceChip(
                      label: Text(builtinPresetLabel(l10n, b)),
                      selected: _matches(b.recipe),
                      onSelected: (_) => _choose(b.recipe, l10n),
                    ),
                  for (final p in user)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: _matches(p.recipe),
                      onSelected: (_) => _choose(p.recipe, l10n),
                    ),
                ],
              ),
              ?_srModel(l10n),
              ?_denoise(l10n),
              _facesControls(l10n),
              _jpegControl(l10n),
              _lowLightControl(l10n),
              _scratchesControl(l10n),
              ?strength,
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _enhance(EnhanceController ctl, Recipe r, AppLocalizations l10n) async {
    if (r.faceModel != null && !await _faceNotice(l10n)) return;
    if (!mounted) return;
    await ctl.start(widget.input, r, facesOff: r.faceModel == null ? const [] : _facesOff.toList());
  }

  // Stages whose progress is a fraction (the others show an indeterminate bar).
  static const _determinate = {JobStage.upscale, JobStage.faces, JobStage.jpeg, JobStage.scratches};

  Widget _progress(Running s, EnhanceController ctl, AppLocalizations l10n) {
    final eta = s.eta;
    final percent = (s.progress * 100).round();
    final label = switch (s.stage) {
      JobStage.queued => l10n.stageWaiting,
      JobStage.decode => l10n.stageReading,
      JobStage.faces => l10n.stageFaces(percent),
      JobStage.jpeg => l10n.stageJpeg(percent),
      JobStage.scratches => l10n.stageScratches(percent),
      JobStage.lowLight => l10n.stageLowLight,
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
                LinearProgressIndicator(value: _determinate.contains(s.stage) ? s.progress : null),
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

  /// The result (06 §3.2): the comparison above, Save here, the rest in the "…" menu.
  Widget _finished(Finished s, EnhanceController ctl, AppLocalizations l10n) {
    final busy = s.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8)],
        FilledButton(
          onPressed: busy ? null : () => _save(() => ctl.saveToGallery(), l10n.savedToGallery),
          child: Text(l10n.editorSave),
        ),
      ],
    );
  }

  /// FR-ENH-005: the blend with the original, from the "…" menu.
  Future<void> _strengthSheet(AppLocalizations l10n) async {
    // The input is the blend base below 100% strength.
    final hasOriginal = ref.read(fileExistsProvider(widget.input)).value ?? false;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final s = ref.watch(enhanceProvider);
            if (s is! Finished) return const SizedBox.shrink();
            final ctl = ref.read(enhanceProvider.notifier);
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(l10n.strength),
                      Expanded(
                        child: Slider(
                          value: s.strength,
                          divisions: 20,
                          label: l10n.strengthValue((s.strength * 100).round()),
                          semanticFormatterCallback: (v) => l10n.strengthValue((v * 100).round()),
                          onChanged: hasOriginal && !s.saving ? ctl.setStrength : null,
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          l10n.strengthValue((s.strength * 100).round()),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  if (!hasOriginal)
                    Text(
                      l10n.strengthNeedsOriginal,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// FR-CMP-007 (06 §1.1): size, model, processor and time on request.
  Future<void> _details(Finished s, AppLocalizations l10n) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.resultDetails),
      content: Text(
        '${l10n.sizePx(s.result.width, s.result.height)}\n${resultInfo(l10n, s.result)}',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close))],
    ),
  );

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
        messenger.showSnackBar(SnackBar(content: Text(l10n.formatTooLarge)));
      } else {
        showError(messenger, l10n, 'save', e, stack, l10n.saveFailed);
      }
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'save', e, stack, l10n.saveFailed);
    }
  }

  Future<void> _saveAs(Finished s, EnhanceController ctl, AppLocalizations l10n) async {
    final mp = s.result.width * s.result.height / 1e6;
    final heic = await ref.read(heicSupportedProvider.future);
    if (!mounted) return;
    final format = await showModalBottomSheet<ExportFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n.saveAsTitle)),
            for (final f in availableFormats(heic: heic))
              ListTile(
                title: Text(formatLabel(l10n, f)),
                subtitle: mp > f.maxMegapixels ? Text(formatTooLargeLabel(l10n, f)) : null,
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
    // FR-IMP-006 (input over the limit) or FR-ENH-014 (out of memory, 06 §3.5).
    final oom = e.code == 'oom_downscale';
    final current = scaleLabel(
      l10n,
      (e.payload['scale'] as num?)?.toInt() ?? 4,
      fast2: e.payload['fast2'] == true,
    );
    final picked = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(oom ? l10n.oomTitle : l10n.tooLargeTitle),
        content: Text(oom ? l10n.oomBody(current) : l10n.tooLargeBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          for (final o in opts)
            TextButton(
              onPressed: () => Navigator.pop(context, o),
              child: Text(
                o['background'] == 'lanczos'
                    ? l10n.regionFaces
                    : scaleLabel(
                        l10n,
                        (o['scale'] as num?)?.toInt() ?? 4,
                        fast2: o['fast2'] == true,
                      ),
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

/// A tool of the editor's bottom bar: an icon (or a short text such as "4×") over its label.
class _Tool extends StatelessWidget {
  const _Tool({
    this.icon,
    this.text,
    required this.label,
    this.selected = false,
    this.busy = false,
    required this.onTap,
  });

  final IconData? icon;
  final String? text;
  final String label;
  final bool selected, busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onTap == null
        ? scheme.onSurface.withValues(alpha: 0.38)
        : selected
        ? scheme.primary
        : scheme.onSurface;
    final glyph = busy
        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : icon != null
        ? Icon(icon, color: color)
        : Text(
            text ?? '',
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 16),
          );
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 24, child: Center(child: glyph)),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
