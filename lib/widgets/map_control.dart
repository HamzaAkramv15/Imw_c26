import 'package:flutter/material.dart';

import '../theme.dart';
import 'gem_ui.dart';

/// A round map button. [active] fills it with the accent colour.
class MapControl extends StatelessWidget {
  const MapControl({super.key, required this.icon, required this.tooltip, required this.onTap, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return RoundAction(
      tooltip: tooltip,
      onTap: onTap,
      active: active,
      child: Icon(icon, size: 22, color: active ? p.onAccent : p.accent),
    );
  }
}

/// Zoom in / zoom out as one pill.
class ZoomPill extends StatelessWidget {
  const ZoomPill({super.key, required this.onIn, required this.onOut, required this.inTip, required this.outTip});
  final VoidCallback onIn;
  final VoidCallback onOut;
  final String inTip;
  final String outTip;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget btn(IconData i, String tip, VoidCallback f, BorderRadius r) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: f,
        borderRadius: r,
        child: SizedBox(width: 46, height: 44, child: Icon(i, size: 22, color: p.accent)),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(23), border: Border.all(color: p.line.withValues(alpha: .8)), boxShadow: gemShadow(p)),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.add, inTip, onIn, const BorderRadius.vertical(top: Radius.circular(23))),
            Container(width: 24, height: 1, color: p.line),
            btn(Icons.remove, outTip, onOut, const BorderRadius.vertical(bottom: Radius.circular(23))),
          ],
        ),
      ),
    );
  }
}
