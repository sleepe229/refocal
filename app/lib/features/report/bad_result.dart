import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import '../../bootstrap/app_log.dart';
import '../../bootstrap/engine.dart';
import '../../bootstrap/tier.dart';
import '../../l10n/app_localizations.dart';
import '../about/about_page.dart' show sourceUrl;

/// The categories of 15 §5 (the monthly review sorts reports by them).
enum BadResultKind { otherFace, artifacts, color, bias, other }

/// FR-REP-002: what a bad-result report says. No photo and no paths: the parameters, the
/// model, the backend and the device only.
String badResultBody({
  required BadResultKind kind,
  required String comment,
  required String app,
  required String os,
  required String device,
  required String tier,
  required JobResult result,
  required JobRequest? request,
}) {
  final r = request;
  return [
    '**Category:** ${kind.name}',
    if (comment.trim().isNotEmpty) '\n${comment.trim()}\n',
    '| | |',
    '|---|---|',
    '| App | Refocal $app |',
    '| OS | $os |',
    '| Device | $device ($tier) |',
    '| Model | ${result.model} |',
    '| Mode | ${result.scale}x${result.fast2 ? ' fast' : ''} |',
    if (r?.faceModel case final f?) ...[
      '| Faces | $f, strength ${(r!.faceStrength * 100).round()}%'
          '${r.facesOnly ? ', only faces' : ''}${r.facesOff.isEmpty ? '' : ', ${r.facesOff.length} off'} |',
    ],
    '| Backend | ${result.backend} |',
    if (result.fallbacks.isNotEmpty) '| Fallbacks | ${result.fallbacks.join(', ')} |',
    '| Input | ${result.inputWidth}x${result.inputHeight} |',
    '| Output | ${result.width}x${result.height} |',
    if (result.duration case final d?) '| Time | ${d.inMilliseconds} ms |',
    '',
    '_No photo attached. Attach one only if you are sure it can be public._',
  ].join('\n');
}

/// The pre-filled issue (label bad-result, 15 §5).
Uri badResultIssue(BadResultKind kind, String body) => Uri.parse('$sourceUrl/issues/new').replace(
  queryParameters: {'labels': 'bad-result', 'title': 'Bad result: ${kind.name}', 'body': body},
);

/// FR-REP-001..003 (COMP-AND-008): category and comment, the full text shown before anything
/// leaves the phone, then a GitHub issue opened in the browser. The photo goes only by a
/// separate, explicit share after a warning that issues are public.
Future<void> showBadResultReport(BuildContext context, JobResult result) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => _BadResultSheet(result),
);

class _BadResultSheet extends ConsumerStatefulWidget {
  const _BadResultSheet(this.result);
  final JobResult result;

  @override
  ConsumerState<_BadResultSheet> createState() => _BadResultSheetState();
}

class _BadResultSheetState extends ConsumerState<_BadResultSheet> {
  var _kind = BadResultKind.artifacts;
  final _comment = TextEditingController();
  late final Future<({String app, String os, String device, String tier, JobRequest? request})>
  _context = _read();

  Future<({String app, String os, String device, String tier, JobRequest? request})> _read() async {
    final engine = await ref.read(engineProvider.future);
    String device = 'unknown';
    try {
      final info = await ref.read(platformApiProvider).deviceInfo();
      device =
          '${info.soc ?? 'unknown SoC'}, ${(info.totalRamBytes / (1 << 30)).toStringAsFixed(1)} GB';
    } on PlatformException catch (e) {
      AppLog.warn('device info: ${e.code}');
    }
    JobRequest? request;
    try {
      final j = await File('${widget.result.jobDir}/request.json').readAsString();
      request = JobRequest.fromJson((jsonDecode(j) as Map).cast<String, Object?>());
    } on Exception catch (e) {
      AppLog.warn('report request: ${e.runtimeType}');
    }
    final tier = ref.read(tierProvider).value?.tier.label ?? '?';
    return (
      app: engine.version,
      os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      device: device,
      tier: tier,
      request: request,
    );
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String _body(({String app, String os, String device, String tier, JobRequest? request}) c) =>
      badResultBody(
        kind: _kind,
        comment: _comment.text,
        app: c.app,
        os: c.os,
        device: c.device,
        tier: c.tier,
        result: widget.result,
        request: c.request,
      );

  Future<void> _open(String body) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(platformApiProvider).openUrl(badResultIssue(_kind, body).toString());
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      AppLog.warn('open issue: ${e.code}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.reportNoBrowser)));
    }
  }

  /// FR-REP-003: the photo only by this explicit action, after the warning.
  Future<void> _sharePhoto() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.reportPhotoTitle),
        content: Text(l10n.reportPhotoBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.reportPhotoOk),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final engine = await ref.read(engineProvider.future);
    final dir = await Directory('${engine.dirs.cache}/share').create(recursive: true);
    final copy = await File(widget.result.previewPath).copy('${dir.path}/refocal-result.jpg');
    await ref.read(platformApiProvider).shareFile(copy.path, 'image/jpeg', l10n.reportPhotoOk);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      BadResultKind.otherFace: l10n.badOtherFace,
      BadResultKind.artifacts: l10n.badArtifacts,
      BadResultKind.color: l10n.badColor,
      BadResultKind.bias: l10n.badBias,
      BadResultKind.other: l10n.badOther,
    };
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: FutureBuilder(
          future: _context,
          builder: (context, snap) {
            final c = snap.data;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.reportBadTitle, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final k in BadResultKind.values)
                        ChoiceChip(
                          label: Text(labels[k]!),
                          selected: _kind == k,
                          onSelected: (_) => setState(() => _kind = k),
                        ),
                    ],
                  ),
                  TextField(
                    controller: _comment,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: l10n.reportComment),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (c == null)
                    const LinearProgressIndicator()
                  else ...[
                    Text(l10n.reportWillSend, style: Theme.of(context).textTheme.bodySmall),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(8),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _body(c),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _open(_body(c)),
                      icon: const Icon(Icons.open_in_browser),
                      label: Text(l10n.reportOpenIssue),
                    ),
                    TextButton.icon(
                      onPressed: _sharePhoto,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(l10n.reportSharePhoto),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
