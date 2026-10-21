import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_platform/refocal_platform.dart';

import 'app_log.dart';
import 'engine.dart';
import 'settings.dart';

/// The processing notification and foreground service (ADR-0019, FR-BATCH-004), shared by
/// everything that processes: the editor's job and the queue. The service runs while at least
/// one of them holds it; the notification shows the one that updated last. Its Pause/Cancel
/// actions reach every holder (ProcessingActions).
///
/// Platform calls are conveniences: processing never depends on them, so a refusal (e.g.
/// ForegroundServiceStartNotAllowedException, no activity for the permission dialog) is logged
/// and processing goes on.
class ForegroundWork {
  ForegroundWork(this._api, this._texts);

  final RefocalPlatformApi _api;
  final ProcessingTexts Function() _texts;
  final _holders = <Object>{};
  Completer<void>? _idle;

  /// Something is processing (the app update waits for it, FR-UPD-004).
  bool get busy => _holders.isNotEmpty;

  /// Completes once nothing processes.
  Future<void> idle() => busy ? (_idle ??= Completer<void>()).future : Future.value();

  /// [holder] starts processing; call while the app is in the foreground (a user action).
  Future<void> acquire(Object holder) async {
    final first = _holders.isEmpty;
    _holders.add(holder);
    if (!first) return;
    await _call('notification permission', _api.requestNotificationPermission);
    await _call('start processing', () => _api.startProcessing(_texts()));
  }

  /// [text] e.g. "40%" or "2 of 5 · 40%"; [percent] 0..100, or -1 for indeterminate.
  Future<void> update(Object holder, String text, int percent) async {
    if (!_holders.contains(holder)) return;
    await _call('update processing', () => _api.updateProcessing(text, percent));
  }

  /// [holder] is done; the last one stops the service. [finishedText] is left as a tappable
  /// notification when the app is in the background, if nothing else is still processing.
  Future<void> release(Object holder, String? finishedText) async {
    if (!_holders.remove(holder) || _holders.isNotEmpty) return;
    _idle?.complete();
    _idle = null;
    await _call('stop processing', () => _api.stopProcessing(finishedText));
  }

  static Future<void> _call(String what, FutureOr<Object?> Function() f) async {
    try {
      await f();
    } on PlatformException catch (e) {
      AppLog.warn('$what: ${e.code}');
    }
  }
}

final foregroundWorkProvider = Provider<ForegroundWork>((ref) {
  return ForegroundWork(ref.watch(platformApiProvider), () {
    final l10n = ref.read(l10nProvider);
    return ProcessingTexts(
      title: l10n.notifEnhancing,
      pause: l10n.pause,
      cancel: l10n.cancel,
      timedOut: l10n.notifTimedOut,
      channelName: l10n.notifChannelName,
      channelDescription: l10n.notifChannelDescription,
    );
  });
});
