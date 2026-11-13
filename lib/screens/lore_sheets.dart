import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../i18n/translations.dart';
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

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final l = S.lang.index;
    return GemSheetFrame(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GemEyebrow(S.t('about_museum')),
            const SizedBox(height: 6),
            Text(kEpilogue['title']![l], style: TextStyle(fontSize: 22, height: 1.2, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: p.gold)),
            for (final para in kEpilogue['body']![l].split('\n\n')) ...[
              const SizedBox(height: 12),
              Text(para, style: TextStyle(fontFamily: 'Arial', fontSize: 16, height: 1.6, color: p.ink)),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
              decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: p.gold, width: 3))),
              child: Text(kEpilogue['closing']![l], style: TextStyle(fontSize: 16, height: 1.45, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: p.ink)),
            ),
          ],
        ),
      ),
    );
  }
}
