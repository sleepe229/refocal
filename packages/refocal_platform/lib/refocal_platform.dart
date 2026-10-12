import 'refocal_platform_platform_interface.dart';

class RefocalPlatform {
  Future<String?> getPlatformVersion() {
    return RefocalPlatformPlatform.instance.getPlatformVersion();
  }
}
