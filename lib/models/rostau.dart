import '../i18n/lang.dart';

/// A Rostau trip: an ordered wish-list of places, planned into one walk.
///
/// Rostau (Egyptian *Ra-setau*, "the mouth of the passages") was a name for the
/// necropolis of Giza and for the ways leading through the underworld.
///
/// Curated trips carry their title and phrase in every language (columns in
/// [AppLang] order); a visitor's own trip carries the name they typed.
class RostauTrip {
  const RostauTrip(this.id, this.stops, {this.title = const [], this.phrase = const [], this.name});

  /// A visitor's trip.
  const RostauTrip.custom(this.id, this.name, this.stops)
      : title = const [],
        phrase = const [];

  final String id;

  /// Place ids, in the order the trip lists them (the planner may reorder).
  final List<String> stops;
  final List<String> title;
  final List<String> phrase;

  /// The visitor's own name for the trip; null for a curated trip.
  final String? name;

  bool get custom => name != null;

  String titleIn(AppLang l) => name ?? title[l.index];
  String phraseIn(AppLang l) => phrase.isEmpty ? '' : phrase[l.index];

  RostauTrip copyWith({String? name, List<String>? stops}) =>
      RostauTrip(id, stops ?? this.stops, title: title, phrase: phrase, name: name ?? this.name);

  Map<String, Object> toJson() => {'id': id, 'name': name ?? '', 'stops': stops};

  /// A saved trip, or null when the entry is not a trip.
  static RostauTrip? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], name = json['name'], stops = json['stops'];
    if (id is! String || name is! String || stops is! List) return null;
    return RostauTrip.custom(id, name, <String>[for (final s in stops) if (s is String) s]);
  }
}

/// Where a stop stands in a walk being followed.
enum StopState { done, current, upcoming }

/// How far the visitor is along a planned walk: [order] holds the stops in
/// walking order (routing node ids), and the first [done] of them are behind
/// them. There is no GPS indoors, so it only moves when the visitor says so:
/// "Arrived", or setting their location at a stop.
class TripProgress {
  const TripProgress(this.order, int done) : _done = done;

  final List<String> order;
  final int _done;

  int get total => order.length;

  /// Stops behind the visitor (a saved count out of range is clamped).
  int get done => _done.clamp(0, total);
  bool get finished => done >= total;

  /// The stop to walk to now, or null once the walk is over.
  String? get next => finished ? null : order[done];

  /// [next]'s number, counting from 1.
  int get nextNumber => done + 1;

  /// Where the walk ends.
  String? get finish => order.isEmpty ? null : order.last;

  List<String> get walked => order.sublist(0, done);
  List<String> get remaining => order.sublist(done);

  /// The stop's number in walking order (from 1), or null if not on the walk.
  int? numberOf(String id) {
    final i = order.indexOf(id);
    return i < 0 ? null : i + 1;
  }

  StopState? stateOf(String id) {
    final i = order.indexOf(id);
    if (i < 0) return null;
    if (i < done) return StopState.done;
    return i == done ? StopState.current : StopState.upcoming;
  }

  /// At the current stop: it is done, and the next one is current.
  TripProgress arrive() => TripProgress(order, finished ? total : done + 1);

  /// The visitor says they are at [node]: if that is a stop still ahead, it and
  /// every stop before it are done.
  TripProgress at(String node) {
    final i = order.indexOf(node);
    return i >= done ? TripProgress(order, i + 1) : this;
  }
}
