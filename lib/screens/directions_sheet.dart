import 'package:flutter/material.dart';

import '../data/gem_map_data.dart';
import '../i18n/strings.dart';
import '../services/route_finder.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/gem_ui.dart';

/// Step-by-step directions for the current route or tour, grouped by map so
/// "inside the building" and "outside" read as separate stages.
class DirectionsSheet extends StatelessWidget {
  const DirectionsSheet({super.key, required this.title, required this.route, required this.onStepTap, required this.onToggleStairs});

  final String title;
  final RouteResult route;
  final void Function(RouteStep) onStepTap;

  /// Called with the new "avoid stairs" value. The screen re-routes.
  final void Function(bool) onToggleStairs;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final avoid = AppState.instance.avoidStairs;

    // rows = section headers (map changes) and steps
    final rows = <Object>[];
    String? lastMap;
    for (final s in route.steps) {
      if (s.mapId != lastMap) {
        rows.add(s.mapId);
        lastMap = s.mapId;
      }
      rows.add(s);
    }

    return DraggableScrollableSheet(
      initialChildSize: .66,
      minChildSize: .38,
      maxChildSize: .94,
      expand: false,
      builder: (context, scroll) => GemSheetFrame(
        expand: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GemEyebrow(S.t('directions')),
                        const SizedBox(height: 4),
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, color: p.ink, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _stat(context, Icons.straighten, S.distance(route.meters)),
                            const SizedBox(width: 14),
                            _stat(context, Icons.directions_walk, S.minutes(route.walkTime)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
              child: Material(
                color: avoid ? p.accent.withValues(alpha: .10) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  activeThumbColor: p.accent,
                  secondary: Icon(avoid ? Icons.accessible_forward : Icons.accessible, color: p.accent),
                  title: Text(S.t('avoid_stairs'), style: const TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w800, fontSize: 14.5)),
                  value: avoid,
                  onChanged: onToggleStairs,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  if (r is String) {
                    final m = allMaps[r];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                      child: GemEyebrow(S.t('in_map', x: m == null ? r : S.mapTitle(m))),
                    );
                  }
                  final s = r as RouteStep;
                  final last = s.kind == StepKind.arrive || s.kind == StepKind.stop;
                  return ListTile(
                    onTap: () => onStepTap(s),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: CircleAvatar(radius: 19, backgroundColor: last ? p.gold : p.accent, child: Icon(s.icon, size: 20, color: p.surface)),
                    title: Text(S.step(s), style: TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w700, fontSize: 15, color: p.ink)),
                    subtitle: s.meters > 4 ? Text(S.distance(s.meters), style: TextStyle(fontFamily: 'Arial', fontSize: 12.5, color: p.muted)) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String text) {
    final p = context.pal;
    return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: p.muted),
      const SizedBox(width: 5),
      Text(text, style: TextStyle(fontFamily: 'Arial', fontSize: 13.5, color: p.muted, fontWeight: FontWeight.w700)),
    ],
  );
  }
}
