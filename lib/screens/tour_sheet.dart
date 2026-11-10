import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../i18n/strings.dart';
import '../services/route_finder.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/gem_ui.dart';
import '../widgets/place_badge.dart';

/// Pinned places as a tour: reorder by hand or let the app find the shortest
/// walking order, then start it as one continuous route.
class TourSheet extends StatefulWidget {
  const TourSheet({
    super.key,
    required this.graph,
    required this.stopIds,
    required this.originId,
    required this.originName,
    required this.onChangeOrigin,
    required this.onStart,
    required this.onRemove,
  });

  final MuseumGraph graph;
  final List<String> stopIds;
  /// Null until the visitor has said where they are.
  final String? originId;
  final String? originName;
  final VoidCallback onChangeOrigin;
  final void Function(List<String> order) onStart;
  final void Function(String id) onRemove;

  @override
  State<TourSheet> createState() => _TourSheetState();
}

class _TourSheetState extends State<TourSheet> {
  late List<String> _ids = List.of(widget.stopIds);
  TourResult? _preview;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  void _recompute() {
    _preview = (_ids.isEmpty || widget.originId == null)
        ? null
        : widget.graph.tour(widget.originId!, _ids, avoidStairs: AppState.instance.avoidStairs, optimize: false);
  }

  void _optimize() {
    if (widget.originId == null) {
      widget.onChangeOrigin();
      return;
    }
    final r = widget.graph.tour(widget.originId!, _ids, avoidStairs: AppState.instance.avoidStairs);
    if (r == null) return;
    setState(() {
      _ids = [...r.order, ...r.skipped];
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pv = _preview;
    final p = context.pal;
    return DraggableScrollableSheet(
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: .94,
      expand: false,
      builder: (context, scroll) => GemSheetFrame(
        expand: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GemEyebrow(S.t('my_tour')),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: widget.onChangeOrigin,
                          child: Row(
                            children: [
                              Icon(widget.originId == null ? Icons.location_searching : Icons.my_location, size: 18, color: p.accent),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  widget.originName == null ? S.t('tour_origin_unset') : S.t('from_here', x: widget.originName!),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 16, color: p.accent, fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(S.t('change'), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted)),
                            ],
                          ),
                        ),
                        if (pv != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${S.t('stops', n: pv.order.length)} · ${S.distance(pv.route.meters)} · ${S.minutes(pv.route.walkTime)}',
                            style: TextStyle(fontFamily: 'Arial', fontSize: 13, color: p.muted, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_ids.length > 1)
                    OutlinedButton.icon(
                      onPressed: _optimize,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: Text(S.t('optimize')),
                      style: gemOutlined(context),
                    ),
                ],
              ),
            ),
            if (pv != null && pv.skipped.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(S.t('skipped', x: pv.skipped.map(S.placeId).join('، ')), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.dark ? const Color(0xffff8a80) : Colors.redAccent)),
              ),
            Divider(height: 1, color: p.line),
            Expanded(
              child: _ids.isEmpty
                  ? Center(child: Padding(padding: EdgeInsets.all(30), child: Text(S.t('tour_empty'), textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Arial', color: p.muted))))
                  : ReorderableListView.builder(
                      scrollController: scroll,
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      itemCount: _ids.length,
                      onReorder: (a, b) => setState(() {
                        if (b > a) b -= 1;
                        _ids.insert(b, _ids.removeAt(a));
                        _recompute();
                      }),
                      itemBuilder: (_, i) {
                        final id = _ids[i];
                        final place = placeById(id);
                        return ListTile(
                          key: ValueKey(id),
                          leading: place == null ? const Icon(Icons.place) : PlaceBadge(place: place, size: 36),
                          title: Text(S.placeId(id), style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w700, fontSize: 15, color: p.ink)),
                          subtitle: place == null ? null : Text(S.category(place.category), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() {
                              widget.onRemove(id);
                              _ids.removeAt(i);
                              _recompute();
                            }),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _ids.isEmpty ? null : () => widget.onStart(_ids),
                  icon: const Icon(Icons.route),
                  label: Text(S.t('start_tour')),
                  style: gemFilled(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
