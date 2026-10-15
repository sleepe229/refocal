import 'package:flutter/foundation.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

/// The app's side of the bug-report log (FR-SET-007, PRIV-LOG-001..004). Lines go through the
/// native core: one file with the core's own lines, one rotation, and the core redacts paths
/// and URIs before writing. Callers still log parameters, never file names or photo metadata.
class AppLog {
  AppLog._();

  static RefocalNative? _native;
  static String? _path;

  /// Bounded by PRIV-LOG-002: two files of 2 MB.
  static const maxBytes = 2 << 20;

  /// Current file and the rotated one, oldest first; null before [open].
  static List<String> get files => [
    if (_path != null) ...['$_path.1', _path!],
  ];

  /// [logsDir] must exist.
  static void open(RefocalNative native, String logsDir) {
    final path = '$logsDir/refocal.log';
    native.openLog(path, maxBytes: maxBytes);
    native.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.info); // PRIV-LOG-002
    _native = native;
    _path = path;
  }

  static void debug(String message) => _write(LogLevel.debug, message);
  static void info(String message) => _write(LogLevel.info, message);
  static void warn(String message) => _write(LogLevel.warn, message);

  static void error(String message, [Object? error, StackTrace? stack]) {
    final b = StringBuffer(message);
    if (error != null) b.write(': ${error.runtimeType}: $error');
    if (stack != null) b.write('\n$stack');
    _write(LogLevel.error, b.toString());
  }

  static void _write(LogLevel level, String message) {
    final n = _native;
    if (n != null) {
      n.log(level, message);
    } else if (kDebugMode) {
      debugPrint('[${level.name}] $message'); // before the core is loaded
    }
  }

  /// PRIV-LOG-004: uncaught Flutter and platform errors end up in the log.
  static void installErrorHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error('Flutter error', details.exception, details.stack);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (e, stack) {
      error('Uncaught error', e, stack);
      return false; // keep the default handling (and crash reporting in debug)
    };
  }
}
