import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_platform/refocal_platform.dart';

/// Actions from the processing notification (ADR-0019): "pause", "cancel", "timeout".
class ProcessingActions implements RefocalPlatformEvents {
  ProcessingActions._();

  static final instance = ProcessingActions._();
  final _actions = StreamController<String>.broadcast();

  Stream<String> get stream => _actions.stream;

  /// Registers the Pigeon handler; call once in main().
  static void install() => RefocalPlatformEvents.setUp(instance);

  @override
  void onProcessingAction(String action) => _actions.add(action);
}

final processingActionsProvider = Provider((_) => ProcessingActions.instance.stream);
