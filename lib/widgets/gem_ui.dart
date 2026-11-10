import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../models/map_models.dart';
import '../theme.dart';
import 'gem_glyph.dart';

// ═══════════════════════════════════════════════════════════════
//  One visual language for the whole app: sheets, buttons, toasts,
//  chips. Every popup is built from these so they feel the same,
//  and every colour comes from the palette so dark mode just works.
// ═══════════════════════════════════════════════════════════════

const double kSheetRadius = 28;

/// Soft two-layer shadow: a tight contact shadow plus a wide ambient one.
/// This is what lifts controls off the map and removes the "flat" look.
List<BoxShadow> gemShadow(GemPalette p, {double lift = 1}) => [
  BoxShadow(color: p.shadow.withValues(alpha: p.dark ? .55 : .16), blurRadius: 3 * lift, offset: Offset(0, 1 * lift)),
  BoxShadow(color: p.shadow.withValues(alpha: p.dark ? .45 : .14), blurRadius: 18 * lift, offset: Offset(0, 8 * lift)),
];

/// Rounded sheet with a grab handle. Pass the scrolling content as [child].
class GemSheetFrame extends StatelessWidget {
  const GemSheetFrame({super.key, required this.child, this.expand = false});
  final Widget child;

  /// True inside a DraggableScrollableSheet (the child then fills the frame).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final body = Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(4))),
        const SizedBox(height: 6),
        // ListTiles / InkWells inside the sheet paint on the nearest Material; the frame's
        // coloured DecoratedBox would hide them (and trips a framework assertion).
        if (expand) Expanded(child: Material(type: MaterialType.transparency, child: child)) else Flexible(child: Material(type: MaterialType.transparency, child: child)),
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(kSheetRadius),
        border: Border.all(color: p.line.withValues(alpha: p.dark ? .9 : .6)),
        boxShadow: gemShadow(p, lift: 1.6),
      ),
      child: body,
    );
  }
}

/// Small gold "eyebrow" text above a title.
class GemEyebrow extends StatelessWidget {
  const GemEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(fontFamily: 'Arial', fontSize: 11, letterSpacing: 1.6, color: context.pal.gold, fontWeight: FontWeight.w700),
  );
}

ButtonStyle gemFilled(BuildContext context, {Color? color}) {
  final p = context.pal;
  return FilledButton.styleFrom(
    backgroundColor: color ?? p.accent,
    foregroundColor: p.onAccent,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    textStyle: const TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w800, fontSize: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

ButtonStyle gemOutlined(BuildContext context) {
  final p = context.pal;
  return OutlinedButton.styleFrom(
    foregroundColor: p.accent,
    side: BorderSide(color: p.accent.withValues(alpha: .7), width: 1.4),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    textStyle: const TextStyle(fontFamily: 'Arial', fontWeight: FontWeight.w800, fontSize: 15),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
  );
}

// ── toast ─────────────────────────────────────────────────────────
class ToastData {
  ToastData(this.message, this.icon) : id = _next++;
  static int _next = 0;
  final int id;
  final String message;
  final IconData icon;
}

/// Shows [ToastData] sliding in from the top; replaces plain snack bars so
/// every message (location set, step-free on, no route…) looks the same.
class GemToastHost extends StatelessWidget {
  const GemToastHost({super.key, required this.toast});
  final ValueNotifier<ToastData?> toast;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ValueListenableBuilder<ToastData?>(
      valueListenable: toast,
      builder: (context, t, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(position: Tween(begin: const Offset(0, -.5), end: Offset.zero).animate(anim), child: child),
        ),
        child: t == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : Container(
                key: ValueKey(t.id),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: p.dark ? p.surfaceHi : GemColors.ink.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(20),
                  border: p.dark ? Border.all(color: p.line) : null,
                  boxShadow: gemShadow(p),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, color: p.dark ? p.accent : GemColors.gold, size: 20),
                    const SizedBox(width: 10),
                    Flexible(child: Text(t.message, style: TextStyle(fontFamily: 'Arial', color: p.dark ? p.ink : Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Owns the toast value + its auto-dismiss timer.
class ToastController {
  final ValueNotifier<ToastData?> value = ValueNotifier(null);
  Timer? _timer;

  void show(String message, {IconData icon = Icons.info_outline}) {
    value.value = ToastData(message, icon);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2600), () => value.value = null);
  }

  void dispose() {
    _timer?.cancel();
    value.dispose();
  }
}

// ── round action (menu, tour, zoom…) ──────────────────────────────
class RoundAction extends StatelessWidget {
  const RoundAction({super.key, required this.child, required this.tooltip, required this.onTap, this.badge = 0, this.active = false, this.size = 46});
  final Widget child;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final button = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? p.accent : p.surface,
        border: Border.all(color: p.line.withValues(alpha: .8)),
        boxShadow: gemShadow(p),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(message: tooltip, child: SizedBox(width: size, height: size, child: Center(child: child))),
        ),
      ),
    );
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        PositionedDirectional(
          top: -3,
          end: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: p.gold, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.bg, width: 1.5)),
            child: Text('$badge', style: TextStyle(fontFamily: 'Arial', fontSize: 10.5, fontWeight: FontWeight.w800, color: p.dark ? Colors.black : Colors.white)),
          ),
        ),
      ],
    );
  }
}

// ── the floating search field ─────────────────────────────────────
class SearchPill extends StatelessWidget {
  const SearchPill({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.line.withValues(alpha: .8)),
        boxShadow: gemShadow(p),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: p.dark ? p.surfaceHi : GemColors.teal, border: Border.all(color: p.gold, width: 1.4)),
                  child: Icon(Icons.remove_red_eye_outlined, color: p.gold, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(S.t('search_ph'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Arial', fontSize: 15, color: p.muted, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.search, color: p.ink, size: 22),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── category chips: icon + label, scroll sideways ─────────────────
class CategoryRow extends StatelessWidget {
  const CategoryRow({super.key, required this.categories, required this.selected, required this.onSelect});
  final List<PlaceCategory> categories;
  final PlaceCategory? selected;
  final void Function(PlaceCategory?) onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget chip({required Widget Function(Color) icon, required String label, required bool on, required VoidCallback tap}) {
      final fg = on ? p.onAccent : p.ink;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Container(
          decoration: BoxDecoration(
            color: on ? p.accent : p.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? p.accent : p.line.withValues(alpha: .8)),
            boxShadow: on ? gemShadow(p, lift: .6) : gemShadow(p, lift: .5),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: tap,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon(on ? p.onAccent : p.gold),
                    const SizedBox(width: 7),
                    Text(label, style: TextStyle(fontFamily: 'Arial', fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        clipBehavior: Clip.none,
        children: [
          chip(icon: (c) => Icon(Icons.grid_view_rounded, size: 17, color: c), label: S.t('all'), on: selected == null, tap: () => onSelect(null)),
          for (final c in categories)
            chip(icon: (col) => GemGlyph(c.glyph, size: 18, color: col), label: S.filter(c), on: selected == c, tap: () => onSelect(selected == c ? null : c)),
        ],
      ),
    );
  }
}
