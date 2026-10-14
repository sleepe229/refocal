import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/features/editor/enhance_controller.dart';
import 'package:refocal/l10n/app_localizations.dart';
import 'package:refocal/ui_kit/compare_slider.dart';

void main() {
  Widget app(Widget child, {Locale? locale}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SizedBox(width: 400, child: child)),
  );

  testWidgets('compare slider moves with a drag', (tester) async {
    final img = MemoryImage(_png1x1);
    await tester.pumpWidget(app(CompareSlider(before: img, after: img, aspectRatio: 1)));
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    await tester.drag(find.byType(CompareSlider), const Offset(100, 0));
    await tester.pump();
  });

  testWidgets('strength below 100% previews the blend over the original', (tester) async {
    final before = MemoryImage(_png1x1), after = MemoryImage(Uint8List.fromList(_png1x1));
    await tester.pumpWidget(
      app(
        CompareSlider(before: before, after: after, aspectRatio: 1, strength: 0.4),
        locale: const Locale('ru'),
      ),
    );
    expect(find.text('Оригинал'), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 0.4);
    // The original under the result, plus the clipped original of the slider.
    expect(find.byWidgetPredicate((w) => w is Image && w.image == before), findsNWidgets(2));
  });

  test('scale choices follow ADR-0014', () {
    expect(ScaleChoice.fast2.scale, 2);
    expect(ScaleChoice.fast2.fastPath, isTrue);
    expect(ScaleChoice.x1.scale, 1);
    expect(ProviderContainer().read(enhanceProvider), isA<Idle>());
  });
}

final _png1x1 = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
