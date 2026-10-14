import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_platform/refocal_platform.dart';

/// Calls from the platform: actions from the processing notification (ADR-0019): "pause",
/// "cancel", "timeout"; and "an image was shared to the running app" (FR-SHARE-001).
class ProcessingActions implements RefocalPlatformEvents {
  ProcessingActions._();

  static final instance = ProcessingActions._();
  final _actions = StreamController<String>.broadcast();
  final _shared = StreamController<void>.broadcast();

  Stream<String> get stream => _actions.stream;
  Stream<void> get shared => _shared.stream;

  /// Registers the Pigeon handler; call once in main().
  static void install() => RefocalPlatformEvents.setUp(instance);

  @override
  void onProcessingAction(String action) => _actions.add(action);

  @override
  void onSharedImage() => _shared.add(null);
}

final processingActionsProvider = Provider((_) => ProcessingActions.instance.stream);

/// Fires when an image is shared while the app runs; take it with takeSharedImage().
final sharedImageEventsProvider = Provider((_) => ProcessingActions.instance.shared);
