import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine.dart';

/// Metadata policy (FR-SET-002, ADR-0018). A JSON file until the drift database arrives with
/// history in 0.3 (ADR-0009): two flags do not justify bundling SQLite into a 30 MB APK.
class Settings {
  const Settings({this.keepGps = false, this.aiMarker = true});

  /// PRIV-META-001: location is removed from results unless the user asks to keep it.
  final bool keepGps;

  /// FR-META-004/005: XMP DigitalSourceType marker; can be turned off with a warning.
  final bool aiMarker;

  Settings copyWith({bool? keepGps, bool? aiMarker}) =>
      Settings(keepGps: keepGps ?? this.keepGps, aiMarker: aiMarker ?? this.aiMarker);

  Map<String, Object?> toJson() => {'version': 1, 'keep_gps': keepGps, 'ai_marker': aiMarker};

  factory Settings.fromJson(Map<String, Object?> j) =>
      Settings(keepGps: j['keep_gps'] == true, aiMarker: j['ai_marker'] != false);
}

class SettingsController extends AsyncNotifier<Settings> {
  File? _file;

  @override
  Future<Settings> build() async {
    final dirs = await ref.watch(appDirsProvider.future);
    final f = _file = File('${dirs.support}/settings.json');
    try {
      return Settings.fromJson(jsonDecode(await f.readAsString()) as Map<String, Object?>);
    } on Object {
      return const Settings(); // missing or unreadable: defaults are the private ones
    }
  }

  Future<void> save(Settings s) async {
    state = AsyncData(s);
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.part');
    await tmp.writeAsString(jsonEncode(s.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, Settings>(
  SettingsController.new,
);
