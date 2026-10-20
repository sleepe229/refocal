import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
    await tester.drag(find.byType(CompareSlider), const Offset(100, 0)); // the border's handle
    await tester.pump(const Duration(milliseconds: 400)); // past the double-tap timeout
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

  testWidgets('a look filters the blend, the original stays as it is (FR-LOOK-*)', (tester) async {
    final before = MemoryImage(_png1x1), after = MemoryImage(Uint8List.fromList(_png1x1));
    const look = ColorFilter.mode(Color(0x80FF0000), BlendMode.srcOver);
    await tester.pumpWidget(
      app(CompareSlider(before: before, after: after, aspectRatio: 1, strength: 0.4, look: look)),
    );
    final filtered = find.byType(ColorFiltered);
    expect(tester.widget<ColorFiltered>(filtered).colorFilter, look);
    // Under the filter: the blend (the original at 1 - strength and the result over it).
    expect(find.descendant(of: filtered, matching: find.byType(Opacity)), findsOneWidget);
    expect(
      find.descendant(
        of: filtered,
        matching: find.byWidgetPredicate((w) => w is Image && w.image == before),
      ),
      findsOneWidget,
    );
    // The slider's original (left of the border) is not filtered.
    expect(find.byWidgetPredicate((w) => w is Image && w.image == before), findsNWidgets(2));
  });

  testWidgets('zoom: tiles only past the preview, of the visible part (FR-CMP-005)', (
    tester,
  ) async {
    final tiles = _FakeTiles();
    final img = MemoryImage(_png1x1);
    await tester.pumpWidget(
      app(
        CompareSlider(
          before: img,
          after: img,
          aspectRatio: 2,
          tiles: tiles,
          resultWidth: 8000,
          resultHeight: 4000,
        ),
      ),
    );
    await tester.pump();
    expect(tiles.asked, isEmpty); // fit: the 2048 px previews are enough
    final viewer = find.byType(InteractiveViewer);
    // Off the border's handle (in the middle): a double tap there zooms to 1:1 under it.
    final at = tester.getTopLeft(viewer) + const Offset(100, 130);
    final target = (100 / 400 * 8000, 130 / 200 * 4000); // in result pixels
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final tc = tester.widget<InteractiveViewer>(viewer).transformationController!;
    expect(tc.value.getMaxScaleOnAxis(), greaterThan(2));
    expect(tiles.asked, isNotEmpty);
    expect(tiles.asked.map((t) => t.$6).toSet(), {1}); // 1:1 of the result
    expect(tiles.asked.map((t) => t.$1).toSet(), {0, 1}); // result and original
    for (final (_, x, y, w, h, _) in tiles.asked) {
      expect(x >= 0 && y >= 0 && x + w <= 8000 && y + h <= 4000, isTrue);
      // around where the tap was: only what is visible
      expect((x - target.$1).abs() < 1500 && (y - target.$2).abs() < 1000, isTrue);
    }
    expect(tiles.asked.length, lessThan(2 * 6 * 4)); // two sides x the visible grid
    final asked = tiles.asked.length;
    await tester.pump(); // the same tiles are not asked again while they load
    expect(tiles.asked.length, asked);
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tc.value.getMaxScaleOnAxis(), 1); // back to fit
  });

  testWidgets('side by side: two panels, one zoom (FR-CMP-004)', (tester) async {
    final img = MemoryImage(_png1x1);
    await tester.pumpWidget(app(CompareSlider(before: img, after: img, aspectRatio: 2)));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Side by side'));
    await tester.pump();
    final viewers = tester.widgetList<InteractiveViewer>(find.byType(InteractiveViewer)).toList();
    expect(viewers, hasLength(2));
    expect(viewers[0].transformationController, same(viewers[1].transformationController));
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Enhanced'), findsOneWidget);
    await tester.tap(find.byTooltip('With a border'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('holding a finger shows the original until it is lifted (FR-CMP-002)', (
    tester,
  ) async {
    final img = MemoryImage(_png1x1);
    await tester.pumpWidget(app(CompareSlider(before: img, after: img, aspectRatio: 2)));
    String value() =>
        tester.getSemantics(find.bySemanticsLabel('Before and after comparison')).value;
    expect(value(), '50% original');
    final g = await tester.startGesture(
      tester.getTopLeft(find.byType(InteractiveViewer)) + const Offset(80, 120),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(value(), '100% original');
    await g.up();
    await tester.pump();
    expect(value(), '50% original');
  });

  test('scale choices follow ADR-0014', () {
    expect(ScaleChoice.fast2.scale, 2);
    expect(ScaleChoice.fast2.fastPath, isTrue);
    expect(ScaleChoice.x1.scale, 1);
    expect(ProviderContainer().read(enhanceProvider), isA<Idle>());
  });
}

class _FakeTiles implements CompareTiles {
  final asked = <(int, int, int, int, int, int)>[];

  @override
  Future<ui.Image> tile(int source, int x, int y, int w, int h, int factor) {
    asked.add((source, x, y, w, h, factor));
    return Completer<ui.Image>().future; // still loading: the preview is drawn
  }
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
