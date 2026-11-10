import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../i18n/strings.dart';
import '../models/map_models.dart';
import '../services/search_engine.dart';
import '../theme.dart';
import '../widgets/gem_ui.dart';
import '../widgets/place_badge.dart';

/// Asks the visitor where they are. Pops with a place id, or [pickOnMap].
///
/// The app never guesses a starting point: indoors there is no GPS, so every
/// route and tour starts from what the visitor tells us here.
///
/// Layout (top to bottom, nothing overlaps, nothing is stacked in one scroll
/// of competing blocks): header → "pick on the map" → search → either the
/// entrance cards (nothing typed) or the results (typing).
class WhereAmISheet extends StatefulWidget {
  const WhereAmISheet({super.key});

  /// Returned when the visitor wants to tap their spot on the map instead.
  static const String pickOnMap = '__pick_on_map__';

  @override
  State<WhereAmISheet> createState() => _WhereAmISheetState();
}

class _WhereAmISheetState extends State<WhereAmISheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _sheet = DraggableScrollableController();
  final _all = SearchEngine.build(regions: false);

  static const _entrances = ['cx_ticket', 'mb_entrance', 'mg_entrance'];

  @override
  void initState() {
    super.initState();
    // typing needs room: grow the sheet as soon as the field is focused
    _focus.addListener(() {
      if (_focus.hasFocus && _sheet.isAttached) {
        _sheet.animateTo(.94, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final q = _controller.text;
    final typing = q.trim().isNotEmpty;
    final groups = typing ? SearchEngine.search(_all, q) : const <({String key, List<SearchEntry> items})>[];
    final results = [for (final g in groups) ...g.items].take(30).toList();
    final base = TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w700, fontSize: 15, color: p.ink);
    final hit = base.copyWith(color: p.gold);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        controller: _sheet,
        initialChildSize: .62,
        minChildSize: .4,
        maxChildSize: .94,
        expand: false,
        snap: true,
        snapSizes: const [.62, .94],
        builder: (context, scroll) => GemSheetFrame(
          expand: true,
          child: ListView(
            controller: scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // ── header ──
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: p.accent.withValues(alpha: .14), shape: BoxShape.circle, border: Border.all(color: p.accent.withValues(alpha: .5))),
                    child: Icon(Icons.my_location, color: p.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.t('where_now'), style: TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w700, color: p.ink)),
                        const SizedBox(height: 3),
                        Text(S.t('where_hint'), style: TextStyle(fontFamily: 'Arial', fontSize: 12.5, height: 1.35, color: p.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── the primary way: tap the map ──
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(WhereAmISheet.pickOnMap),
                  icon: const Icon(Icons.touch_app_rounded, size: 20),
                  label: Text(S.t('pick_on_map')),
                  style: gemFilled(context),
                ),
              ),
              const SizedBox(height: 16),

              // ── search ──
              TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w600, color: p.ink),
                cursorColor: p.accent,
                decoration: InputDecoration(
                  hintText: S.t('nearby_hint'),
                  hintMaxLines: 1,
                  hintStyle: TextStyle(fontFamily: 'Arial', fontSize: 14, color: p.muted),
                  prefixIcon: Icon(Icons.search, color: p.muted),
                  suffixIcon: typing
                      ? IconButton(
                          icon: Icon(Icons.close, color: p.muted),
                          onPressed: () => setState(_controller.clear),
                        )
                      : null,
                  filled: true,
                  fillColor: p.surfaceHi,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: p.accent, width: 1.4)),
                ),
              ),
              const SizedBox(height: 18),

              // ── body: entrances, or results while typing ──
              if (!typing) ...[
                GemEyebrow(S.t('at_entrance')),
                const SizedBox(height: 10),
                _entranceGrid(p),
              ] else if (results.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text(S.t('no_results'), style: TextStyle(fontFamily: 'Arial', fontSize: 15, color: p.muted))),
                )
              else
                for (final e in results) _resultTile(p, e, q, base, hit),
            ],
          ),
        ),
      ),
    );
  }

  /// Three equal cards that always fit the width, whatever the language.
  Widget _entranceGrid(GemPalette p) {
    final places = [for (final id in _entrances) if (placeById(id) != null) placeById(id)!];
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap * (places.length - 1)) / places.length;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final pl in places) SizedBox(width: w, child: _entranceCard(p, pl))],
        );
      },
    );
  }

  Widget _entranceCard(GemPalette p, MapPlace pl) => Container(
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: p.line.withValues(alpha: .9)),
      boxShadow: gemShadow(p, lift: .5),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(pl.id),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              PlaceBadge(place: pl, size: 34),
              const SizedBox(height: 10),
              // two lines reserved, so the three cards are always the same height
              SizedBox(
                height: 34,
                child: Text(S.place(pl), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w800, fontSize: 13, height: 1.2, color: p.ink)),
              ),
              const SizedBox(height: 4),
              Text(S.mapShort(allMaps[mapIdOfPlace(pl.id)]!), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontSize: 11.5, color: p.muted)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _resultTile(GemPalette p, SearchEntry e, String q, TextStyle base, TextStyle hit) => InkWell(
    onTap: () => Navigator.of(context).pop(e.place!.id),
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PlaceBadge(place: e.place!, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(children: SearchEngine.highlight(e.title, q, base, hit)), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted)),
              ],
            ),
          ),
          Icon(Icons.north_west, size: 16, color: p.line),
        ],
      ),
    ),
  );
}
