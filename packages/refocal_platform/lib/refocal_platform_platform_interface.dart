import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'refocal_platform_method_channel.dart';

abstract class RefocalPlatformPlatform extends PlatformInterface {
  /// Constructs a RefocalPlatformPlatform.
  RefocalPlatformPlatform() : super(token: _token);

  static final Object _token = Object();

  static RefocalPlatformPlatform _instance = MethodChannelRefocalPlatform();

  /// The default instance of [RefocalPlatformPlatform] to use.
  ///
  /// Defaults to [MethodChannelRefocalPlatform].
  static RefocalPlatformPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [RefocalPlatformPlatform] when
  /// they register themselves.
  static set instance(RefocalPlatformPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
