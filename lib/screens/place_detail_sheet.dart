import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_stories.dart';
import '../i18n/strings.dart';
import '../models/map_models.dart';
import '../theme.dart';
import '../widgets/gem_ui.dart';
import '../widgets/glyphs.dart';
import '../widgets/place_badge.dart';
import '../widgets/story_block.dart';

/// Bottom sheet for one place, laid out like the design concept:
/// photo (or badge) + eyebrow + title + location chips, an ornamental divider,
/// the story hook with a short preview and a "Discover its story" door to the
/// full text, then Start route / Pin / I'm here in one row.
class PlaceDetailSheet extends StatelessWidget {
  const PlaceDetailSheet({
    super.key,
    required this.place,
    required this.isPinned,
    required this.isRouteTarget,
    required this.isOrigin,
    required this.onPin,
    required this.onRoute,
    required this.onSetOrigin,
    required this.onOpenLinkedMap,
  });

  final MapPlace place;
  final bool isPinned;
  final bool isRouteTarget;
  final bool isOrigin;
  final VoidCallback onPin;
  final VoidCallback onRoute;
  final VoidCallback onSetOrigin;
  final void Function(String mapId)? onOpenLinkedMap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final image = kPlaceImage[place.id];
    final floor = kPlaceFloor[place.id];
    final desc = S.description(place);
    final story = storyFor(place.id);
    final chips = [
      if (floor != null && floor > 0)
        S.floorName(floor).replaceFirst(RegExp(r'^the |^'), ''),
      ...place.chips
          .where(
            (c) =>
                !(floor != null &&
                    ['1st Floor', '2nd Floor', '3rd Floor'].contains(c)),
          )
          .map(S.chip),
    ];
    final number = (place.number ?? '').trim();
    final eyebrow = number.isEmpty
        ? S.category(place.category).toUpperCase()
        : '${S.category(place.category).toUpperCase()}  ·  $number';

    return SafeArea(
      top: false,
      child: GemSheetFrame(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(place: place, image: image),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow,
                          style: TextStyle(
                            fontFamily: 'Arial',
                            fontSize: 11,
                            letterSpacing: 1.8,
                            color: p.gold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          S.place(place),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 23,
                            height: 1.15,
                            color: p.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final c in chips) _Chip(c)],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _Ornament(),
              const SizedBox(height: 12),
              if (story != null) ...[
                Text(
                  S.ar ? story.hookAr : story.hook,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.25,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                    color: p.gold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (S.ar ? story.storyAr : story.story)
                      .split('\n\n')
                      .first
                      .trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 14.5,
                    height: 1.5,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 12),
                _StoryDoor(story: story),
              ] else if (desc.isNotEmpty)
                Text(
                  desc,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 15,
                    height: 1.45,
                    color: p.ink,
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: FilledButton.icon(
                      onPressed: onRoute,
                      icon: const Icon(Icons.near_me_rounded, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isRouteTarget ? S.t('routing') : S.t('start_route'),
                        ),
                      ),
                      style: gemFilled(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: onPin,
                      icon: Icon(
                        isPinned ? Icons.bookmark : Icons.bookmark_border,
                        size: 18,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(isPinned ? S.t('pinned') : S.t('pin')),
                      ),
                      style: gemOutlined(context).copyWith(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: OutlinedButton.icon(
                      onPressed: onSetOrigin,
                      icon: Icon(
                        isOrigin
                            ? Icons.my_location
                            : Icons.location_on_outlined,
                        size: 18,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isOrigin ? S.t('you_are_here') : S.t('im_here'),
                        ),
                      ),
                      style: gemOutlined(context).copyWith(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (place.linkedMapId != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => onOpenLinkedMap?.call(place.linkedMapId!),
                    icon: Icon(Icons.map_outlined, size: 18, color: p.accent),
                    label: Text(
                      S.t('open_plan'),
                      style: TextStyle(
                        fontFamily: 'Arial',
                        fontWeight: FontWeight.w700,
                        color: p.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Photo in a gold frame, or the place badge when there is no photo.
/// Decoded at thumbnail size and faded in, so scrolling and opening stay cheap.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.place, required this.image});
  final MapPlace place;
  final String? image;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (image == null) return PlaceBadge(place: place, size: 56);
    return Container(
      width: 98,
      height: 98,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.gold, width: 2),
        boxShadow: gemShadow(p, lift: .6),
        color: p.surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          image!,
          fit: BoxFit.cover,
          cacheWidth: 300,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) => sync
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 220),
                  child: child,
                ),
          errorBuilder: (_, _, _) =>
              Center(child: PlaceBadge(place: place, size: 48)),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: p.surfaceHi,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 13, color: p.ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Arial',
                fontSize: 12,
                color: p.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ── lotus between two hairlines ──
class _Ornament extends StatelessWidget {
  const _Ornament();
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        Expanded(
          child: Container(height: 1.2, color: p.gold.withValues(alpha: .6)),
        ),
        const SizedBox(width: 10),
        CustomPaint(
          size: const Size.square(26),
          painter: _SignPainter('lotus', p.gold),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1.2, color: p.gold.withValues(alpha: .6)),
        ),
      ],
    );
  }
}

class _SignPainter extends CustomPainter {
  const _SignPainter(this.sign, this.color);
  final String sign;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    paintGlyph(canvas, sign, size.width * .92, color, pen: size.width * .07);
  }

  @override
  bool shouldRepaint(_SignPainter old) =>
      old.sign != sign || old.color != color;
}

/// "Discover its story ›": opens the full text in its own scrolling sheet.
class _StoryDoor extends StatelessWidget {
  const _StoryDoor({required this.story});
  final PlaceStory story;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.surfaceHi,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.gold.withValues(alpha: .55)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .9,
              ),
              child: GemSheetFrame(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                  child: StoryBlock(story),
                ),
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.auto_stories_outlined, color: p.gold, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  S.t('discover_story'),
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                color: p.ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
