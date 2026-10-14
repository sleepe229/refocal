import 'package:flutter/material.dart';
import 'package:refocal_core/refocal_core.dart';

import '../../l10n/app_localizations.dart';

/// Asks for a preset name (FR-PRE-002): the trimmed name, or null when cancelled.
Future<String?> showPresetNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _PresetNameDialog(title: title, initial: initial),
);

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.title, required this.initial});
  final String title, initial;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid => Preset.isValidName(_text.text);

  void _submit() {
    if (_valid) Navigator.pop(context, Preset.validName(_text.text));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.presetName,
          errorText: _text.text.trim().length > Preset.maxNameLength
              ? l10n.presetNameTooLong(Preset.maxNameLength)
              : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(onPressed: _valid ? _submit : null, child: Text(l10n.presetSave)),
      ],
    );
  }
}
