import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/l10n/app_localizations_en.dart';
import 'package:refocal/ui_kit/errors.dart';
import 'package:refocal_core/refocal_core.dart';

void main() {
  final l10n = AppLocalizationsEn();
  const secret = '/data/user/0/io.github.refocal.app/no_backup/inbox/in-1.jpg';

  test('error reasons are localized and never carry the exception text (PRIV-LOG-001)', () {
    final reasons = {
      EnhException(EnhStatus.diskFull, secret): l10n.failDiskFull,
      const FileSystemException('cannot delete', secret, OSError('No space', 28)):
          l10n.failDiskFull,
      const FileSystemException('cannot delete', secret): l10n.errorStorage,
      PlatformException(code: 'limit', message: secret): l10n.failLimit,
      PlatformException(code: 'busy', message: secret): l10n.errorSystem,
      const FormatException(secret): l10n.errorUnexpected,
    };
    for (final MapEntry(key: e, value: want) in reasons.entries) {
      final got = errorReason(l10n, e);
      expect(got, want, reason: '$e');
      expect(got, isNot(contains('/data')));
    }
  });
}
