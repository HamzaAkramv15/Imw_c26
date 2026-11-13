import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_map_data.dart';
import 'package:imo/data/gem_rostau.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/i18n/strings.dart';
import 'package:imo/models/rostau.dart';
import 'package:imo/screens/rostau_sheet.dart';
import 'package:imo/services/rostau.dart';
import 'package:imo/services/route_finder.dart';
import 'package:imo/state/app_state.dart';
import 'package:imo/state/store.dart';
import 'package:imo/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final graph = MuseumGraph(allMaps);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    Store.put({'rostau': null});
    AppState.instance.setLang(AppLang.en);
  });

  Widget host(Widget child) => MaterialApp(theme: GemTheme.light, home: Scaffold(body: child));

  RostauSheet sheet({String? origin, void Function(RostauTrip, List<String>)? onStart, VoidCallback? onChoose}) => RostauSheet(
    graph: graph,
    originId: origin,
    pinnedCount: 0,
    activeTripId: null,
    onOpenTour: () {},
    onChooseStart: (_) => onChoose?.call(),
    onStart: onStart ?? (_, _) {},
    onPlaceTap: (_) {},
    onMessage: (_) {},
  );

  test('a singular count reads "1 stop"', () {
    expect(S.count('stops', 1), '1 stop');
    expect(S.count('stops', 3), '3 stops');
    expect(S.count('results_n', 1), '1 result');
  });

  testWidgets('the list shows every curated trip, the pinned tour and an empty "your trips"', (t) async {
    await t.pumpWidget(host(sheet()));
    await t.pumpAndSettle();
    expect(find.text('My tour'), findsOneWidget);
    for (final trip in kRostauTrips) {
      final title = trip.titleIn(AppLang.en);
      await t.scrollUntilVisible(find.text(title.substring(title.indexOf(' · ') + 3)), 200, scrollable: find.byType(Scrollable).first);
    }
    await t.scrollUntilVisible(find.text(S.t('your_trips_empty')), 200, scrollable: find.byType(Scrollable).first);
  });

  Future<void> open(WidgetTester t, String text) async {
    await t.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
    await t.ensureVisible(find.text(text));
    await t.pumpAndSettle();
    await t.tap(find.text(text));
    await t.pumpAndSettle();
  }

  testWidgets('without a start point a trip asks for one; with one it starts in walking order', (t) async {
    var asked = false;
    await t.pumpWidget(host(sheet(onChoose: () => asked = true)));
    await t.pumpAndSettle();
    await open(t, 'Gold of the Boy King');
    await t.tap(find.text('Choose where you start'));
    expect(asked, isTrue);

    List<String>? started;
    await t.pumpWidget(host(sheet(origin: 'cx_ticket', onStart: (_, order) => started = order)));
    await t.pumpAndSettle();
    await open(t, 'Gold of the Boy King');
    await t.tap(find.text('Start this trip'));
    final nebu = kRostauTrips.firstWhere((x) => x.id == 'nebu');
    expect(started!.toSet(), nebu.stops.toSet());
    expect(started, RostauPlanner(graph).plan(nebu, 'cx_ticket')!.tour.order);
  });

  testWidgets('the editor saves only with a name and a place, and says what is missing', (t) async {
    Object? result;
    await t.pumpWidget(MaterialApp(
      theme: GemTheme.light,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await Navigator.of(context).push<Object?>(TripEditorPage.route(stops: ['mb_1', 'tg_mask'])),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('Still needed: a name'), findsOneWidget);

    await t.enterText(find.byType(TextField), 'Kings and gold');
    await t.pump();
    await t.tap(save);
    await t.pumpAndSettle();
    expect(result, isA<RostauTrip>());
    expect(RostauLibrary.custom.single.name, 'Kings and gold');
    expect(RostauLibrary.custom.single.stops, ['mb_1', 'tg_mask']);
  });
}
