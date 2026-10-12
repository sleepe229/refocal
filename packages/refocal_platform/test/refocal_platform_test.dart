import 'package:flutter_test/flutter_test.dart';
import 'package:refocal_platform/refocal_platform.dart';
import 'package:refocal_platform/refocal_platform_platform_interface.dart';
import 'package:refocal_platform/refocal_platform_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockRefocalPlatformPlatform
    with MockPlatformInterfaceMixin
    implements RefocalPlatformPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final RefocalPlatformPlatform initialPlatform = RefocalPlatformPlatform.instance;

  test('$MethodChannelRefocalPlatform is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelRefocalPlatform>());
  });

  test('getPlatformVersion', () async {
    RefocalPlatform refocalPlatformPlugin = RefocalPlatform();
    MockRefocalPlatformPlatform fakePlatform = MockRefocalPlatformPlatform();
    RefocalPlatformPlatform.instance = fakePlatform;

    expect(await refocalPlatformPlugin.getPlatformVersion(), '42');
  });
}
