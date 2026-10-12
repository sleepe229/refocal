import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'refocal_platform_platform_interface.dart';

/// An implementation of [RefocalPlatformPlatform] that uses method channels.
class MethodChannelRefocalPlatform extends RefocalPlatformPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('refocal_platform');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
