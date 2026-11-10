import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../i18n/strings.dart';
import '../theme.dart';
import 'gem_ui.dart';

/// The timeline of the Main Galleries: four equal chips (they always fit the
/// screen). Tap one to light up its galleries on the plan and fade the rest;
/// its name appears in the strip above.
class EraBar extends StatelessWidget {
  const EraBar({super.key, required this.selected, required this.onSelect});
  final String? selected;
  final void Function(String? eraId) onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Era? active;
    for (final e in kEras) {
      if (e.id == selected) active = e;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: active == null
                ? const SizedBox(width: double.infinity)
                : Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.dark ? p.surfaceHi : GemColors.ink.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(16),
                      border: p.dark ? Border.all(color: p.line) : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: p.dark || active.color == GemColors.ink ? Colors.white.withValues(alpha: p.dark ? 1 : 1) : active.color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${S.era(active)} · ${S.chip(active.range)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: 'Arial', fontSize: 12.5, fontWeight: FontWeight.w700, color: p.dark ? p.ink : Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Row(
            children: [
              for (final e in kEras)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _chip(context, p, e, selected == e.id),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, GemPalette p, Era e, bool on) {
    final color = p.pin(e.color);
    return Container(
      decoration: BoxDecoration(
        color: on ? color : p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: on ? color : p.line.withValues(alpha: .8)),
        boxShadow: gemShadow(p, lift: .6),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onSelect(on ? null : e.id),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: 38,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: on ? Colors.white : color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(e.galleries, style: TextStyle(fontFamily: 'Arial', fontSize: 12.5, fontWeight: FontWeight.w800, color: on ? Colors.white : p.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
