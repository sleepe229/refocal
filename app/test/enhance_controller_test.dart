import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/features/editor/enhance_controller.dart';

void main() {
  // Leaving the editor disposes the controller; its cleanup used to read `state` in onDispose,
  // which Riverpod 3 refuses (UnmountedRefException on the S24, every time), so nothing was
  // cleaned up.
  test('disposing the editor controller cleans up without touching the disposed ref', () {
    final errors = <Object>[];
    runZonedGuarded(() {
      final container = ProviderContainer();
      final sub = container.listen(enhanceProvider, (_, _) {});
      expect(container.read(enhanceProvider), isA<Idle>());
      sub.close();
      container.dispose();
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });
}
