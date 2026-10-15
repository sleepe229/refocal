import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/models.dart';
import '../../bootstrap/presets.dart';
import '../../bootstrap/settings.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';

/// Batch sheet (06 §3.4): one preset for all photos (FR-BATCH-002) and whether each result is
/// saved when it is done (FR-BATCH-006). Returns the recipe, with `output` set for autosave;
/// null when dismissed.
Future<Recipe?> showBatchSheet(BuildContext context, int count) => showModalBottomSheet<Recipe>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _BatchSheet(count: count),
);

class _BatchSheet extends ConsumerStatefulWidget {
  const _BatchSheet({required this.count});
  final int count;

  @override
  ConsumerState<_BatchSheet> createState() => _BatchSheetState();
}

class _BatchSheetState extends ConsumerState<_BatchSheet> {
  Recipe _recipe = BuiltinPreset.fast.recipe; // ADR-0014: the safe default for any size
  bool? _autosave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value ?? const Settings();
    final autosave = _autosave ?? settings.batchAutosave;
    // Presets of models the device has (bundled or installed packs).
    final available = ref.watch(availableModelsProvider);
    final user = [
      for (final p in ref.watch(presetsProvider).value ?? const <Preset>[])
        if (canRun(p.recipe, available)) p,
    ];
    Widget chip(String label, Recipe r) => ChoiceChip(
      label: Text(label),
      selected: _recipe == r,
      onSelected: (_) => setState(() => _recipe = r),
    );
    // Scrolls: with large text (A11Y-GEN-004) the sheet is taller than the screen allows.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.batchTitle(widget.count), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(l10n.batchPreset, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final b in BuiltinPreset.values)
                  if (canRun(b.recipe, available)) chip(builtinPresetLabel(l10n, b), b.recipe),
                for (final p in user) chip(p.name, p.recipe),
              ],
            ),
            const SizedBox(height: 4),
            Text(recipeLabel(l10n, _recipe), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.batchAutosave(formatLabel(l10n, settings.format))),
              subtitle: autosave ? null : Text(l10n.batchAutosaveOff),
              value: autosave,
              onChanged: (v) => setState(() => _autosave = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                _recipe.copyWith(
                  output: () =>
                      autosave ? OutputSpec(settings.format, quality: settings.quality) : null,
                ),
              ),
              icon: const Icon(Icons.playlist_add),
              label: Text(l10n.batchAdd),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aiDisclaimer,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
