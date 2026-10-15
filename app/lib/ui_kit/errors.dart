import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:refocal_core/refocal_core.dart';

import '../bootstrap/app_log.dart';
import '../l10n/app_localizations.dart';

/// What a failed job or call means for the user (06 §3.5).
String statusText(AppLocalizations l10n, EnhStatus s) => switch (s) {
  EnhStatus.cancelled => l10n.failCancelled,
  EnhStatus.paused => l10n.failPaused,
  EnhStatus.diskFull => l10n.failDiskFull,
  EnhStatus.invalid => l10n.failInvalid,
  EnhStatus.limit => l10n.failLimit,
  EnhStatus.oom => l10n.failOom,
  _ => l10n.failOther(s.name),
};

const _enospc = 28; // Linux/Android errno; iOS reports it the same way (BSD)

/// A short localized reason for [e]. Never the exception's own text: it may hold paths, URIs
/// or SQL (PRIV-LOG-001); that goes to the log, which the core redacts.
String errorReason(AppLocalizations l10n, Object e) => switch (e) {
  EnhException(:final status) => statusText(l10n, status),
  FileSystemException(osError: OSError(errorCode: _enospc)) => l10n.failDiskFull,
  FileSystemException() => l10n.errorStorage,
  PlatformException(code: 'limit') => l10n.failLimit,
  PlatformException() => l10n.errorSystem,
  _ => l10n.errorUnexpected,
};

/// Logs [e] as the failure of [what] and shows [message] with its [errorReason]. Takes the
/// messenger and strings, not a context: callers capture them before their first await.
void showError(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  String what,
  Object e,
  StackTrace stack,
  String Function(String reason) message,
) {
  AppLog.error(what, e, stack);
  messenger.showSnackBar(SnackBar(content: Text(message(errorReason(l10n, e)))));
}

/// The reason of a failed queue job: its `errorCode` (an [EnhStatus] name, "cancelled" or
/// "internal", see QueueOrchestrator).
String failureReason(AppLocalizations l10n, String? code) =>
    switch (EnhStatus.values.asNameMap()[code]) {
      final s? => statusText(l10n, s),
      null when code == JobFailed.cancelled => l10n.failCancelled,
      null => l10n.errorUnexpected,
    };
