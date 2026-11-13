import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_extras.dart';
import 'package:imo/data/gem_regions.dart';
import 'package:imo/widgets/museum_map_canvas.dart';

void main() {
  final galleries = regionsFor('main_galleries');

  test('each timeline chip lights exactly the galleries its label names', () {
    const want = {
      '01–03': {'mg_zone_01', 'mg_zone_02', 'mg_zone_03'},
      '04–06': {'mg_zone_04', 'mg_zone_05', 'mg_zone_06'},
      '07–09': {'mg_zone_07', 'mg_zone_08', 'mg_zone_09', 'mg_zone_09b'},
      '10–12': {'mg_zone_10', 'mg_zone_11', 'mg_zone_12'},
    };
    for (final e in kEras) {
      expect(regionsInGroup(galleries, e.id), want[e.galleries], reason: e.galleries);
    }
    expect(regionsInGroup(galleries, null), isEmpty);
  });

  test('the galleries of a picked era are lifted out of the veil', () {
    final era = regionsInGroup(galleries, 'era2');
    expect(focusRegions(galleries, era, null), era);
    // switching chips switches the lit rooms; no chip, nothing lit
    expect(focusRegions(galleries, regionsInGroup(galleries, 'era4'), null), isNot(contains('mg_zone_05')));
    expect(focusRegions(galleries, const {}, null), isEmpty);
  });

  test('a gallery only selected is marked by its pin, other rooms are lifted', () {
    expect(focusRegions(galleries, const {}, 'mg_zone_05'), isEmpty);
    final building = regionsFor('main_building');
    expect(focusRegions(building, const {}, 'mb_zone_grand_hall'), {'mb_zone_grand_hall'});
    // selecting a gallery while an era is lit keeps the era lit
    final era = regionsInGroup(galleries, 'era1');
    expect(focusRegions(galleries, era, 'mg_zone_07'), era);
  });
}
