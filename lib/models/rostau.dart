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
