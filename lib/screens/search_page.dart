import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../services/search_engine.dart';
import '../theme.dart';
import '../widgets/place_badge.dart';

/// Full-screen search. Understands names (English or Arabic), types ("food"),
/// map names, and NUMBERS: "5" lists gallery 05, attraction 5, restaurant 5,
/// shop 5… grouped by type. Pops with the chosen [SearchEntry].
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  /// Fade + slight rise, to match the other transitions in the app.
  static Route<SearchEntry> route() => PageRouteBuilder<SearchEntry>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => const SearchPage(),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .03),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _all = SearchEngine.build();
  String _filter = 'all';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final q = _controller.text;
    final groups = q.trim().isEmpty && _filter == 'all'
        ? SearchEngine.suggestions(_all)
        : SearchEngine.search(_all, q, filter: _filter);
    final count = groups.fold<int>(0, (n, g) => n + g.items.length);
    final filters = [
      'all',
      ...SearchEngine.order.where((k) => _all.any((e) => e.categoryKey == k)),
    ];

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: p.ink),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: S.t('search_ph'),
                        hintStyle: TextStyle(
                          fontFamily: 'Arial',
                          color: p.muted,
                        ),
                        filled: true,
                        fillColor: p.surfaceHi,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        suffixIcon: q.isEmpty
                            ? Icon(Icons.search, color: p.muted)
                            : IconButton(
                                icon: Icon(Icons.close, color: p.muted),
                                onPressed: () => setState(_controller.clear),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(26),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final k = filters[i];
                  final on = _filter == k;
                  return ChoiceChip(
                    label: Text(
                      k == 'all' ? S.t('f_all') : SearchEngine.groupLabel(k),
                    ),
                    selected: on,
                    onSelected: (_) => setState(() => _filter = k),
                    showCheckmark: false,
                    selectedColor: p.accent,
                    backgroundColor: p.surface,
                    side: BorderSide(color: on ? p.accent : p.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    labelStyle: TextStyle(
                      fontFamily: 'Arial',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: on ? p.onAccent : p.ink,
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: count == 0
                    ? _empty()
                    : ListView(
                        key: ValueKey('$q|$_filter'),
                        padding: const EdgeInsets.only(bottom: 30),
                        children: [
                          if (q.trim().isEmpty && _filter == 'all')
                            _header(S.t('popular'))
                          else if (q.trim().isNotEmpty)
                            Padding(
                              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
                              child: Text(
                                S.t('results_n', n: count),
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  fontSize: 12,
                                  color: p.muted,
                                ),
                              ),
                            ),
                          for (final g in groups) ...[
                            if (!(q.trim().isEmpty &&
                                _filter == 'all' &&
                                g.key == groups.first.key))
                              _header(
                                SearchEngine.groupLabel(g.key),
                                count: g.items.length,
                              ),
                            for (final e in g.items) _tile(e, q),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String text, {int? count}) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Arial',
              fontSize: 11,
              letterSpacing: 1.6,
              color: p.gold,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (count != null) ...[
            SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Arial',
                fontSize: 11,
                color: p.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(SearchEntry e, String q) {
    final p = context.pal;
    final base = TextStyle(
      fontFamily: 'Arial',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: p.ink,
    );
    final hit = base.copyWith(
      color: p.gold,
      backgroundColor: p.gold.withValues(alpha: .12),
    );
    return InkWell(
      onTap: () => Navigator.of(context).pop(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            if (e.place != null)
              PlaceBadge(place: e.place!, size: 42)
            else
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: p.gold.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.crop_square_rounded, color: p.gold),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: SearchEngine.highlight(e.title, q, base, hit),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.number.isEmpty
                        ? e.subtitle
                        : '${S.t('no_n', n: int.tryParse(e.number))} · ${e.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      fontSize: 12.5,
                      color: p.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.north_east, size: 18, color: p.line),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    final p = context.pal;
    return Center(
      key: const ValueKey('empty'),
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore, size: 52, color: p.line),
            const SizedBox(height: 14),
            Text(
              S.t('no_results'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: p.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.t('no_results_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Arial',
                fontSize: 14,
                height: 1.4,
                color: p.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
