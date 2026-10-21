import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../bootstrap/models.dart';
import '../../l10n/app_localizations.dart';
import '../editor/editor_page.dart';

/// The photo whose editor asked for the models downloading now (06 §3.3): the banner takes
/// the user back to it, with the settings that wanted them.
class DownloadOrigin extends Notifier<({List<String> packs, EditorArgs args})?> {
  @override
  ({List<String> packs, EditorArgs args})? build() => null;

  void set(List<String> packs, EditorArgs args) => state = (packs: packs, args: args);

  /// Clears the origin if it still is the one for [packs].
  void clear([List<String>? packs]) {
    if (packs == null || identical(state?.packs, packs)) state = null;
  }
}

final downloadOriginProvider =
    NotifierProvider<DownloadOrigin, ({List<String> packs, EditorArgs args})?>(DownloadOrigin.new);

/// Downloads the user left the screen of (the editor, the Models screen show their own
/// progress): a small bar at the bottom, over no content (the pages get its height as
/// padding). It shows the progress while models download, "ready" for a few seconds once all
/// of them are installed, and nothing after a failure or a cancel (the editor's offer reports
/// those). Closed by the user, it stays away until another model starts downloading. A tap
/// opens the photo the models were asked for, else the Models screen.
class DownloadBanner extends ConsumerStatefulWidget {
  const DownloadBanner({super.key, required this.router, required this.child});
  final GoRouter router;
  final Widget child;

  /// Screens that show the downloads themselves.
  static const ownProgress = {'/editor', '/models'};

  /// How long "ready" stays.
  static const doneFor = Duration(seconds: 4);

  @override
  ConsumerState<DownloadBanner> createState() => _DownloadBannerState();
}

class _DownloadBannerState extends ConsumerState<DownloadBanner> {
  /// The packs of this round of downloads (from the first start to the last end).
  final _round = <String>{};
  bool _closed = false;
  bool _done = false;
  bool _ending = false;
  Timer? _doneTimer;
  late String _location = _where();

  String _where() {
    try {
      return widget.router.state.matchedLocation;
    } on Object {
      return '/'; // no route yet
    }
  }

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_routed);
    ref.listenManual(modelsProvider, (_, next) => _downloads(next.value?.downloads.keys));
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_routed);
    _doneTimer?.cancel();
    super.dispose();
  }

  void _routed() {
    final at = _where();
    if (at == _location) return;
    setState(() => _location = at);
    if (DownloadBanner.ownProgress.contains(at) && _done) _finish();
  }

  void _downloads(Iterable<String>? active) {
    final now = {...?active};
    if (now.difference(_round).isNotEmpty) {
      // A model started: shown again even if the bar was closed.
      _doneTimer?.cancel();
      setState(() {
        _round.addAll(now);
        _closed = _done = false;
      });
      return;
    }
    if (now.isEmpty && _round.isNotEmpty && !_done && !_ending) unawaited(_ended());
  }

  /// The round is over: "ready" if every pack of it is installed (the database has them before
  /// the download leaves the list), else quietly away.
  Future<void> _ended() async {
    final round = {..._round};
    _ending = true;
    final Set<String> installed;
    try {
      // A new query: the provider's last value may be from before the install.
      installed = {for (final p in await ref.refresh(installedPacksProvider.future)) p.id};
    } finally {
      _ending = false;
    }
    if (!mounted ||
        !setEquals(round, _round) ||
        (ref.read(modelsProvider).value?.downloads.isNotEmpty ?? false)) {
      return; // another download started meanwhile
    }
    if (!round.every(installed.contains) || DownloadBanner.ownProgress.contains(_location)) {
      return _finish();
    }
    setState(() => _done = true);
    _doneTimer = Timer(DownloadBanner.doneFor, _finish);
  }

  void _finish() {
    _doneTimer?.cancel();
    if (!mounted) return;
    ref.read(downloadOriginProvider.notifier).clear();
    setState(() {
      _round.clear();
      _done = _closed = false;
    });
  }

  void _close() {
    if (_done) return _finish();
    setState(() => _closed = true);
  }

  void _open() {
    final origin = ref.read(downloadOriginProvider);
    if (_done) _finish();
    if (origin != null) {
      ref.read(downloadOriginProvider.notifier).clear();
      unawaited(widget.router.push('/editor', extra: origin.args));
    } else {
      unawaited(widget.router.push('/models'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(modelsProvider).value?.downloads ?? const {};
    ref.watch(installedPacksProvider); // listened, so that [_ended]'s query runs
    final visible =
        _round.isNotEmpty &&
        !_closed &&
        (_done || downloads.isNotEmpty) &&
        !DownloadBanner.ownProgress.contains(_location);
    final media = MediaQuery.of(context);
    final bar = visible ? _bar(context, downloads) : null;
    return Stack(
      children: [
        MediaQuery(
          data: bar == null
              ? media
              : media.copyWith(
                  padding: media.padding.copyWith(bottom: media.padding.bottom + _height),
                  viewPadding: media.viewPadding.copyWith(
                    bottom: media.viewPadding.bottom + _height,
                  ),
                ),
          child: widget.child,
        ),
        if (bar != null) Positioned(left: 0, right: 0, bottom: media.padding.bottom, child: bar),
      ],
    );
  }

  static const _height = 64.0;

  Widget _bar(BuildContext context, Map<String, PackProgress> downloads) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    var done = 0, total = 0;
    for (final p in downloads.values) {
      done += p.done;
      total += p.total;
    }
    final fraction = total == 0 ? null : done / total;
    final back = ref.watch(downloadOriginProvider) != null;
    final text = _done ? l10n.bannerDone : l10n.bannerDownloading(((fraction ?? 0) * 100).floor());
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Dismissible(
          key: const ValueKey('download-banner'),
          direction: DismissDirection.down,
          onDismissed: (_) => _close(),
          child: Material(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _open,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(
                          _done ? Icons.check_circle_outline : Icons.download,
                          size: 20,
                          color: scheme.onInverseSurface,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onInverseSurface),
                            ),
                          ),
                        ),
                        if (back)
                          TextButton(
                            onPressed: _open,
                            child: Text(
                              l10n.bannerBackToPhoto,
                              style: TextStyle(color: scheme.inversePrimary),
                            ),
                          ),
                        // No tooltip: the bar is above the navigator's Overlay.
                        Semantics(
                          label: l10n.close,
                          button: true,
                          excludeSemantics: true,
                          child: IconButton(
                            icon: Icon(Icons.close, size: 20, color: scheme.onInverseSurface),
                            onPressed: _close,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_done)
                    LinearProgressIndicator(
                      value: fraction,
                      minHeight: 2,
                      color: scheme.inversePrimary,
                      backgroundColor: Colors.transparent,
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
