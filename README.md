# GEM Navigator

Interactive map of the Grand Egyptian Museum: four plans (site, main building,
Main Galleries, Tutankhamun Galleries), drawn as a 2.5D scene, with routing,
tours, search and stories, in eight languages.

```
flutter pub get
flutter analyze
flutter test
python3 tools/test_nav.py      # routing-graph checks (needs numpy, scipy, scikit-image, Pillow, rsvg-convert)
python3 tools/render_routes.py /tmp/routes   # sample routes drawn over the walls, per plan
```

## Layout

| Path | What |
|---|---|
| `lib/data/gem_map_data.dart`, `gem_tutankhamun_data.dart` | Places (pins) of each plan |
| `lib/data/gem_regions.dart`, `gem_blocks.dart`, `gem_floors.dart` | Rooms, walls, cases, treads and floors traced from the official plans |
| `lib/data/gem_figures.dart` | **Generated** monuments: upright outlines of both Ramesses II colossi, the Ptolemaic pair, the Merenptah column and the Hanging Obelisk; meshes of the palms and pyramids (`tools/build_figures.py`) |
| `lib/data/gem_nav.dart` | **Generated** routing graph, openings, wall gaps, portals (`tools/build_nav.py`) |
| `lib/data/gem_extras.dart` | Scale, plan labels, eras |
| `lib/services/route_finder.dart` | Router (Dijkstra on the generated graph), directions, tours |
| `lib/i18n/` | Languages (`lang.dart`), all texts (`translations.dart`), lookups (`strings.dart`) |
| `assets/maps/dark/` | Plan artwork shipped with the app (recoloured at load time) |
| `assets/maps/light/` | The plans in their original colours (read by the tools only) |

## Routing

The routing graph is not drawn by hand. `tools/build_nav.py` rasterises each
plan into walkable floor, treads and obstacles (walls, cases, shop units,
statues) from the same data the app draws, then:

1. seeds every place, every door and waypoints along the middle of the floor;
2. grows a geodesic Voronoi diagram of the seeds and joins neighbours along
   their shortest walk, pulled straight where the line stays on the floor;
3. adds straight shortcuts between nodes that see each other;
4. does it twice: with treads (edges flagged `stairs`) and without (step-free).

**Walls.** The canvas raises walls along the outline of every hall, zone and
building. The routing grid closes the same outlines, except where
`tools/walls.py` leaves them open: at an opening (a circle around each door),
and where a Tutankhamun zone meets other floor (that plan colours its themed
areas inside one hall and draws a line only on the outer edge). The gaps are
written to `kWallGaps`, and the canvas draws its walls from that list, so the
drawing and the routing share one source.

So an edge can never pass through a wall, and the script refuses to write a
graph with a dead end, a node off the floor or an unreachable place
(`--check`). `tools/test_nav.py` checks every edge against the walls exactly
as the canvas draws them, and compares route lengths with the best walk on the
floor grid under the same keep-off-the-walls rule. `tools/render_routes.py`
draws sample routes over the walls from the generated Dart data.

Facts the plans cannot show (links between plans and floors, upper-floor
rooms drawn on the ground plan, openings the plan omits) live in
`tools/nav_spec.py`, each with its source.

**Profiles.** *Standard*: shortest practical walk (treads cost 1.6×, the Grand
Staircase 2.5×, the moving walkway and lifts are used when quicker).
*Step-free*: level floor and lifts only. The moving walkway beside the Grand
Staircase is left out of step-free routes: no official source confirms
wheelchair use.

**Openings.** `kDoors` holds the openings: doors and passages (a stretch the plan leaves without a wall, such as the foot of the
Grand Staircase). Each one is a routing node, and the walls are open within
half its width of its centre. Openings the official plan does not draw (the
three between the Grand Hall and the Glass Hall, placed where the plan's aisles
meet the wall, and the door at the plan's "Wheelchair Access" marker that leads
to the lifts) are `verified: false` and flagged in the directions. On the map an
opening is simply a gap in the wall: nothing is drawn across it.

**Directions.** Stairs, lifts and the moving walkway say up or down and the
floor reached ("Take the stairs up to the 1st floor"), followed by "You are
now on the 1st floor". Treads drawn inside a level give "Take the steps (into
Gallery …)": the plans do not show which end is higher, so no direction is
given. Step-free routes never use treads, stairs or the moving walkway.

After changing a plan, a block, a place or the spec:

```
python3 tools/build_nav.py && python3 tools/test_nav.py
```

## Rostau trips

`lib/models/rostau.dart`, `lib/data/gem_rostau.dart`, `lib/services/rostau.dart`.
Rostau (Egyptian *Ra-setau*, "the mouth of the passages") is the trips feature:
seven curated trips named with ancient Egyptian words (per-aa, nebu, Duat,
Maat, djed, ankh, Sekhet-Aaru), each with a title and a catchy line in every
language, and the visitor's own trips (`RostauLibrary`, saved with the app
state; unknown or repeated places are dropped, damaged entries skipped).
`RostauPlanner.plan` orders the stops into the shortest walk (the router's
tour: nearest neighbour, 2-opt, never worse than the listed order) and lists
the highlights the walk passes within 12 m that are not on the trip. The
screens for browsing and editing trips are not built yet.

## Rendering

The model is painted by three stacked painters, each behind its own repaint
boundary: the scene (floor, walls, blocks, monuments), the route and the
names. The route's dashes move continuously while a route is shown; only the
route layer repaints for them. Slabs are ordered once per half-degree of
rotation (pan and zoom never change the order).

## Tools

Python 3 with numpy, scipy, scikit-image, OpenCV and Pillow (plus
`rsvg-convert`). They write the generated Dart data:

| Tool | Writes |
|---|---|
| `build_nav.py` (+ `nav_spec.py`, `navgrid.py`, `walls.py`) | `gem_nav.dart`: routing graph, openings, wall gaps |
| `build_figures.py` (+ `meshkit.py`) | `gem_figures.dart`: monument outlines, palm and pyramid meshes |
| `build_rooms.py` | the Main Galleries rooms in `gem_regions.dart` |
| `build_floors.py`, `build_gallery_walls.py` (+ `svgutil.py`; also need shapely and svgpathtools) | `gem_floors.dart`, the Main Galleries wall strips |
| `test_nav.py`, `render_routes.py` | checks; route renders |

## Languages

English, Arabic (right-to-left), German, French, Russian, Japanese, Korean and
Simplified Chinese. Every text lives in `lib/i18n/translations.dart`, one
column per language. `test/i18n_test.dart` fails if any entry is missing.
Search matches names in every language and folds accents, kana and digit forms.
The long place stories are written in English and Arabic in
`lib/data/gem_stories.dart`, and in the six other languages in
`lib/data/gem_stories_i18n.dart` (stories that repeat another share its text).

## Sources for accuracy

* The plans are the official GEM visitor-guide maps (vector data from the PDF).
* Grand Hall contents (Ramesses II colossus, Sakkara Cannon, Victory Column of
  Merenpetah): the GEM official visitor guide.
* Top of the Grand Staircase: Main Galleries to the left, Tutankhamun to the
  right: *Ancient Egypt* no. 148, "Visiting the Main Galleries".
* Moving walkway beside the staircase; lift for about four wheelchairs:
  the-past.com review, January 2026.
* The statues: see the docstring of `tools/build_figures.py`.
* Gallery themes (Society / Kingship / Beliefs) follow the theme rows printed
  on the official Main Galleries plan.
