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
}
