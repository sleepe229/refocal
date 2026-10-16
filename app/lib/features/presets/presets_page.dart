import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/presets.dart';
import '../../l10n/app_localizations.dart';
import '../../ui_kit/labels.dart';
import '../../ui_kit/errors.dart';
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
      appBar: AppBar(
        title: Text(l10n.presetsTitle),
        actions: [
          IconButton(
            tooltip: l10n.presetsImport,
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () => _import(context, ref, l10n),
          ),
          IconButton(
            tooltip: l10n.presetsExport,
            icon: const Icon(Icons.save_alt),
            onPressed: (presets.value ?? const []).isEmpty
                ? null
                : () => _export(context, ref, l10n, presets.value!),
          ),
        ],
      ),
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

  /// FR-PRE-003: your presets to a file the user picks.
  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<Preset> presets,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final engine = await ref.read(engineProvider.future);
      final dir = await Directory('${engine.dirs.cache}/export').create(recursive: true);
      final f = File('${dir.path}/refocal-presets.json');
      await f.writeAsString(PresetFile.encode(presets), flush: true);
      final uri = await ref
          .read(platformApiProvider)
          .saveToFile(f.path, 'refocal-presets.json', 'application/json');
      await f.delete();
      if (uri != null) messenger.showSnackBar(SnackBar(content: Text(l10n.presetsExported)));
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'export presets', e, stack, l10n.presetSaveFailed);
    }
  }

  /// FR-PRE-003: presets from a file (checked whole before anything is added).
  Future<void> _import(BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    String? path;
    try {
      final engine = await ref.read(engineProvider.future);
      path = await ref
          .read(platformApiProvider)
          .pickFile('${engine.dirs.cache}/import', _maxFileBytes);
      if (path == null) return;
      final read = PresetFile.decode(await File(path).readAsString());
      final repo = await ref.read(presetRepositoryProvider.future);
      final n = await repo.importAll(read);
      messenger.showSnackBar(SnackBar(content: Text(l10n.presetsImported(n))));
    } on FormatException catch (e) {
      AppLog.warn('import presets: ${e.message}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.presetsNotAFile)));
    } on PlatformException catch (e) {
      AppLog.warn('import presets: ${e.code}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.presetsNotAFile)));
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'import presets', e, stack, l10n.presetSaveFailed);
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          // in the cache: cleared with it
        }
      }
    }
  }

  static const _maxFileBytes = 1 << 20;

  Future<void> _rename(BuildContext context, WidgetRef ref, AppLocalizations l10n, Preset p) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showPresetNameDialog(context, title: l10n.presetRename, initial: p.name);
    if (name == null) return;
    try {
      await (await ref.read(presetRepositoryProvider.future)).rename(p.id, name);
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'change preset', e, stack, l10n.presetSaveFailed);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AppLocalizations l10n, Preset p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await (await ref.read(presetRepositoryProvider.future)).remove(p.id);
    } on Exception catch (e, stack) {
      showError(messenger, l10n, 'change preset', e, stack, l10n.presetSaveFailed);
    }
  }
}
