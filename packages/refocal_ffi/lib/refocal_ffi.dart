/// Thin bridge to the Refocal native core (native/include/enh.h).
///
/// Job events will arrive through a native port (`enh_job_start_port`, ADR-0005); the
/// skeleton exposes library info and the device probe only.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:refocal_core/refocal_core.dart';

import 'src/enh_bindings.g.dart';

class RefocalNative {
  RefocalNative._(this._b) {
    final abi = _b.enh_abi_version();
    if (abi != ENH_ABI_VERSION) {
      throw StateError('libenh ABI $abi, bindings expect $ENH_ABI_VERSION');
    }
  }

  /// Opens libenh: the APK's libenh.so on Android, the linked framework on iOS.
  factory RefocalNative.open({String? path}) => RefocalNative._(EnhBindings(_open(path)));

  final EnhBindings _b;

  String get version => _b.enh_version().cast<Utf8>().toDartString();

  /// CPU/GPU description used for device tiers (ADR-0017).
  Map<String, Object?> deviceProbe() {
    final cfg = calloc<enh_session_config>()..ref.struct_size = sizeOf<enh_session_config>();
    final session = calloc<Pointer<enh_session>>();
    final out = calloc<Pointer<Char>>();
    try {
      _check(_b.enh_session_create(cfg, session), 'session_create');
      try {
        _check(_b.enh_device_probe(session.value, out), 'device_probe');
        final json = out.value.cast<Utf8>().toDartString();
        _b.enh_free(out.value.cast());
        return jsonDecode(json) as Map<String, Object?>;
      } finally {
        _b.enh_session_destroy(session.value);
      }
    } finally {
      calloc
        ..free(cfg)
        ..free(session)
        ..free(out);
    }
  }

  static void _check(int code, String what) {
    final s = EnhStatus.fromCode(code);
    if (s != EnhStatus.ok) throw EnhException(s, what);
  }

  static DynamicLibrary _open(String? path) {
    if (path != null) return DynamicLibrary.open(path);
    if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('libenh.so');
    if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.process();
    throw UnsupportedError('Refocal native core: unsupported platform');
  }
}
