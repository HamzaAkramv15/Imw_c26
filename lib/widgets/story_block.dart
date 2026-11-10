import 'package:flutter/material.dart';

import '../data/gem_stories.dart';
import '../i18n/strings.dart';
import '../theme.dart';

/// The story of a place: a catchy line, the tale in short paragraphs, and a
/// closing thought set apart in gold. Follows the app language.
class StoryBlock extends StatelessWidget {
  const StoryBlock(this.story, {super.key});
  final PlaceStory story;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ar = S.ar;
    final hook = ar ? story.hookAr : story.hook;
    final body = ar ? story.storyAr : story.story;
    final closing = ar ? story.closingAr : story.closing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hook, style: TextStyle(fontSize: 21, height: 1.25, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: p.gold)),
        for (final para in body.split('\n\n')) ...[
          const SizedBox(height: 12),
          Text(para.trim(), style: TextStyle(fontFamily: 'Arial', fontSize: 15, height: 1.6, color: p.ink)),
        ],
        if (closing.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: p.gold, width: 3))),
            child: Text(closing, style: TextStyle(fontSize: 16, height: 1.45, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, color: p.ink)),
          ),
        ],
      ],
    );
  }
}
