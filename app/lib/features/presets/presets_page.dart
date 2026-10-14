import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/presets.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';
import 'preset_name_dialog.dart';

/// Built-in and user presets (FR-PRE-001/002): user presets are renamed and deleted here and
/// saved from the editor.
class PresetsPage extends ConsumerWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final presets = ref.watch(presetsProvider);
    final header = Theme.of(context).textTheme.titleSmall;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.presetsTitle)),
      body: ListView(
        children: [
          ListTile(title: Text(l10n.presetsBuiltin, style: header)),
          for (final b in BuiltinPreset.values)
            ListTile(
              title: Text(builtinPresetLabel(l10n, b)),
              subtitle: Text(recipeLabel(l10n, b.recipe)),
            ),
          const Divider(),
          ListTile(title: Text(l10n.presetsYours, style: header)),
          ...presets.when(
            loading: () => const [Center(child: CircularProgressIndicator())],
            error: (e, _) => [ListTile(title: Text('$e'))],
            data: (list) => list.isEmpty
                ? [ListTile(subtitle: Text(l10n.presetsEmpty))]
                : [for (final p in list) _tile(context, ref, l10n, p)],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, AppLocalizations l10n, Preset p) => ListTile(
    title: Text(p.name),
    subtitle: Text(recipeLabel(l10n, p.recipe)),
    trailing: PopupMenuButton<bool>(
      onSelected: (rename) =>
          rename ? _rename(context, ref, l10n, p) : _delete(context, ref, l10n, p),
      itemBuilder: (_) => [
        PopupMenuItem(value: true, child: Text(l10n.presetRename)),
        PopupMenuItem(value: false, child: Text(l10n.deleteTooltip)),
      ],
    ),
  );

  Future<void> _rename(BuildContext context, WidgetRef ref, AppLocalizations l10n, Preset p) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showPresetNameDialog(context, title: l10n.presetRename, initial: p.name);
    if (name == null) return;
    try {
      await (await ref.read(presetRepositoryProvider.future)).rename(p.id, name);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.presetSaveFailed('$e'))));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AppLocalizations l10n, Preset p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await (await ref.read(presetRepositoryProvider.future)).remove(p.id);
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.presetSaveFailed('$e'))));
    }
  }
}
