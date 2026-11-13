import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_rostau.dart';
import '../i18n/lang.dart';
import '../i18n/strings.dart';
import '../models/rostau.dart';
import '../services/rostau.dart';
import '../services/route_finder.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/gem_ui.dart';
import '../widgets/place_badge.dart';
import 'lore_sheets.dart';
import 'search_page.dart';

/// The sign drawn for each trip: what the trip's Egyptian name was written with.
String _signOf(RostauTrip t) => switch (t.id) {
  'per_aa' => 'per', // O1, the house
  'nebu' => 'nbw', // S12, the gold collar
  'duat' => 'duat', // N15, star in a circle
  'maat' => 'feather', // H6, the feather of Maat
  'djed' => 'djed',
  'ankh' => 'ankh',
  'sekhet_aaru' => 'reed', // M17, the reed
  _ => 'wat', // N31, a road: the visitor's own trips
};

/// "Nebu · Gold of the Boy King" → ("Nebu", "Gold of the Boy King"): the
/// Egyptian word reads as an eyebrow above the title.
(String?, String) splitTripTitle(RostauTrip t, AppLang l) {
  final s = t.titleIn(l);
  if (t.custom) return (null, s);
  final dot = s.indexOf(' · ');
  if (dot > 0) return (s.substring(0, dot), s.substring(dot + 3));
  final ja = s.lastIndexOf('・'); // Japanese joins with a middle dot
  if (ja > 0) return (s.substring(0, ja), s.substring(ja + 1));
  return (null, s);
}

/// Rostau trips: the curated walks, the visitor's own, and their pinned tour.
/// Tap a trip to see it planned from where the visitor stands, with the
/// highlights the walk passes on the way, then start it on the map.
class RostauSheet extends StatefulWidget {
  const RostauSheet({
    super.key,
    required this.graph,
    required this.originId,
    required this.pinnedCount,
    required this.activeTripId,
    required this.onOpenTour,
    required this.onChooseStart,
    required this.onStart,
    required this.onPlaceTap,
    required this.onMessage,
    this.openTripId,
  });

  final MuseumGraph graph;

  /// Where the visitor said they are; null until they tell us.
  final String? originId;
  final int pinnedCount;

  /// The trip currently drawn on the map, if any.
  final String? activeTripId;

  /// Open straight on this trip instead of the list.
  final String? openTripId;
  final VoidCallback onOpenTour;

  /// Ask where the visitor is, then come back to [tripId] (or the list).
  final void Function(String? tripId) onChooseStart;
  final void Function(RostauTrip trip, List<String> order) onStart;
  final void Function(String placeId) onPlaceTap;
  final void Function(String message) onMessage;

  @override
  State<RostauSheet> createState() => _RostauSheetState();
}

class _RostauSheetState extends State<RostauSheet> {
  late String? _open = widget.openTripId;

  RostauTrip? get _trip => _open == null ? null : RostauLibrary.byId(_open!);

  Future<void> _edit({RostauTrip? trip}) async {
    final r = await Navigator.of(context).push(TripEditorPage.route(trip: trip));
    if (!mounted || r == null) return;
    setState(() {
      if (r is RostauTrip) {
        _open = r.id;
        widget.onMessage(S.t('trip_saved'));
      } else {
        _open = null; // deleted
        widget.onMessage(S.t('trip_deleted'));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return PopScope(
      // back from a trip returns to the list, not to the map
      canPop: trip == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _open = null);
      },
      child: DraggableScrollableSheet(
        initialChildSize: .8,
        minChildSize: .4,
        maxChildSize: 1,
        expand: false,
        builder: (context, scroll) => GemSheetFrame(
          expand: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, .02), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: trip == null
                ? _TripList(
                    key: const ValueKey('list'),
                    scroll: scroll,
                    pinnedCount: widget.pinnedCount,
                    activeTripId: widget.activeTripId,
                    onOpenTour: widget.onOpenTour,
                    onOpen: (t) => setState(() => _open = t.id),
                    onNew: () => _edit(),
                  )
                : _TripDetail(
                    key: ValueKey(trip.id),
                    scroll: scroll,
                    trip: trip,
                    graph: widget.graph,
                    originId: widget.originId,
                    onBack: () => setState(() => _open = null),
                    onChooseStart: () => widget.onChooseStart(trip.id),
                    onStart: (order) => widget.onStart(trip, order),
                    onPlaceTap: widget.onPlaceTap,
                    onEdit: trip.custom ? () => _edit(trip: trip) : null,
                  ),
          ),
        ),
      ),
    );
  }
}

// ── the list ──────────────────────────────────────────────────────
class _TripList extends StatelessWidget {
  const _TripList({
    super.key,
    required this.scroll,
    required this.pinnedCount,
    required this.activeTripId,
    required this.onOpenTour,
    required this.onOpen,
    required this.onNew,
  });

  final ScrollController scroll;
  final int pinnedCount;
  final String? activeTripId;
  final VoidCallback onOpenTour;
  final void Function(RostauTrip) onOpen;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final own = RostauLibrary.custom;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GemEyebrow(S.t('trips')),
                    const SizedBox(height: 4),
                    Text(S.t('trips_title'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.ink)),
                    const SizedBox(height: 4),
                    Text(S.t('trips_sub'), style: TextStyle(fontFamily: 'Arial', fontSize: 14, height: 1.4, color: p.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GlyphIcon('wat', size: 40, color: p.gold),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          leading: _Seal(child: Icon(pinnedCount == 0 ? Icons.bookmarks_outlined : Icons.bookmarks, size: 20, color: p.accent)),
          eyebrow: null,
          title: S.t('my_tour'),
          meta: pinnedCount == 0 ? S.t('tour_empty') : '${S.t('my_tour_hint')} · ${S.count('stops', pinnedCount)}',
          onTap: onOpenTour,
        ),
        const SizedBox(height: 20),
        _SectionHeader(S.t('curated_trips')),
        for (final t in kRostauTrips) ...[
          _TripCard(trip: t, active: t.id == activeTripId, onTap: () => onOpen(t)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        _SectionHeader(
          S.t('your_trips'),
          action: own.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(S.t('new_trip')),
                  style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 14, fontWeight: FontWeight.w800)),
                ),
        ),
        if (own.isEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: p.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('your_trips_empty'), style: TextStyle(fontFamily: 'Arial', fontSize: 14, height: 1.4, color: p.muted)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(S.t('new_trip')),
                  style: gemOutlined(context),
                ),
              ],
            ),
          )
        else
          for (final t in own) ...[
            _TripCard(trip: t, active: t.id == activeTripId, onTap: () => onOpen(t)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 0, 8),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: GemEyebrow(text))),
          ?action,
        ],
      ),
    ),
  );
}

/// The trip's sign in a gold ring.
class _Seal extends StatelessWidget {
  const _Seal({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surfaceHi,
        border: Border.all(color: p.gold.withValues(alpha: .7), width: 1.4),
      ),
      child: child,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.leading, required this.eyebrow, required this.title, required this.meta, required this.onTap, this.phrase, this.active = false});
  final Widget leading;
  final String? eyebrow;
  final String title;
  final String meta;
  final String? phrase;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: active ? p.accent : p.line.withValues(alpha: .9), width: active ? 1.6 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[GemEyebrow(eyebrow!), const SizedBox(height: 2)],
                    Text(title, style: TextStyle(fontSize: 16, height: 1.25, fontWeight: FontWeight.w700, color: p.ink)),
                    if (phrase != null && phrase!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(phrase!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontSize: 14, height: 1.4, color: p.muted)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (active) ...[Icon(Icons.alt_route, size: 14, color: p.accent), const SizedBox(width: 4)],
                        Flexible(child: Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.w700, color: active ? p.accent : p.muted))),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right, color: p.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.active, required this.onTap});
  final RostauTrip trip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (word, title) = splitTripTitle(trip, S.lang);
    return _Card(
      leading: _Seal(child: GlyphIcon(_signOf(trip), size: 26, color: p.gold)),
      eyebrow: word,
      title: title,
      phrase: trip.phraseIn(S.lang),
      meta: S.count('stops', trip.stops.length),
      active: active,
      onTap: onTap,
    );
  }
}

// ── one trip, planned ─────────────────────────────────────────────
class _TripDetail extends StatelessWidget {
  const _TripDetail({
    super.key,
    required this.scroll,
    required this.trip,
    required this.graph,
    required this.originId,
    required this.onBack,
    required this.onChooseStart,
    required this.onStart,
    required this.onPlaceTap,
    required this.onEdit,
  });

  final ScrollController scroll;
  final RostauTrip trip;
  final MuseumGraph graph;
  final String? originId;
  final VoidCallback onBack;
  final VoidCallback onChooseStart;
  final void Function(List<String> order) onStart;
  final void Function(String placeId) onPlaceTap;

  /// Null for a curated trip (they cannot be changed).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final avoid = AppState.instance.avoidStairs;
    final plan = originId == null ? null : RostauPlanner(graph).plan(trip, originId!, avoidStairs: avoid);
    final (word, title) = splitTripTitle(trip, S.lang);
    final order = plan?.tour.order ?? trip.stops;
    final phrase = trip.phraseIn(S.lang);
    final skipped = plan?.tour.skipped ?? const <String>[];

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
            children: [
              Row(
                children: [
                  IconButton(onPressed: onBack, tooltip: S.t('trips_title'), icon: Icon(Icons.arrow_back, color: p.ink)),
                  const Spacer(),
                  if (onEdit != null)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(S.t('edit')),
                      style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (word != null) ...[GemEyebrow(word), const SizedBox(height: 4)],
                          Text(title, style: TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, color: p.ink)),
                          if (phrase.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(phrase, style: TextStyle(fontSize: 16, height: 1.4, fontStyle: FontStyle.italic, color: p.gold)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GlyphIcon(_signOf(trip), size: 44, color: p.gold),
                  ],
                ),
              ),
              // without a start point the button at the bottom asks for one
              if (originId != null) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _StartLine(
                    from: S.t('from_here', x: S.nodeName(originId!)),
                    stats: plan == null ? S.t(avoid ? 'no_step_free' : 'no_path') : '${S.count('stops', plan.tour.order.length)} · ${S.distance(plan.tour.route.meters)} · ${S.minutes(plan.tour.route.walkTime)}',
                    stepFree: avoid,
                    onChange: onChooseStart,
                  ),
                ),
              ],
              if (skipped.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: Text(S.t('skipped', x: S.list(skipped.map(S.placeId))), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.rose)),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _SectionHeader(S.t(plan == null ? 'listed_order' : 'walk_order')),
              ),
              for (final (i, id) in order.indexed) _StopRow(n: i + 1, id: id, onTap: () => onPlaceTap(id)),
              if (plan != null && plan.onTheWay.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _SectionHeader(S.t('on_the_way')),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Text(S.t('on_the_way_hint'), style: TextStyle(fontFamily: 'Arial', fontSize: 14, height: 1.4, color: p.muted)),
                ),
                for (final id in plan.onTheWay) _StopRow(id: id, onTap: () => onPlaceTap(id)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
          child: SizedBox(
            width: double.infinity,
            child: originId == null
                ? FilledButton.icon(
                    onPressed: onChooseStart,
                    icon: const Icon(Icons.my_location, size: 20),
                    label: Text(S.t('choose_start')),
                    style: gemFilled(context),
                  )
                : FilledButton.icon(
                    onPressed: plan == null || plan.tour.order.isEmpty ? null : () => onStart(plan.tour.order),
                    icon: const Icon(Icons.route),
                    label: Text(S.t('start_trip')),
                    style: gemFilled(context),
                  ),
          ),
        ),
      ],
    );
  }
}

class _StartLine extends StatelessWidget {
  const _StartLine({required this.from, required this.stats, required this.stepFree, required this.onChange});
  final String from;
  final String stats;
  final bool stepFree;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onChange,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.my_location, size: 18, color: p.accent),
                const SizedBox(width: 6),
                Flexible(child: Text(from, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: p.accent, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                Text(S.t('change'), style: TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.w700, color: p.muted)),
              ],
            ),
          ),
        ),
        Row(
          children: [
            Flexible(child: Text(stats, style: TextStyle(fontFamily: 'Arial', fontSize: 14, fontWeight: FontWeight.w700, color: p.muted))),
            if (stepFree) ...[const SizedBox(width: 8), Icon(Icons.accessible_forward, size: 16, color: p.accent)],
          ],
        ),
      ],
    );
  }
}

/// A place in a trip: numbered when it is a stop, plain when it is on the way.
class _StopRow extends StatelessWidget {
  const _StopRow({required this.id, required this.onTap, this.n});
  final String id;
  final int? n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final place = placeById(id);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (n != null) ...[
              SizedBox(
                width: 24,
                child: Text('$n', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Arial', fontSize: 14, fontWeight: FontWeight.w800, color: p.gold)),
              ),
              const SizedBox(width: 8),
            ],
            if (place != null) PlaceBadge(place: place, size: n == null ? 32 : 38) else const Icon(Icons.place),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.placeId(id), style: TextStyle(fontFamily: 'Arial', fontSize: n == null ? 14 : 16, fontWeight: FontWeight.w700, color: p.ink)),
                  if (place != null) Text(S.category(place.category), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── the editor ────────────────────────────────────────────────────
/// Name a trip and pick its places. Pops with the saved [RostauTrip], or with
/// [TripEditorPage.deleted] after a delete; null when left unchanged.
class TripEditorPage extends StatefulWidget {
  const TripEditorPage({super.key, this.trip, this.stops = const []});

  /// The trip being changed; null for a new one.
  final RostauTrip? trip;

  /// Places a new trip starts with (e.g. the pinned tour).
  final List<String> stops;

  static const Object deleted = 'deleted';

  static Route<Object?> route({RostauTrip? trip, List<String> stops = const []}) =>
      MaterialPageRoute<Object?>(builder: (_) => TripEditorPage(trip: trip, stops: stops));

  @override
  State<TripEditorPage> createState() => _TripEditorPageState();
}

class _TripEditorPageState extends State<TripEditorPage> {
  late final _name = TextEditingController(text: widget.trip?.name ?? '');
  late final List<String> _stops = List.of(widget.trip?.stops ?? widget.stops);
  late final String _initial = _signature;
  final _toast = ToastController();

  String get _signature => '${_name.text.trim()}|${_stops.join(',')}';
  bool get _dirty => _signature != _initial;

  List<String> get _missing => [
    if (_name.text.trim().isEmpty) S.t('trip_need_name'),
    if (_stops.isEmpty) S.t('trip_need_stops'),
  ];

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _toast.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_stops.length >= RostauLibrary.maxStops) {
      _toast.show(S.t('trip_full', n: RostauLibrary.maxStops), icon: Icons.block);
      return;
    }
    final e = await Navigator.of(context).push(SearchPage.route(placesOnly: true));
    final id = e?.place?.id;
    if (id == null || !mounted) return;
    if (_stops.contains(id)) {
      _toast.show(S.t('already_in_trip'), icon: Icons.info_outline);
      return;
    }
    setState(() => _stops.add(id));
  }

  void _save() {
    final t = RostauLibrary.save(id: widget.trip?.id, name: _name.text, stops: _stops);
    if (t != null) Navigator.of(context).pop(t);
  }

  Future<bool> _confirm(String title, String yes) async {
    final p = context.pal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: p.bg,
        title: Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(S.t('keep_editing'), style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w700, color: p.muted))),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(yes, style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w800, color: p.rose))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _discard() async {
    if (await _confirm(S.t('discard_q'), S.t('discard')) && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final t = widget.trip!;
    if (!await _confirm(S.t('delete_trip_q', x: t.name ?? ''), S.t('delete'))) return;
    RostauLibrary.delete(t.id);
    if (mounted) Navigator.of(context).pop(TripEditorPage.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final missing = _missing;
    return PopScope(
      // leaving with unsaved changes asks first
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard();
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                    child: Row(
                      children: [
                        IconButton(onPressed: () => Navigator.of(context).maybePop(), tooltip: S.t('cancel'), icon: Icon(Icons.close, color: p.ink)),
                        Expanded(
                          child: Text(S.t(widget.trip == null ? 'new_trip' : 'edit_trip'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.ink)),
                        ),
                        FilledButton(
                          onPressed: missing.isEmpty ? _save : null,
                          style: gemFilled(context).copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 10))),
                          child: Text(S.t('save')),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: TextField(
                      controller: _name,
                      autofocus: widget.trip == null && _stops.isEmpty,
                      maxLength: RostauLibrary.maxName,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(fontFamily: 'Arial', fontSize: 16, fontWeight: FontWeight.w700, color: p.ink),
                      cursorColor: p.accent,
                      decoration: InputDecoration(
                        labelText: S.t('trip_name'),
                        labelStyle: TextStyle(fontFamily: 'Arial', color: p.muted),
                        filled: true,
                        fillColor: p.surfaceHi,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.accent, width: 1.4)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                    child: Row(
                      children: [
                        Expanded(child: GemEyebrow(_stops.isEmpty ? S.t('listed_order') : '${S.t('listed_order')} · ${_stops.length}')),
                        TextButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(S.t('add_places')),
                          style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 14, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _stops.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GlyphIcon('wat', size: 52, color: p.line),
                                  const SizedBox(height: 12),
                                  Text(S.t('your_trips_empty'), textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Arial', fontSize: 14, height: 1.4, color: p.muted)),
                                  const SizedBox(height: 14),
                                  OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: Text(S.t('add_places')), style: gemOutlined(context)),
                                ],
                              ),
                            ),
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            itemCount: _stops.length,
                            onReorderItem: (a, b) => setState(() => _stops.insert(b, _stops.removeAt(a))),
                            itemBuilder: (_, i) {
                              final id = _stops[i];
                              final place = placeById(id);
                              return ListTile(
                                key: ValueKey(id),
                                leading: place == null ? const Icon(Icons.place) : PlaceBadge(place: place, size: 36),
                                title: Text(S.placeId(id), style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w700, fontSize: 16, color: p.ink)),
                                subtitle: place == null ? null : Text(S.category(place.category), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted)),
                                trailing: IconButton(
                                  tooltip: S.t('delete'),
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () => setState(() => _stops.removeAt(i)),
                                ),
                              );
                            },
                          ),
                  ),
                  if (missing.isNotEmpty || widget.trip != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: missing.isEmpty
                                ? const SizedBox.shrink()
                                : Text(S.t('trip_needs', x: S.list(missing)), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted)),
                          ),
                          if (widget.trip != null)
                            TextButton.icon(
                              onPressed: _delete,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: Text(S.t('delete')),
                              style: TextButton.styleFrom(foregroundColor: p.rose, textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 14, fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              Positioned(
                top: 64,
                left: 28,
                right: 28,
                child: IgnorePointer(child: Center(child: GemToastHost(toast: _toast.value))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
