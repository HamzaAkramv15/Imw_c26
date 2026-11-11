"""Hand-curated navigation facts that the plans cannot tell on their own.

Everything else (walkable floor, walls, cases, treads, the routing graph and its
paths) is derived from the plans by build_nav.py.  Every entry below says where
it comes from; entries the official material does not settle are marked
`verified=False` and are shown to visitors as such (never as step-free facts).

Sources
  [GUIDE]  GEM official visitor guide (visit-gem.com / gem-pulse.com PDF): Grand Hall
           holds the Ramesses II colossus, the Sakkara Cannon and the Victory Column of
           Merenpetah.
  [AE148]  Ancient Egypt magazine no. 148, "Visiting the Main Galleries" (the-past.com):
           the Main Galleries are entered from the top of the Grand Staircase; left for
           the Main Galleries, right for Tutankhamun.
  [PAST26] the-past.com review, Jan 2026: a moving walkway runs along one side of the
           Grand Staircase (it breaks at points to reach the exhibits) and a lift takes
           about four wheelchairs at a time.
  [PLAN]   the official plans themselves (assets/maps/*.svg come from the PDF).
"""

# ── portals: links between maps or between levels drawn on one plan ──────────
# (a, b, kind, metres, verified_step_free, source)
#   kind: door | stairs | lift | travelator
#   verified_step_free only matters for travelators: a moving walkway has no
#   steps, but no official source says wheelchairs may use it, so it is excluded
#   from wheelchair routes.
PORTALS = [
    # outside → inside: the plaza door of the main building [PLAN]
    ('cx_main_door', 'mb_entrance', 'door', 25, True, 'PLAN'),
    # Grand Staircase from its foot (Senwosret I statues) to the top [AE148]
    ('mb_4', 'mg_entrance', 'stairs', 140, False, 'AE148'),
    # the moving walkway beside the staircase [PAST26]
    ('mb_4', 'mg_entrance', 'travelator', 140, False, 'PAST26'),
    # the lift [PAST26]
    ('mb_lift1', 'mg_entrance', 'lift', 70, True, 'PAST26'),
    ('mb_lift2', 'mg_entrance', 'lift', 70, True, 'PAST26'),
    # rooms on the staircase landings (chips on the official plan) [PLAN]
    ('mb_4', 'mb_6', 'stairs', 50, False, 'PLAN'),
    ('mb_4', 'mb_8', 'stairs', 60, False, 'PLAN'),
    ('mb_4', 'mb_9', 'stairs', 95, False, 'PLAN'),
    ('mb_lift1', 'mb_6', 'lift', 40, True, 'PLAN'),
    ('mb_lift1', 'mb_8', 'lift', 40, True, 'PLAN'),
    ('mb_lift1', 'mb_9', 'lift', 55, True, 'PLAN'),
    # the Tutankhamun Galleries open off the top landing, opposite the Main
    # Galleries [AE148]; their plan is a separate sheet
    ('mg_tut', 'tg_entrance', 'door', 15, True, 'AE148'),
    ('mg_tut', 'tg_exit', 'door', 15, True, 'PLAN'),
]

# Places drawn on the ground plan that are really on an upper level: they are
# reached through PORTALS only, never by walking across the ground plan.
PLACE_FLOOR = {
    'mb_6': 1, 'mb_8': 1, 'mb_9': 2,
    'mb_10': 3, 'mb_11': 3, 'mb_info1': 3, 'mb_info3': 3, 'mb_access2': 3,
    'mg_tut': 3,
}

# "Route to X" means "route to Y": the pin points at another plan.
REDIRECTS = {
    'mb_10': 'mg_tut',
    'mb_11': 'mg_entrance',
    'mb_info3': 'mg_entrance',
    'mb_access2': 'mg_entrance',
    'mb_info1': 'mg_tut',
    'cx_main_building': 'cx_main_door',
}

# ── openings ─────────────────────────────────────────────────────────────────
# Every room the canvas draws with walls (halls, zones, buildings) is closed on
# all sides, in the drawing AND in the routing grid, except at these openings.
# (id, map, x, y, half-width, kind, verified, source); the opening is cut through
# every wall within half-width of (x, y).  kind: door | passage (a stretch the
# plan leaves without a wall).
OPENINGS = [
    # the main building's door on the entrance plaza [PLAN: entrance notch]
    ('cx_main_door', 'gem_complex', 838, 822, 7, 'door', True, 'PLAN'),
    ('mb_main_door', 'main_building', 940, 640, 9, 'door', True, 'PLAN'),
    # the Grand Hall opens onto the foot of the Grand Staircase where the plan
    # draws no wall: from the hall's west corner to where the stair-foot wall begins
    ('mb_stair_foot', 'main_building', 721, 547, 36, 'passage', True, 'PLAN'),
    # beside the "Wheelchair Access" marker the plan places at the staircase wall,
    # leading to the lifts.  The plan draws the wall unbroken there.
    ('mb_access_door', 'main_building', 976, 174, 11, 'door', False, 'PLAN wheelchair-access marker'),
    # the Main Galleries' entrance from the top landing [PLAN]
    ('mg_main_door', 'main_galleries', 1025, 735, 7, 'door', True, 'PLAN'),
]

# Walls that the plan draws without an opening although the spaces on both
# sides are public.  build_nav.py opens them where the plan's own aisles meet
# the wall (the widest clear runs on BOTH sides).  The plan does not show the
# real openings, so these doors are verified=False.
#   (map, a point on the wall (the 'wall' block containing it), number of openings, source)
AISLE_DOORS = [
    # Grand Hall | Glass Hall (commercial area).  The official guide lists the
    # shops and restaurants as part of the visit [GUIDE], so they are reachable.
    ('main_building', (1080, 285), 3, 'GUIDE+PLAN aisles'),
]

# Cost multipliers the generator uses when it lays out paths.
ROAD_COST = 4.0      # crossing an access road on the site plan
STAIR_COST = 1.6     # treads, for standard routes
