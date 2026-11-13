"""Writes docs/i18n-glossary.md: the museum, navigation and history terms the
app uses, side by side in its eight languages, read from the live tables in
lib/i18n/translations.dart (so the glossary never drifts from the app).

    python3 tools/i18n_glossary.py
"""
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
LANGS = ['en', 'ar', 'de', 'fr', 'ru', 'ja', 'ko', 'zh']
STR = r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\""


def rows(table):
    src = open(os.path.join(ROOT, 'lib/i18n/translations.dart'), encoding='utf-8').read()
    body = src[src.index('const Map<String, List<String>> %s' % table):]
    body = body[:body.index('\n};')]
    out = {}
    for m in re.finditer(r"^\s*(%s):\s*\[(.*)\],\s*$" % STR, body, re.M):
        vals = [v[1:-1].replace("\\'", "'") for v in re.findall(STR, m.group(2))]
        if len(vals) == 8:
            out[m.group(1)[1:-1]] = vals
    return out


SECTIONS = [
    ('Plans and floors', 'kUi', ['map_gem_complex', 'map_main_building', 'map_main_galleries', 'map_tutankhamun',
                                 'floor_0', 'floor_1', 'floor_2', 'floor_3']),
    ('Spaces and landmarks', 'kNames', ['Main Entrance', 'Grand Hall', 'Grand Staircase', 'Glass Hall', 'Upper Floors',
                                        'Main Galleries', 'Tutankhamun Galleries', 'Hanging Obelisk',
                                        "Khufu's Boats Museum", 'Pyramids Steps', "Children's Museum"]),
    ('Highlights', 'kNames', ['Colossal Statue of Ramesses II', 'Victory Column of Merenpetah',
                              'Ptolemaic King and Queen Statues', 'Senwosret I Statues',
                              'Ramesses II Statue (San El-Hagar)', 'Sakkara Cannon']),
    ('Services', 'kNames', ['Prayer Room', 'Restroom', 'Clinic', 'Lift', 'Wheelchair Access', 'Information Desk',
                            'Tour Earphones Desk', 'ATM']),
    ('Periods', 'kUi', ['era_era1', 'era_era2', 'era_era3', 'era_era4', 'bc', 'ad']),
    ('Directions', 'kUi', ['step_left', 'step_right', 'step_door', 'step_passage', 'step_steps', 'step_stairs',
                           'step_lift', 'step_travelator', 'step_now_on', 'step_arrive', 'step_in', 'avoid_stairs',
                           'unverified_door']),
    ('Trips', 'kUi', ['trips', 'stop_of', 'stop_next', 'stop_end', 'arrived', 'trip_complete']),
]

NOTES = """
## Conventions

* **Floors.** English, Arabic, German and French count the ground floor as 0
  ("ground floor", "الدور الأرضي", "Erdgeschoss", "rez-de-chaussée"); Russian,
  Japanese, Korean and Chinese call it the 1st (первый этаж, 1階, 1층, 1层).
  The Main Galleries are therefore the "3rd floor" in the first group and the
  4th in the second. Arabic uses the Egyptian «الدور» rather than «الطابق», as
  on signs in Egypt.
* **Egyptian names** follow each language's Egyptology: Ramses II. / Sesostris I.
  (de), Ramsès / Sésostris / Toutânkhamon (fr), Рамсес / Сенусерт / Тутанхамон
  (ru), ラムセス2世 (ja), 람세스 2세 (ko), 拉美西斯二世 (zh), رمسيس الثاني (ar).
  Search also accepts the other common spellings (Ramses, Merneptah, Senusret,
  Sesostris, Cheops, Saqqara, Tutankhamen…) and one or two typos.
* **Brand names** of shops and cafés are never translated.
* **Plurals.** Russian sidesteps declension with a label ("Остановок: 5");
  Arabic uses its dual and the 3–10 plural (`S.count`: محطتان، 5 محطات، 11 محطة).
* **Russian locative.** "You are now on the 2nd floor" needs the floor in the
  locative (на втором этаже), supplied by `S.step`, not by the floor names.
* **Punctuation.** French puts a space before : ; ? ! and inside « »; Arabic
  uses ، ؛ ؟ and « »; Japanese and Chinese use full-width ：、「」/“”.
* **"Sakkara Cannon"** is the spelling of the official GEM visitor guide (for
  the Saqqara King List, a *canon*); the English label adds "(King List)" and
  the other languages give the object's proper name.

## Reviewed 2026-11-13, and what a native speaker should still check

Corrected in this pass: French "Ensuite" (means "afterwards") for the stop to go
to now → "Direction"; French and Arabic arrival lines (gendered "Vous êtes
arrivé", Arabic past tense "وصلت" used as an instruction); Russian "Переход
завершён" ("transition complete") → "Теперь вы на втором этаже"; Russian turns
"у объекта «…»" → "— ориентир: …"; Arabic counts (dual and 3–10 plural); the
story of attraction 5, which described another statue, rewritten in all eight
languages from the Egyptian Gazette's account of the quartzite colossus.

Flagged for a native reviewer (not wrong, but a judgement call):
* ru «Великий памятниками», ko ‘기념물로 위대한 자’, zh “伟大的丰碑建造者”, ja
  「記念建造物において偉大なる者」: renderings of the epithet "Great of Monuments".
* ko 위대한 왕비 for "Great Royal Wife" (Korean Egyptology also uses 정비).
* ar «بعد {x}» for "In 40 m": natural in navigation, but reads as "after".
"""


def main():
    names = rows('kNames')
    ui = rows('kUi')
    out = ['# Terminology glossary', '',
           'Generated by `tools/i18n_glossary.py` from `lib/i18n/translations.dart`.', '']
    for title, table, keys in SECTIONS:
        src = names if table == 'kNames' else ui
        out += ['## ' + title, '', '| ' + ' | '.join(LANGS) + ' |', '|' + '---|' * 8]
        for k in keys:
            if k in src:
                out.append('| ' + ' | '.join(v.replace('|', '\\|') for v in src[k]) + ' |')
        out.append('')
    out.append(NOTES.strip() + '\n')
    path = os.path.join(ROOT, 'docs', 'i18n-glossary.md')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(out))
    print('wrote', path)


main()
