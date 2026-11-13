import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo/app.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/state/app_state.dart';
import 'package:imo/state/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });

  testWidgets('the app starts, and follows the language and its direction', (tester) async {
    AppState.instance.setLang(AppLang.en);
    await tester.pumpWidget(const GemNavigatorApp());
    await tester.pump(const Duration(milliseconds: 100));
    final scaffold = find.byType(Scaffold).first;
    expect(Directionality.of(tester.element(scaffold)), TextDirection.ltr);

    AppState.instance.setLang(AppLang.ar);
    await tester.pump(const Duration(milliseconds: 100));
    expect(Directionality.of(tester.element(find.byType(Scaffold).first)), TextDirection.rtl);

    AppState.instance.setLang(AppLang.ja);
    await tester.pump(const Duration(milliseconds: 100));
    expect(Localizations.localeOf(tester.element(find.byType(Scaffold).first)).languageCode, 'ja');
    AppState.instance.setLang(AppLang.en);
    // let the debounced save and the language switch settle
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('with Reduce Motion on, a shown route stands still (no endless frames)', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    // a visitor who set their location and asked for a route, last time
    Store.put({'map': 'gem_complex', 'origin': 'cx_ticket', 'routeTarget': 'tg_mask', 'tour': null});
    await tester.pumpWidget(const GemNavigatorApp());
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byTooltip('Next step'), findsOneWidget); // the route card is up, with its instruction
    expect(tester.binding.hasScheduledFrame, isFalse);
    Store.put({'origin': null, 'routeTarget': null});
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
