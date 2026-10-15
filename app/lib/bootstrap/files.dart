import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [path] exists, checked off the build: widgets watch this instead of calling
/// `existsSync` while building. Invalidate it after deleting the file.
final fileExistsProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, path) => File(path).exists(),
);

/// Deletes [path] if it is there. Best effort: a file that cannot be deleted now is an orphan
/// the startup sweeps remove (JobStore.sweep, HistoryStore.sweep).
Future<void> deleteIfPresent(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // gone already, or retried by the sweep
  }
}
