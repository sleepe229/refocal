import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/main.dart';

void main() {
  testWidgets('shows the core info screen', (tester) async {
    await tester.pumpWidget(const RefocalApp());
    expect(find.text('Refocal'), findsOneWidget);
  });
}
