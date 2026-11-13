import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_map_data.dart';
import 'package:imo/data/gem_rostau.dart';
import 'package:imo/models/rostau.dart';
import 'package:imo/services/route_finder.dart';

void main() {
  const order = ['a', 'b', 'c', 'd'];

  test('a fresh trip: nothing done, the first stop is next, the last is the finish', () {
    const p = TripProgress(order, 0);
    expect(p.total, 4);
    expect(p.done, 0);
    expect(p.next, 'a');
    expect(p.nextNumber, 1);
    expect(p.finish, 'd');
    expect(p.finished, isFalse);
    expect(p.stateOf('a'), StopState.current);
    expect(p.stateOf('b'), StopState.upcoming);
    expect(p.stateOf('x'), isNull);
    expect(p.numberOf('c'), 3);
  });

  test('arriving marks the current stop done and moves on, up to the end', () {
    var p = const TripProgress(order, 0).arrive();
    expect(p.done, 1);
    expect(p.stateOf('a'), StopState.done);
    expect(p.next, 'b');
    p = p.arrive().arrive().arrive();
    expect(p.finished, isTrue);
    expect(p.next, isNull);
    expect(p.stateOf('d'), StopState.done);
    expect(p.arrive().done, 4); // never past the end
  });

  test('saying you are at a later stop marks every stop up to it done', () {
    final p = const TripProgress(order, 1).at('c');
    expect(p.done, 3);
    expect(p.next, 'd');
    // an earlier stop, or a place off the trip, changes nothing
    expect(p.at('a').done, 3);
    expect(p.at('elsewhere').done, 3);
  });

  test('a saved count out of range is clamped', () {
    expect(const TripProgress(order, -2).done, 0);
    expect(const TripProgress(order, 9).done, 4);
    expect(const TripProgress([], 0).finished, isTrue);
  });

  test('the walk splits into the part behind and the part ahead, in the planned order', () {
    final graph = MuseumGraph(allMaps);
    final trip = kRostauTrips.first;
    final plan = graph.tour('cx_ticket', trip.stops)!;
    final p = TripProgress(plan.order, 2);
    final ahead = graph.tour(plan.order[1], p.remaining, optimize: false)!;
    expect(ahead.order, p.remaining);
    final behind = graph.tour('cx_ticket', p.walked, optimize: false)!;
    expect(behind.order, plan.order.take(2).toList());
  });
}
