// Pigeon definitions for platform services (ADR-0005: Pigeon for everything outside the pixel
// path). Regenerate: dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    kotlinOut: 'android/src/main/kotlin/io/github/refocal/refocal_platform/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.github.refocal.refocal_platform'),
    swiftOut: 'ios/refocal_platform/Sources/refocal_platform/Messages.g.swift',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
class AppDirs {
  AppDirs({required this.support, required this.cache});

  /// Persistent, not backed up: models/, jobs/, inbox/ live here.
  String support;
  String cache;
}

class PickedImage {
  PickedImage({required this.path, required this.sizeBytes, this.displayName, this.mimeType});

  /// Copy inside the app's inbox directory; the original is never modified.
  String path;
  int sizeBytes;
  String? displayName;
  String? mimeType;
}

@HostApi()
abstract class RefocalPlatformApi {
  AppDirs getDirs();

  /// How the previous process ended, for the crash sentinel (ADR-0016): "native_crash",
  /// "os_kill" or null (unknown; Android < 11, iOS).
  String? lastExitReason();

  /// System photo picker; copies the selection into [inboxDir]. Null when cancelled.
  @async
  PickedImage? pickImage(String inboxDir);

  /// Adds [path] to the gallery (Android: MediaStore Pictures/Refocal). Returns its URI.
  @async
  String saveToGallery(String path, String displayName, String mimeType);

  /// Android 13+: asks for POST_NOTIFICATIONS (progress of background processing). True if
  /// granted or not needed. Processing works either way; only the notification is hidden.
  @async
  bool requestNotificationPermission();

  /// Keeps processing alive while the app is in the background (ADR-0019, FR-BATCH-004):
  /// Android foreground service with a progress notification and Pause/Cancel actions.
  /// Must be called while the app is in the foreground (a user action).
  void startProcessing(String title);

  /// [percent] 0..100, or -1 for indeterminate.
  void updateProcessing(String text, int percent);

  /// Stops the service. A non-null [finishedText] is left as a tappable notification when the
  /// app is not in the foreground (e.g. "Photo ready").
  void stopProcessing(String? finishedText);
}

/// Calls from the platform into Dart.
@FlutterApi()
abstract class RefocalPlatformEvents {
  /// A notification action: "pause", "cancel", or "timeout" (Android 15 FGS time limit:
  /// pause and checkpoint now, the user continues later).
  void onProcessingAction(String action);
}
