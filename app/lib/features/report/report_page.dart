import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../l10n/app_localizations.dart';
import '../../version.dart';

/// "Report a problem" (FR-SET-007, FR-REP-004): the log is shown in full before anything leaves
/// the phone, and is sent only by the user, through the share sheet (PRIV-LOG-003).
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  late final Future<List<String>> _lines = _read();

  static Future<List<String>> _read() async {
    final out = <String>[];
    for (final path in AppLog.files) {
      final f = File(path);
      if (await f.exists()) out.addAll(await f.readAsLines());
    }
    return out;
  }

  Future<void> _share(List<String> lines) async {
    final l10n = AppLocalizations.of(context);
    final engine = await ref.read(engineProvider.future);
    final dir = Directory('${engine.dirs.cache}/share')..createSync(recursive: true);
    final file = File('${dir.path}/refocal-log.txt');
    await file.writeAsString('Refocal $appVersion\n${lines.join('\n')}\n', flush: true);
    await ref.read(platformApiProvider).shareFile(file.path, 'text/plain', l10n.reportShareTitle);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: FutureBuilder<List<String>>(
        future: _lines,
        builder: (context, snap) {
          final lines = snap.data;
          if (lines == null) return const Center(child: CircularProgressIndicator());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.all(16), child: Text(l10n.reportIntro)),
              Expanded(
                child: lines.isEmpty
                    ? Center(child: Text(l10n.reportEmpty))
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: SelectionArea(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: lines.length,
                            itemBuilder: (_, i) => Text(
                              lines[i],
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                          ),
                        ),
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: lines.isEmpty ? null : () => _share(lines),
                    icon: const Icon(Icons.share),
                    label: Text(l10n.reportShare),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
