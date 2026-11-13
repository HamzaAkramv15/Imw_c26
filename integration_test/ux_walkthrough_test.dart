// On-device UX walkthrough: drives the main journeys and asks the host for a
// real simulator screenshot at each step.
//
//   SHOTS_DIR=/path flutter test integration_test/ux_walkthrough_test.dart \
//     -d <simulator> --dart-define=SHOTS_DIR=/path
//
// For each step the test writes `<dir>/req/<name>` and waits until a host-side
// watcher (`xcrun simctl io <udid> screenshot`) deletes it. The simulator shares
// the host file system, so no driver is needed. Without SHOTS_DIR the steps
// still run (and check), they just take no pictures.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:imo/app.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/state/app_state.dart';
import 'package:imo/state/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dir = String.fromEnvironment('SHOTS_DIR');
const _only = String.fromEnvironment('ONLY'); // comma-separated journey names

Future<void> _settle(WidgetTester t, [int ms = 900]) async {
  // the route dashes animate forever, so pumpAndSettle would never return
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> shot(WidgetTester t, String name) async {
  await _settle(t);
  if (_dir.isEmpty) return;
  final req = File('$_dir/req/$name')..createSync(recursive: true);
  for (var i = 0; i < 200 && req.existsSync(); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
  }
}

Future<void> tapText(WidgetTester t, String text, {bool last = false}) async {
  final f = last ? find.text(text).last : find.text(text).first;
  // on a small phone the row may be below the fold of its sheet
  if (find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate().isNotEmpty) {
    await t.ensureVisible(f);
    await _settle(t, 300);
  }
  await t.tap(f, warnIfMissed: false);
  await _settle(t, 600);
}

Future<void> tapTip(WidgetTester t, String tip) async {
  await t.tap(find.byTooltip(tip).first, warnIfMissed: false);
  await _settle(t, 600);
}

Future<void> back(WidgetTester t) async {
  // dismiss the top sheet / page the way a user would: tap the scrim or go back
  final nav = t.state<NavigatorState>(find.byType(Navigator).first);
  nav.maybePop();
  await _settle(t, 600);
}

bool _run(String journey) => _only.isEmpty || _only.split(',').contains(journey);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> launch(WidgetTester t, {Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    await Store.init();
    // Store keeps its in-memory copy when nothing is saved: start each journey clean
    Store.put({'map': null, 'pinned': <String>[], 'origin': null, 'routeTarget': null, 'tour': null, 'trip': null, 'views': <String, Object>{}, 'quarter': <String, Object>{}, 'rostau': null});
    AppState.instance.setLang(AppLang.en);
    AppState.instance.setThemeMode(ThemeMode.light);
    AppState.instance.setAvoidStairs(false);
    await t.pumpWidget(GemNavigatorApp(key: UniqueKey()));
    await _settle(t, 1500);
  }

  /// The app started again on the state it saved (a relaunch, minus the process).
  Future<void> relaunch(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await _settle(t, 800); // the debounced save
    await Store.init();
    await t.pumpWidget(GemNavigatorApp(key: UniqueKey()));
    await _settle(t, 1500);
  }

  Future<void> scrollTo(WidgetTester t, String text) async {
    await t.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).last);
    await t.ensureVisible(find.text(text).last);
    await _settle(t, 400);
  }

  testWidgets('walkthrough', (t) async {
    if (_run('maps')) {
      await launch(t);
      await shot(t, 'a01_fresh_complex');
      await tapText(t, 'Building');
      await shot(t, 'a02_building');
      await tapText(t, 'Galleries');
      await shot(t, 'a03_galleries');
      await tapText(t, '01–03');
      await shot(t, 'a04_galleries_era');
      await tapText(t, '07–09');
      await shot(t, 'a05_galleries_era3');
      await tapText(t, 'Complex');
      await tapText(t, 'Highlights');
      await shot(t, 'a06_filter_highlights');
    }

    if (_run('search')) {
      await launch(t);
      await t.tap(find.text('Search places, galleries, shops…'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'mask');
      await _settle(t);
      await tapText(t, 'Golden funerary mask');
      await shot(t, 'b04_detail');
      await tapText(t, 'Pin');
      await shot(t, 'b05_detail_pinned');
      expect(find.text('Pinned'), findsOneWidget); // the sheet stayed open
      await tapText(t, 'Start route');
      await shot(t, 'b07_where_am_i');
      await t.tap(find.byType(TextField).last);
      await _settle(t);
      await shot(t, 'b08_where_am_i_keyboard');
      await t.enterText(find.byType(TextField).last, 'ticket');
      await shot(t, 'b09_where_am_i_typed');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await shot(t, 'b10_route_card');
      // the route card opens the directions (it shows one instruction at a time)
      await t.tap(find.byIcon(Icons.alt_route).first);
      await _settle(t);
      await shot(t, 'b11_directions');
      await back(t);
      await tapTip(t, 'My tour');
      await shot(t, 'b12_tour_one');
      await back(t);
    }

    if (_run('pick')) {
      await launch(t);
      await tapTip(t, 'Where am I?');
      await tapText(t, 'Pick on the map');
      await shot(t, 'p01_pick_banner');
      await tapText(t, 'Cancel');
      await shot(t, 'p02_pick_cancelled');
    }

    if (_run('settings')) {
      await launch(t);
      await tapTip(t, 'My tour');
      await shot(t, 'c01_tour_empty');
      await back(t);
      await tapTip(t, 'Settings');
      await shot(t, 'c02_settings');
      await scrollTo(t, 'Turn map 90°');
      await shot(t, 'c02b_settings_bottom');
      await tapText(t, 'Dark');
      await back(t);
      await shot(t, 'c04_map_dark');
      AppState.instance.setThemeMode(ThemeMode.light);
      AppState.instance.setLang(AppLang.ar);
      await shot(t, 'c05_map_arabic');
      AppState.instance.setLang(AppLang.de);
      await _settle(t);
      await tapText(t, 'Ausstellung');
      await shot(t, 'c06_map_german_galleries');
      AppState.instance.setLang(AppLang.en);
    }

    if (_run('bigtext')) {
      // run with the simulator's text size raised (xcrun simctl ui <udid> content_size …)
      await launch(t);
      await shot(t, 'x01_big_map');
      await tapText(t, 'Galleries');
      await shot(t, 'x02_big_galleries');
      await tapTip(t, 'Where am I?');
      await shot(t, 'x03_big_where');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await tapTip(t, 'Rostau trips');
      await shot(t, 'x04_big_trips');
      await back(t);
    }

    if (_run('motion')) {
      // run with Reduce Motion on: once the route is drawn nothing keeps animating
      await launch(t, prefs: const {});
      final reduce = t.binding.platformDispatcher.accessibilityFeatures.disableAnimations;
      debugPrint('REDUCE_MOTION=$reduce');
      await tapTip(t, 'Where am I?');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await t.tap(find.text('Search places, galleries, shops…'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'mask');
      await _settle(t);
      await tapText(t, 'Golden funerary mask');
      await tapText(t, 'Start route');
      await _settle(t, 3500); // past the toast and every transition
      debugPrint('FRAME_SCHEDULED=${t.binding.hasScheduledFrame}');
      if (reduce) expect(t.binding.hasScheduledFrame, isFalse);
    }

    if (_run('rostau')) {
      await launch(t);
      await tapTip(t, 'Rostau trips');
      await shot(t, 'r01_trips');
      await scrollTo(t, 'The Road Through the Afterlife');
      await tapText(t, 'The Road Through the Afterlife');
      await shot(t, 'r02_trip_no_start');
      await tapText(t, 'Choose where you start');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await shot(t, 'r03_trip_planned');
      await scrollTo(t, 'ON THE WAY');
      await shot(t, 'r03b_trip_on_the_way');
      await tapText(t, 'Start this trip');
      await shot(t, 'r04_trip_on_map');
      await relaunch(t);
      expect(Store.get('trip'), 'duat');
      await shot(t, 'r05_trip_restored');
      await t.tap(find.textContaining('Next: Stop').first); // the trip banner opens the directions
      await _settle(t, 600);
      await shot(t, 'r06_trip_directions');
      await back(t);

      // own trip, from scratch
      await tapTip(t, 'Rostau trips');
      await scrollTo(t, 'New trip');
      await tapText(t, 'New trip', last: true);
      await shot(t, 'r07_editor_empty');
      await t.enterText(find.byType(TextField).first, 'Kings and gold');
      await tapText(t, 'Add places');
      await t.enterText(find.byType(TextField).last, 'mask');
      await _settle(t);
      await tapText(t, 'Golden funerary mask', last: true);
      await tapText(t, 'Add places');
      await t.enterText(find.byType(TextField).last, 'Ramesses');
      await _settle(t);
      await tapText(t, 'Colossal Statue of Ramesses II', last: true);
      await shot(t, 'r08_editor_two');
      await tapText(t, 'Save');
      await shot(t, 'r09_own_trip');
      await back(t);
      await shot(t, 'r10_trips_with_own');
      await back(t);

      // pins → trip
      await t.tap(find.text('Search places, galleries, shops…'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'throne');
      await _settle(t);
      await tapText(t, 'Golden throne', last: true);
      await tapText(t, 'Pin');
      await back(t);
      await tapTip(t, 'My tour');
      await shot(t, 'r11_tour_save_as_trip');
      await tapText(t, 'Save as trip');
      await shot(t, 'r12_editor_from_pins');
      await back(t); // nothing typed yet: leaves without asking

      AppState.instance.setLang(AppLang.ar);
      await _settle(t);
      await tapTip(t, 'رحلات رُستاو');
      await shot(t, 'r13_trips_arabic');
      await back(t);
      AppState.instance.setLang(AppLang.en);
      AppState.instance.setThemeMode(ThemeMode.dark);
      await _settle(t);
      await tapTip(t, 'Rostau trips');
      await shot(t, 'r14_trips_dark');
      await back(t);
      AppState.instance.setThemeMode(ThemeMode.light);
    }

    if (_run('mosque')) {
      await launch(t);
      await tapText(t, 'Building');
      await shot(t, 'm01_building');
      await tapTip(t, 'Where am I?');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await t.tap(find.text('Search places, galleries, shops…'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'prayer');
      await _settle(t);
      await tapText(t, 'Prayer Room', last: true);
      await tapText(t, 'Start route');
      await tapText(t, 'Building');
      await shot(t, 'm02_route_to_prayer_room');
      await t.tap(find.text('Search places, galleries, shops…'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'prayer');
      await _settle(t);
      await tapText(t, 'Prayer Room', last: true);
      await tapText(t, "I'm here");
      await tapTip(t, 'Where am I?'); // known now: flies to the marker
      await shot(t, 'm03_mosque_close');
      await tapTip(t, 'Zoom in');
      await shot(t, 'm04_mosque_closer');
      AppState.instance.setThemeMode(ThemeMode.dark);
      await shot(t, 'm05_mosque_dark');
      AppState.instance.setThemeMode(ThemeMode.light);
      // browsing: the next room along is where you are, the mosque has a plain pin
      await tapTip(t, 'Clear route');
      await t.tap(find.text('Search places, galleries, shops…'));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'clinic');
      await _settle(t);
      await tapText(t, 'Clinic', last: true);
      await tapText(t, "I'm here");
      await tapTip(t, 'Where am I?');
      await tapTip(t, 'Zoom in');
      await shot(t, 'm06_mosque_browse');
      await tapTip(t, 'Settings');
      await tapText(t, 'Turn map 90°');
      await tapTip(t, 'Where am I?');
      await tapTip(t, 'Zoom in');
      await shot(t, 'm07_mosque_turned');
    }

    if (_run('trip')) {
      // a whole trip, stop by stop: where you have been, where you go now, where it ends
      await launch(t);
      await tapTip(t, 'Where am I?');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await tapTip(t, 'Rostau trips');
      await tapText(t, 'The Great House');
      await tapText(t, 'Start this trip');
      await shot(t, 't00_start');
      for (var i = 1; i <= 6; i++) {
        await tapText(t, 'Arrived');
        await _settle(t, 1200);
        await shot(t, 't0${i}_arrived_$i');
        if (i == 3) {
          AppState.instance.setThemeMode(ThemeMode.dark);
          await shot(t, 't0${i}b_dark');
          AppState.instance.setThemeMode(ThemeMode.light);
          AppState.instance.setLang(AppLang.ar);
          await shot(t, 't0${i}c_arabic');
          AppState.instance.setLang(AppLang.en);
          await relaunch(t);
          expect(Store.get('tripDone'), 3);
          await shot(t, 't0${i}d_restored');
          await tapText(t, 'Galleries');
          await shot(t, 't0${i}e_galleries');
        }
      }
      expect(find.text('Trip complete'), findsOneWidget);
    }

    if (_run('era')) {
      // the timeline chips light their galleries on the plan
      await launch(t);
      await tapText(t, 'Galleries');
      await shot(t, 'e00_none');
      for (final c in ['01–03', '04–06', '07–09', '10–12']) {
        await tapText(t, c);
        await shot(t, 'e_${c.replaceAll('–', '_')}');
      }
      await tapText(t, '10–12'); // again: off
      await shot(t, 'e05_cleared');
      await tapText(t, 'Galleries'); // the category filter (the tab is the last one)
      await tapText(t, '04–06');
      await shot(t, 'e06_filter_on');
      await tapText(t, 'All');
      await shot(t, 'e07_filter_off');
      // with a trip running, and at night
      await tapTip(t, 'Where am I?');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await tapTip(t, 'Rostau trips');
      await tapText(t, 'The Great House');
      await tapText(t, 'Start this trip');
      await tapText(t, 'Galleries', last: true);
      await tapText(t, '07–09');
      await shot(t, 'e08_with_route');
      AppState.instance.setThemeMode(ThemeMode.dark);
      await shot(t, 'e09_dark');
      AppState.instance.setThemeMode(ThemeMode.light);
    }

    if (_run('fixes')) {
      await launch(t);
      await shot(t, 'f01_complex');
      await tapText(t, 'Galleries');
      await tapText(t, '01–03');
      await shot(t, 'f02_era_01_03');
      await tapText(t, '04–06');
      await shot(t, 'f03_era_04_06');
      await tapText(t, '04–06');
      await tapText(t, 'Complex');

      // a few pins, then a trip on top of them
      for (final (q, name) in [('mask', 'Golden funerary mask'), ('throne', 'Golden throne'), ('Ramesses', 'Colossal Statue of Ramesses II')]) {
        await t.tap(find.text('Search places, galleries, shops…'));
        await _settle(t);
        await t.enterText(find.byType(TextField), q);
        await _settle(t);
        await tapText(t, name, last: true);
        await tapText(t, 'Pin');
        await back(t);
      }
      await shot(t, 'f04_pins');
      await tapTip(t, 'Rostau trips');
      await tapText(t, 'The Great House');
      await tapText(t, 'Choose where you start');
      await tapText(t, 'Ticketing & Entrance', last: true);
      await shot(t, 'f05_trip_planned');
      await tapText(t, 'Start this trip');
      await shot(t, 'f06_trip_complex');
      await tapText(t, 'Building');
      await shot(t, 'f07_trip_building');
      await tapText(t, 'Galleries');
      await shot(t, 'f08_trip_galleries');
      await tapText(t, '07–09');
      await shot(t, 'f09_trip_galleries_era');
      await tapTip(t, 'My tour');
      await shot(t, 'f10_tour_during_trip');
      await back(t);
      await tapTip(t, 'Rostau trips');
      await shot(t, 'f11_trips_during_trip');
      await back(t);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
      await _settle(t, 1500);
      await shot(t, 'f12_trip_landscape');
      await SystemChrome.setPreferredOrientations([]);
      await _settle(t, 1500);
    }
  });
}
