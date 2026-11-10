import 'package:flutter/material.dart';

import '../data/gem_stories.dart';
import '../i18n/strings.dart';
import '../theme.dart';
import '../widgets/gem_ui.dart';
import '../widgets/glyphs.dart';

/// A hieroglyph-style sign, drawn with the same vector data as the carved border.
class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.sign, {super.key, this.size = 34, this.color});
  final String sign;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GlyphPainter(sign, color ?? context.pal.gold),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.sign, this.color);
  final String sign;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    paintGlyph(canvas, sign, size.width * .9, color, pen: size.width * .075);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.sign != sign || old.color != color;
}

void showCarvingsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88), child: const _CarvingsSheet()),
    ),
  );
}

void showAboutSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      top: false,
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88), child: const _AboutSheet()),
    ),
  );
}

class _CarvingsSheet extends StatelessWidget {
  const _CarvingsSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ar = S.ar;
    Widget line(String edge, FriezeLine l) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.line.withValues(alpha: .9))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GemEyebrow(edge),
            const SizedBox(height: 10),
            Row(children: [for (final s in l.signs) Padding(padding: const EdgeInsetsDirectional.only(end: 14), child: GlyphIcon(s, size: 38))]),
            const SizedBox(height: 10),
            Text(ar ? l.ar : l.en, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink)),
          ],
        ),
      ),
    );

    return GemSheetFrame(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('carvings'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 8),
            Text(S.t('carvings_intro'), style: TextStyle(fontFamily: 'Arial', fontSize: 14, height: 1.5, color: p.muted)),
            const SizedBox(height: 10),
            Text(ar ? kCaptionTopAr : kCaptionTopEn, style: TextStyle(fontSize: 13, height: 1.4, letterSpacing: ar ? 0 : 1.2, fontWeight: FontWeight.w700, color: p.gold)),
            const SizedBox(height: 4),
            Text(ar ? kCaptionBottomAr : kCaptionBottomEn, style: TextStyle(fontSize: 13, height: 1.4, letterSpacing: ar ? 0 : 1.2, fontWeight: FontWeight.w700, color: p.gold)),
            const SizedBox(height: 18),
            line(S.t('edge_top'), kFriezeTop),
            line(S.t('edge_right'), kFriezeRight),
            line(S.t('edge_bottom'), kFriezeBottom),
            line(S.t('edge_left'), kFriezeLeft),
            const SizedBox(height: 6),
            GemEyebrow(S.t('signs')),
            const SizedBox(height: 10),
            for (final e in kGlyphMeaning.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    GlyphIcon(e.key, size: 34),
                    const SizedBox(width: 14),
                    Expanded(child: Text(ar ? e.value[1] : e.value[0], style: TextStyle(fontFamily: 'Arial', fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ar = S.ar;
    return GemSheetFrame(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GemEyebrow(S.t('about_museum')),
            const SizedBox(height: 6),
            Text(ar ? kEpilogueTitleAr : kEpilogueTitle, style: TextStyle(fontSize: 24, height: 1.2, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: p.gold)),
            for (final para in (ar ? kEpilogueAr : kEpilogue).split('\n\n')) ...[
              const SizedBox(height: 12),
              Text(para, style: TextStyle(fontFamily: 'Arial', fontSize: 15, height: 1.6, color: p.ink)),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
              decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: p.gold, width: 3))),
              child: Text(ar ? kEpilogueClosingAr : kEpilogueClosing, style: TextStyle(fontSize: 16, height: 1.45, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: p.ink)),
            ),
          ],
        ),
      ),
    );
  }
}
