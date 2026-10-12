import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

void main() => runApp(const RefocalApp());

class RefocalApp extends StatelessWidget {
  const RefocalApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Refocal',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const _CoreInfo(),
  );
}

/// M0 skeleton screen: proves the native core loads and probes the device.
class _CoreInfo extends StatelessWidget {
  const _CoreInfo();

  @override
  Widget build(BuildContext context) {
    String text;
    try {
      final core = RefocalNative.open();
      text =
          'libenh ${core.version}\n\n'
          '${const JsonEncoder.withIndent('  ').convert(core.deviceProbe())}';
    } catch (e) {
      text = 'Native core unavailable: $e';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Refocal')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace')),
      ),
    );
  }
}
