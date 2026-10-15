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
  AppDirs({required this.support, required this.backedUp, required this.cache});

  /// Persistent, not backed up: models/, jobs/, inbox/, db.sqlite live here (PRIV-DATA-005).
  String support;

  /// Persistent, in the platform backup: prefs.sqlite only (Android: filesDir, restricted to
  /// that file by the app's backup rules; iOS: Application Support).
  String backedUp;
  String cache;
}

/// Images copied into the inbox, and how many of the selection could not be.
class PickedImages {
  PickedImages({required this.images, required this.failed, this.failure});

  List<PickedImage> images;
  int failed;

  /// Error code of the first failure ("limit": larger than SEC-INP-002 allows; "io").
  String? failure;
}

class PickedImage {
  PickedImage({required this.path, required this.sizeBytes, this.displayName, this.mimeType});

  /// Copy inside the app's inbox directory; the original is never modified.
  String path;
  int sizeBytes;
  String? displayName;
  String? mimeType;
}

/// Texts of the processing notification, in the app's language (the platform has no access to
/// the Dart localizations).
class ProcessingTexts {
  ProcessingTexts({
    required this.title,
    required this.pause,
    required this.cancel,
    required this.timedOut,
    required this.channelName,
    required this.channelDescription,
  });

  String title;
  String pause;
  String cancel;

  /// Left as a tappable notification when Android's background time limit pauses the job.
  String timedOut;
  String channelName;
  String channelDescription;
}

@HostApi()
abstract class RefocalPlatformApi {
  AppDirs getDirs();

  /// How the previous process ended, for the crash sentinel (ADR-0016): "native_crash",
  /// "os_kill" or null (unknown; Android < 11, iOS).
  String? lastExitReason();

  /// System photo picker, up to [maxCount] images (1: single selection); copies the selection
  /// into [inboxDir] in the order picked. Empty when cancelled.
  @async
  PickedImages pickImages(String inboxDir, int maxCount);

  /// Adds [path] to the gallery (Android: MediaStore Pictures/Refocal). Returns its URI.
  @async
  String saveToGallery(String path, String displayName, String mimeType);

  /// Asks where to save (Android: ACTION_CREATE_DOCUMENT, FR-EXP-006) and copies [path]
  /// there. Returns the document URI, or null when cancelled.
  @async
  String? saveToFile(String path, String displayName, String mimeType);

  /// Opens the system share sheet for [path] (Android: a content URI from the plugin's own
  /// provider, read-only; the file must be in the cache "share" directory).
  void shareFile(String path, String mimeType, String chooserTitle);

  /// The images shared to the app (Android ACTION_SEND / ACTION_SEND_MULTIPLE of images,
  /// FR-SHARE-001) that have not been taken yet, copied into [inboxDir]; empty if none. Each
  /// share is returned once.
  @async
  PickedImages takeSharedImages(String inboxDir);

  /// Android 13+: asks for POST_NOTIFICATIONS (progress of background processing). True if
  /// granted or not needed. Processing works either way; only the notification is hidden.
  @async
  bool requestNotificationPermission();

  /// Keeps processing alive while the app is in the background (ADR-0019, FR-BATCH-004):
  /// Android foreground service with a progress notification and Pause/Cancel actions.
  /// Must be called while the app is in the foreground (a user action).
  void startProcessing(ProcessingTexts texts);

  /// [percent] 0..100, or -1 for indeterminate.
  void updateProcessing(String text, int percent);

  /// The device's thermal level as `enh_set_thermal` takes it: 0 nominal, 1 light, 2 fair,
  /// 3 serious, 4 critical (NFR-THERM-002). Changes arrive as onThermalLevel.
  int thermalLevel();

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

  /// Images were shared to the running app; fetch them with takeSharedImages().
  void onSharedImage();

  /// The device's thermal level changed (see RefocalPlatformApi.thermalLevel).
  void onThermalLevel(int level);
}
