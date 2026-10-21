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

/// Static device signals for the tier (05 §6.1, ADR-0017).
class DeviceInfo {
  DeviceInfo({required this.totalRamBytes, required this.osBuild, this.soc});

  /// Android ActivityManager.MemoryInfo.totalMem; iOS ProcessInfo.physicalMemory.
  int totalRamBytes;

  /// Changes with every OS update (Android Build.FINGERPRINT; iOS the OS version and build).
  String osBuild;

  /// Android Build.SOC_MODEL (API 31+) or Build.HARDWARE; iOS utsname.machine.
  String? soc;
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

  /// Asks for a file (Android: ACTION_OPEN_DOCUMENT, any type: an offline pack .rfpack,
  /// FR-MODEL-006) and copies it into [dstDir]. Returns the copy's path, or null when
  /// cancelled. Error "limit" when it is larger than [maxBytes].
  @async
  String? pickFile(String dstDir, int maxBytes);

  /// Adds [path] to the gallery (Android: MediaStore Pictures/Refocal). Returns its URI.
  @async
  String saveToGallery(String path, String displayName, String mimeType);

  /// Asks where to save (Android: ACTION_CREATE_DOCUMENT, FR-EXP-006) and copies [path]
  /// there. Returns the document URI, or null when cancelled.
  @async
  String? saveToFile(String path, String displayName, String mimeType);

  /// Whether this device can encode HEIC (FR-EXP-002, Q-12): Android has a HEIC image or HEVC
  /// video encoder. False hides the format.
  bool heicSupported();

  /// Encodes raw RGBA8 pixels ([rgbaPath]: [width] x [height] x 4 bytes, from the core's "rgba"
  /// export) into a HEIC file at [dstPath] with [quality] 0..100 (Android: androidx HeifWriter,
  /// grid tiles). Metadata is added by the core afterwards. Error "heic" when encoding fails.
  @async
  void encodeHeic(String rgbaPath, int width, int height, int quality, String dstPath);

  /// Opens an https [url] in the browser (FR-REP-002: a pre-filled issue). Error "no_browser"
  /// when nothing can open it; anything but https is refused.
  void openUrl(String url);

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

  DeviceInfo deviceInfo();

  /// Stops the service. A non-null [finishedText] is left as a tappable notification when the
  /// app is not in the foreground (e.g. "Photo ready").
  void stopProcessing(String? finishedText);
}

/// App self-update (ADR-0027). Implemented only by the `github` flavor; the `fdroid` and
/// `play` builds do not register it, so every call fails with a channel error there.
@HostApi()
abstract class AppUpdateApi {
  /// The installed versionCode (PackageInfo.longVersionCode).
  int installedVersionCode();

  /// Android SDK_INT, compared with an update's minSdk.
  int sdkInt();

  /// The active network is not metered (Wi-Fi, Ethernet): background checks and downloads
  /// only run then.
  bool unmetered();

  /// The user allowed this app to install apps ("Install unknown apps").
  bool canInstall();

  /// Opens the system screen where the user allows that for this app.
  void openInstallSettings();

  /// Installs the APK at [apkPath] over this app through a PackageInstaller session, without
  /// a question where Android allows it (12+, this app is the installer of record). Returns
  /// "pending_user" when Android shows its own dialog, else throws (code "install", the
  /// installer's message). On success the process is replaced and never returns.
  @async
  String install(String apkPath);
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

  /// The system is low on memory, as `enh_set_memory_pressure` takes it: 1 moderate, 2 low
  /// (a memory warning: the next tile is half the size, NFR-MEM-004), 3 critical.
  void onMemoryPressure(int level);
}
