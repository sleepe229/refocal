/// Status codes of the native core (`enh_status` in native/include/enh.h).
///
/// The ABI returns plain int32 codes. A code this build does not know (newer core, older
/// Dart) maps to [EnhStatus.internal] instead of throwing (S6, ADR-0005).
enum EnhStatus {
  ok(0),
  cancelled(1),
  paused(2),
  oom(3),
  backend(4),
  deviceLost(5),
  io(6),
  diskFull(7),
  model(8),
  invalid(9),
  numeric(10),
  signature(11),
  limit(12),
  internal(99);

  const EnhStatus(this.code);

  final int code;

  static EnhStatus fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return internal;
  }
}

/// A non-ok status returned by the native core.
class EnhException implements Exception {
  EnhException(this.status, [this.context]);

  final EnhStatus status;
  final String? context;

  @override
  String toString() => 'EnhException(${status.name}${context == null ? '' : ', $context'})';
}
