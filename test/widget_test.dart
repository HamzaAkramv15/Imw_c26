import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo/app.dart';

void main() {
  testWidgets('renders the museum map shell', (tester) async {
    await tester.pumpWidget(const GemNavigatorApp());
    expect(find.text('GRAND EGYPTIAN MUSEUM'), findsOneWidget);
    expect(find.text('Grand Staircase · Level 1'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Gift shop'), findsOneWidget);
  });

  testWidgets('category pill toggles and map opens pinned location sheet', (
    tester,
  ) async {
    await tester.pumpWidget(const GemNavigatorApp());
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-pin')));
    await tester.pumpAndSettle();
    expect(find.text('PINNED LOCATION'), findsOneWidget);
    expect(find.text('Tutankhamun’s Golden Mask'), findsOneWidget);
    expect(find.text('Start route'), findsOneWidget);

    await tester.tap(find.text('Start route'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED LOCATION'), findsNothing);
  });
}
