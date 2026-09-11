extends Node
# Another autoload (see run_state.gd for the fuller explanation of what
# that means and why it's different from class_name). Holds state for
# whichever field room is CURRENTLY loaded - its type, its layout, which
# blobs in it are already defeated, whether its chest is open, where the
# player was standing. All of that gets thrown away and regenerated
# fresh every time a new room is generated (see load_room() below) -
# it's the room's own temporary state, not something that needs to
# outlive it. That's the split from RunState: RunState holds what has to
# survive the WHOLE run (HP, gold, deck, how many rooms/battles so far);
# RoomState holds what only needs to survive a round trip out of THIS
# room and back (walking into a blob, fighting it, returning here).

# --- Room type + layout generation ---
#
# THE SEAM: everything that wants "the next field room" calls load_room()
# with a type, rather than deciding a type and building content itself.
# That type comes from RunState's run graph now (see run_state.gd's
# _generate_run_graph()) - the room the player is standing in IS
# RunState.current_node, and its type is current_node.room_type. Neither
# load_room() nor anything downstream of it (field_room.gd rendering
# whatever ends up in room_layout) needed to change to fit that in - this
# is exactly the seam that was left for a run-graph generator to hand a
# chosen type to instead of a roll.

# --- Floor line (DECIDED - see DESIGN.md's field movement redesign:
# composition & scale pass) ---
#
# The player's fixed vertical position (see player.gd), and everything
# else's bottom-anchor: every SPAWN_SLOTS/opening-room content position
# below is just an X value now, paired with this Y at the point of use,
# so retuning this ONE number keeps the player, room content, doors, and
# field_room.gd's background sky/ground split all in sync automatically -
# no second number to remember to update alongside it.
#
# LOWERED to 830 from 720 (2026-08-30, walk-line correction pass - see
# docs/REGION_01_v1.md §2) - REPLACES the 720 reasoning below, which
# over-corrected: raising the line to 720 opened ~45% of the frame BELOW
# the walk line as empty, evenly-lit ground, which is the wrong place to
# spend that space. Reference composition puts the character low with
# only a thin cropped foreground band below, and stacks depth ABOVE the
# walk line, between the character and the horizon - not below it. 830
# puts the ground band below the line (830 to the bottom wall's inner
# edge at 1040) at 210px, roughly 19% of the frame - a thin foreground
# crop, not a floor to stand in the middle of - while the ~790px above
# it (73% of the frame, y=40 to 830) is where receding depth belongs and
# where interactables are kept clear of (out of the top third of the
# frame). This value is LIVE-TUNED FRAMING, not derived from a formula
# or a target percentage worked backward - expect it to move again by
# eye, the same "eyeballed number, expect to retune" stance every other
# value on this line already carries.
#
# The two paragraphs below are prior history, both superseded, kept for
# context on how this number got here:
#
# RAISED to 720 from 900 (2026-08-30, spatial framing pass): at 720
# (still against the 1080-height viewport), the ground band below this
# line (720 to the bottom wall's inner edge at 1040) is 320px, roughly
# 30% of the viewport height, with the line itself sitting at ~67% down
# the frame - inside that pass's own 65-70% target. Correct as far as it
# went, but it only budgeted the SIZE of the band below the line, not
# where the resulting empty space would actually read as belonging -
# see the 830 paragraph above for the fix.
#
# The paragraph below is the ORIGINAL 900 rationale (2026-08-27), left
# for history: 900, against the room's 1080-height viewport, put the
# ground band below this line (900 to the bottom wall's inner edge at
# 1040) at 140px, a thin strip near the bottom of the frame - roughly
# 13% of the viewport height - rather than the previous 540 (a
# dead-center split that read as a shelf, not a world, with 500px/46% of
# the frame spent on flat empty ground). Everything from the top wall
# (y=40) down to this line is sky, stretching well up and away above the
# player - the composition ratio a side-scroller wants, not a top-down
# room's half-and-half split.
@export var floor_line_y: float = 830.0

# --- Player visual scale (2026-08-30, spatial framing pass) ---
#
# The single source for Player/Visual's scale, alongside floor_line_y
# above - field_room.gd and field_interior.gd both read this at runtime
# and apply it to their own Player/Visual node instead of each carrying
# its own baked `scale` override (field_room.tscn/pay_house_interior.tscn
# used to duplicate the literal Vector2(0.2, 0.2) independently). One
# number, one place to retune the field character's size, same "second
# number to remember to update alongside it" reasoning floor_line_y's
# own doc already gives for itself.
#
# Does NOT touch Sprite's own internal scale (8, inside player_visual.
# tscn) - that scale is what makes ONE 256px sheet cell fill Visual's
# local space at a consistent size regardless of how small Visual itself
# gets drawn; only the OUTER Visual node's scale is meant to be
# data-driven here.
#
# LOWERED to 0.075 from 0.2 (2026-08-30, spatial framing pass - see docs/
# REGION_01_v1.md §2) - the character was reading at roughly 30% of frame
# height, well past this pass's own 8-12% target ("the world should feel
# larger than the character," Art Direction Bible §9). Starting point for
# live tuning, not a final answer - retune by eye against the new
# floor_line_y above, the same "eyeballed number, expect to retune"
# stance every other value on this line already carries.
#
# RAISED to 0.15 from 0.075 (2026-08-30, second scale pass) - 0.075
# over-corrected, landing around 10% of frame height against a ~20%
# target. A factor of 2.0 on this value. Every entity re-tuned against
# the PREVIOUS player scale in the first pass (field_blob.gd's FIELD_
# VISUAL_SCALE/ENCOUNTER_VISUAL_SCALE, the opening-room NPC's visual_
# scale, the Pay House's root scale, the wreckage heap's silhouette
# size) gets that same 2.0 factor applied alongside this change, to
# preserve the tuned relationships between them rather than let them
# drift out of sync with the player a second time - see field_blob.gd's
# own FIELD_VISUAL_SCALE doc for that pass's full accounting.
#
# LOWERED to 0.107 from 0.15 (2026-09-01, field composition pass) - live
# pixel measurement of the walk sheet's frame-0 opaque bounds (rows 35-225
# of 256, 191px tall) put 0.15 at a measured 0.212 of viewport height;
# 0.107 was derived to land at the ~0.15 target: 0.15 * (162px target /
# 229.2px measured at 0.15) = 0.107 (measured result: 0.151). Deliberately
# NOT re-derived project-wide this time (contrast the two passes noted
# above) - FIELD_VISUAL_SCALE/ENCOUNTER_VISUAL_SCALE and every other
# entity tuned against the old 0.15 are explicitly out of scope for this
# pass; the player-to-enemy ratio is expected to shift and is left for a
# later pass to address. player_shadow_y_offset (field_room.gd) WAS
# recomputed alongside this change, since an unrelated pass could easily
# forget it and produce a floating/sunken shadow - see its own doc.
#
# RAISED to 0.123 from 0.107 (2026-09-01, one-tick size bump - same lever
# as the field composition pass above, a tune not a re-derivation) - a
# +15% bump on the previous value (0.107 * 1.15 = 0.12305, rounded to
# 0.123). Same measurement basis as before (191px opaque span * 8 *
# scale / 1080 viewport height): lands at 0.174, up from 0.151. Still
# deliberately NOT re-derived project-wide - FIELD_VISUAL_SCALE/
# ENCOUNTER_VISUAL_SCALE stay untouched, same out-of-scope call as above.
# player_shadow_y_offset (field_room.gd) WAS recomputed alongside this
# change, same reason as above - see its own doc.
@export var player_visual_scale: float = 0.123

# --- Contact shadows (2026-08-30, grounding-cue pass) ---
#
# One shared soft-ellipse treatment for every field entity's grounding
# cue (see entity_shadow.gd) - centralized here, the same "one place to
# retune" reasoning floor_line_y/player_visual_scale above already
# follow, since a shadow's color/proportions are a single project-wide
# feel decision, not a per-entity one (unlike each entity's own width,
# which entity_shadow.gd measures directly per-instance instead).
@export var entity_shadow_enabled: bool = true
@export var entity_shadow_color: Color = Color(0.28, 0.26, 0.22, 0.45)
# Alpha RAISED from 0.30 (2026-08-30, shadow-tuning pass) - 0.30 read as
# too faint to register as a real grounding cue; 0.45 is still well short
# of a hard/opaque shadow (the asset's own soft edge falloff keeps it
# gentle regardless), just no longer easy to miss.
@export_range(0.0, 2.0, 0.01) var entity_shadow_width_ratio: float = 0.75
# Of the entity's own measured rendered width (see entity_shadow.gd's
# attach() - VisualBounds.compute() supplies that measurement) - under
# 1.0 so the shadow reads as sitting under the figure's footprint rather
# than matching its full silhouette width edge-to-edge.
@export_range(0.0, 1.0, 0.01) var entity_shadow_height_ratio: float = 0.22
# Of the shadow's OWN width (not the entity's), so retuning entity_
# shadow_width_ratio above keeps the ellipse's proportions consistent
# rather than needing a second, independent retune.
@export var entity_shadow_y_offset: float = -18.0
# Shifts every shadow up from VisualBounds' own measured bottom edge
# (2026-08-30, shadow-tuning pass) - VisualBounds.compute() reports the
# lowest OPAQUE pixel, which for a figure with trailing cloth or an
# extended limb sits below the actual ground-contact point (the point
# where weight would actually land), not at it. This is the DEFAULT for
# any entity that doesn't set its own override - see entity_shadow.gd's
# attach() for the override mechanism, and each entity script's own
# shadow_y_offset export (field_npc.gd/field_chest.gd/field_curio.gd/
# field_heap.gd/field_marker.gd, plus field_room.gd's player_shadow_y_
# offset for the player) for which entities needed one and why. Negative
# moves the shadow UP (toward the camera/away from the ground plane, in
# this project's Y-down convention).

@export_range(0.01, 0.5, 0.01) var entity_shadow_footprint_slice_fraction: float = 0.12
# How much of an entity's own measured HEIGHT, from the bottom, its shadow's
# width/centre-x are measured from (2026-09-01, footprint-measurement fix) -
# see VisualBounds.compute_bottom_slice(). A raised weapon arm or a flared
# cape/cloak sits well above the actual ground contact point, so measuring
# the FULL silhouette's width (what this project did before this pass)
# makes the shadow both too wide and centred away from the real footprint -
# see this pass's own investigation report, which found this affecting
# battle's own Wanderer far more visibly than any field entity (a Sprite2D's
# own padded canvas vs. a Polygon2D's own tight vertex data), but the fix
# applies uniformly here since every field consumer already shares this one
# value. 0.12 sits in the pass's own 10-15% target range.

# --- Standard room width (DECIDED - see DESIGN.md's field movement
# redesign: room width tuning pass) ---
#
# Standard combat rooms felt cramped in the side-scroller layout - the
# room this replaced (2300 total/2220 interior) produced only ~2.7s of
# entrance-to-exit walking time, well under a comfortable pace. The math,
# against player.gd's own SPEED (750px/s):
#
#   Target: 4-7 seconds of straight-line walking, entrance to exit, in a
#   single-encounter room (no detours) - fast enough to not feel like a
#   travel-time slog (see DESIGN.md's Room Size note), slow enough to
#   read as an actual space, not a corridor. Picked the middle of that
#   range, ~5.5s, as the design target.
#
#   distance = speed * time = 750 * 5.5 = 4125px (target walking distance)
#
#   Player spawn sits 100px in from the left wall's inner face (40),
#   unchanged by width - that's the ENTRANCE margin, not part of the
#   walk itself. The EXIT door sits 100px in from the right wall's inner
#   face, same margin, mirrored. Both stay fixed regardless of width -
#   only the open floor between them grows or shrinks.
#
#   standard_room_width (total, wall-to-wall outer edge) = walking
#   distance + entrance margin + exit margin + both walls' own 40px
#   thickness = 4125 + 100 + 100 + 80 = 4405, rounded to a clean 4400.
#
#   Actual resulting walk: entrance (x=140) to exit (x=4260, see field_
#   room.gd's EXIT_X) = 4120px / 750px/s = 5.49s - lands almost exactly
#   on the 5.5s target, comfortably inside the 4-7s window (3000-5250px
#   / 4.0-7.0s at this speed).
#
# Widening for 2-encounter rooms or the opening room's extra biome
# dressing (PROPOSED, not built this pass): +20% (standard_room_width *
# 1.2 ~= 5280) reads as sensibly roomier without undercutting the same
# walking-time reasoning above - two encounters plus a chest need more
# breathing room than one, but the room shouldn't take proportionally
# twice as long to cross end to end. Not implemented as a real per-room-
# type variant yet - every room (including the opening room) still
# shares this one width, same as before this pass; only the NUMBER
# changed. Building real per-room-type width is a bigger structural
# change (every hand-placed position in this file and field_room.gd
# would need its own width-relative math, not just a bigger constant)
# than this pass's scope covers.
#
# Retuned DOWN after playtesting the 4400 value above - it read as too
# wide in practice, even though it hit the walking-time math on paper.
# 2800 removes ~75% of the 2100px this pass had added over the original
# 2300 (2300 + 0.25*2100 = 2800) - a feel-based correction on top of the
# time-based math, not a rejection of it. Walking time at 2800: (2800 -
# 280 [both margins + both walls' thickness, see the math above]) / 750
# = 3.36s - now under the original 4-7s target, which is expected and
# fine; the target was a starting estimate to reason from, not a hard
# requirement once real playtesting feedback exists to weigh against it.
@export var standard_room_width: float = 2800.0

# THE single derived accessor for the project's own configured viewport
# width (2026-08-29, single-screen COMBAT pass) - reads display/window/
# size/viewport_width straight from ProjectSettings rather than a
# hardcoded 1920, so a future resolution change propagates here (and
# everywhere below that calls this) automatically. A function, not a
# const - GDScript consts can't be initialized from a function call, and
# this project has no other place that caches project settings into a
# var at startup, so recomputing on each call (a cheap Dictionary lookup)
# matches the existing "read it plainly, cache nothing" style everything
# else in this file already uses for RoomState's own exported numbers.
func viewport_width() -> float:
	return ProjectSettings.get_setting("display/window/size/viewport_width")

# The field camera's zoom, tunable here rather than as a Camera2D export
# on field_room.tscn (2026-09-06, field-pull-back pass) - RoomState is an
# always-loaded autoload, the field camera isn't: RoomState.load_room()
# generates a room's placement zones (exit x, content bounds - see
# combat_room_width()/room_width() below) and THEN calls SceneTransition.
# go_to("res://field_room.tscn") (see load_room()'s own doc), which tears
# down whatever scene is currently active and builds a fresh one - there
# is no live Camera2D to read a zoom off of at the point placement zones
# are generated, for any room, ever. Living here instead means both
# sides of that split (generation, before the scene exists; field_
# camera.gd's own _ready(), after) read the exact same live value.
# Starting value ~17.6% wider than the previous fixed zoom of 1.0 (1 /
# 0.85) - a first guess to tune from, not a final number.
@export var field_zoom: float = 0.85

# COMBAT's own width override - now DERIVED from the project's own
# viewport width AND field_zoom above (2026-08-29, single-screen pass,
# REPLACES the earlier 1400.0 half-width default; made zoom-aware 2026-
# 09-06, field-pull-back pass), so a COMBAT/TREASURE room stays exactly
# one screen wide - matching whatever the camera actually shows - at
# ANY configured zoom, not just 1.0.
#
# A FUNCTION, not a stored export with a computed default, specifically
# because a stored `@export var combat_room_width: float = viewport_
# width() / field_zoom` would be wrong: GDScript evaluates a member's
# default expression during _init(), using only field_zoom's own
# script-level default at that point - never whatever override ends up
# saved on the RoomState node in room_state.tscn (the exact mechanism
# entity_shadow_color/treasure_chest_a_offset/etc. already use for
# tuning there). Dragging field_zoom in the inspector would then silently
# stop affecting this value the moment it's saved. Recomputing fresh on
# every call reads field_zoom's actual current value instead, however it
# got set. Every other room type keeps using standard_room_width,
# completely unaffected.
func combat_room_width() -> float:
	return viewport_width() / field_zoom

# THE single shared "room's actual current width" accessor (2026-08-29,
# placement-zone fix; made a genuine cross-file call 2026-09-06, _room_
# width() dedup - see this pass's own report) - PUBLIC (no leading
# underscore) specifically so field_room.gd can call it directly instead
# of keeping its own copy. Room layout generation (_min_content_x()/
# _max_content_x()/_exit_x() below, which route through this instead of
# reading standard_room_width unconditionally) runs HERE, before field_
# room.tscn exists to ask its own rendering-side callers about anything
# (see EXIT_MARGIN's own comment below for the same lifecycle reason
# WALL_INSET/EXIT_MARGIN are still duplicated rather than shared) - but
# nothing about the WIDTH VALUE itself is generation-specific, so once
# field_room.tscn's rendering code exists later in the same room's
# lifecycle, it reads this exact function too rather than a second copy.
# That second copy used to exist, and used to disagree with this one on
# TREASURE specifically (COMBAT-only here vs. COMBAT-or-TREASURE there) -
# invisible before the dedup because TREASURE's own _generate_treasure_
# layout() never calls room_width()/_exit_x()/_min_content_x()/_max_
# content_x() (its chest positions are fixed offsets from spawn_x, not
# rejection-sampled placement - see that function's own doc), so the gap
# never actually fired. Folded in below so this function now really is
# the "same branch, same exclusion" single source of truth field_room.gd
# depends on for TREASURE's own single-screen framing.
func room_width() -> float:
	var is_single_screen := current_room_type == RoomType.Kind.COMBAT or current_room_type == RoomType.Kind.TREASURE
	if is_single_screen and RunState.current_node != RunState.opening_node:
		return combat_room_width()
	return standard_room_width

@export var max_encounters_per_room: int = 2
# Hard cap on how many separate encounter blobs (fights) a single combat
# room can generate - the ONE number every blob-count roll respects (see
# _pick_blob_count() below), so a room can never exceed this regardless
# of room type or width. one_blob_weight/two_blob_weight/three_blob_
# weight (below) stay real, meaningful weights rather than dead config -
# _pick_blob_count() only offers whichever counts are <= this cap to
# WeightedRandom.pick() in the first place, so a count above the cap
# never has a chance to be rolled at all (not rolled-then-clamped, which
# would silently distort the odds of whatever it got clamped down to).
# Raising this later (as the enemy roster grows enough to support denser
# rooms) is the only change needed - three_blob_weight is already there,
# just excluded from the roll while the cap sits at 2.
@export var one_blob_weight: float = 40.0
@export var two_blob_weight: float = 40.0
@export var three_blob_weight: float = 20.0

@export var encounter_chance: float = 0.5
# Chance any given combat blob (see _generate_combat_layout()) is
# replaced by an AUTHORED EncounterData instead of a single random enemy
# - see EncounterPool.pick_random() and DESIGN.md's Bestiary: Authored
# encounters. Rolls against the GENERAL pool only (EncounterPool.
# ENCOUNTER_FOLDER) - elite content (the Wardling, Twin Glasswings) moved
# to its own dedicated pool, only reachable through the ELITE room type
# now (see _generate_elite_layout() and DESIGN.md's ELITE Rooms section).
# Gated behind _past_first_layer() - a deliberately harder fight
# shouldn't ambush the player's very first battle of the run.
#
# Raised from 0.15 to 0.3 then to 0.5 (2026-08-29, "more Gun/Supply and
# Mushroom Patch" pass, target-percentage retune) - tuned alongside
# EnemyPool/EncounterPool's own per-enemy pool_weight (see gun_supply.
# tres/mushroom_patch.tres/beachwrack.tres/sputter.tres) to hit an exact
# target split for layers 1-5, the run's own early stretch: 35% Sputter
# (solo, Tideworn's own former share - see Sputter's retirement-of-
# Tideworn pass), 15% Beachwrack, and the remaining 50% split across the
# encounter pool (originally just Gun/Supply 35% + Mushroom Patch 15%;
# Sputter/Mushroom - formerly Tideworn/Mushroom - joined the same pool
# later at weight 5.0 - see EncounterPool.ENCOUNTER_FOLDER's own contents
# - so that 50% is now a 3-way split rather than the original 35/15
# two-way one). 0.5 is that encounter-pool half's own total share; the
# matching 3:7 Beachwrack:Sputter weight split covers the solo half. A
# flat rate across every layer, not a per-layer curve (no such knob
# exists here) - Outbound joining the single-enemy pool at layer 6 (see
# EnemyData.min_layer) means layers 6+ land on a different,
# uncompensated-for-this-split mix; its own pool_weight was bumped from
# 0.5 to 1.5 in the same pass specifically so it doesn't get crowded out
# to near-zero by Sputter's (formerly Tideworn's) weight, but no attempt
# was made to hit a specific target percentage for it.

const CHEST_CHANCE := 0.6
const COMBAT_CHEST_GOLD_MIN := 15
const COMBAT_CHEST_GOLD_MAX := 25

@export var treasure_chest_gold_min: int = 40
@export var treasure_chest_gold_max: int = 60
# Chest A's (gold) own tunable range (2026-08-29, three-chest treasure
# room) - PROMOTED from TREASURE_CHEST_GOLD_MIN/MAX consts, per this
# pass's own "nothing hardcoded" brief. "Current behavior" otherwise
# unchanged: a flat randi_range() roll, granted the instant Chest A
# opens (see field_chest.gd's own _grant_gold()).

const COMBAT_CHEST_WEAPON_CHANCE := 0.0
const TREASURE_CHEST_WEAPON_CHANCE := 0.15
# UNREFERENCED as of the three-chest treasure room (2026-08-29) - a
# weapon used to be a CHANCE layered on top of the single treasure
# chest's own gold roll; now it's Chest C's own dedicated, GUARANTEED
# job (see _generate_treasure_layout() below and field_chest.gd's
# _offer_weapon()), so nothing rolls against this any more. Left in
# place and flagged rather than deleted, same "flag, don't delete"
# treatment CHEST_CHANCE/COMBAT_CHEST_* got when COMBAT's own chest was
# removed entirely (see the comment a few lines below this one).

@export var shop_stock_min: int = 3
@export var shop_stock_max: int = 4
# How many cards a SHOP room offers - rolled once, see _generate_shop_
# layout(). COMMON/RARE only, same tier cap as reward_screen.gd's regular
# card-choice reward (ULTRA_RARE stays a gift-only tier - see DESIGN.md's
# Rewards note: cards are drops, not currency, and that philosophy holds
# doubly hard for anything sold outright).

@export var shop_common_weight: float = 70.0
@export var shop_rare_weight: float = 24.0
# Its own weights, not reward_screen.gd's common_weight/rare_weight - kept
# independent (even though the defaults currently match) since reward_
# screen.gd is a per-scene Node2D script, not a shared singleton RoomState
# could reach into, and the shop's own rarity mix is a real, separately
# tunable thing (a shop that skews rarer than random drops is a
# legitimate design later).

@export var min_separation_px: float = 400.0
# How close two pieces of content (blobs and/or a chest, today's only
# combination - see _place_content_positions() below) are allowed to
# land to each other, REGARDLESS of type - one flat, generous constant
# for everything, not per-type math (2026-08-27, blob-overlap fix -
# DECIDED not to size this against each blob's own real rendered width
# the way the old 2-blob-only check did, on purpose: a single shared
# floor is simpler to reason about and was explicitly asked for over a
# more "correct" per-type version). Sized against the room's ACTUAL
# current geometry, not guessed: interior_width is 2720px, and the valid
# placement zone (_min_content_x()..._max_content_x()) is 1296px wide.
# Worst case today - 2 blobs + a chest, 3 items in that same 1296px zone
# - needs at minimum 2 * this value reserved for the two gaps between
# them; at 400 that's 800px, leaving 496px (~38% of the zone) of genuine
# slack to place them in, comfortably fittable well before max_placement_
# attempts below runs out. Re-check this math if standard_room_width,
# entrance_clearance_fraction, or exit_clearance_fraction ever change -
# it describes THIS zone width, not a universal constant (same caveat
# this pass's own SPAWN_SLOT_FRACTIONS fix flagged elsewhere).
@export var max_placement_attempts: int = 30
# How many candidate positions _place_content_positions() tries before
# giving up on true separation and falling back to whatever candidate
# came closest (see that function's own doc) - generous relative to how
# rarely the fallback should actually be needed (see min_separation_px's
# own worst-case math above), so a logged fallback is a real signal the
# room genuinely ran out of room, not just an unlucky roll.

@export var escaping_enemy_exit_gap_px: float = 50.0
@export var escaping_enemy_zone_width_px: float = 300.0
# Where an ESCAPING enemy (EnemyData.escape_distance_max > 0.0 - today,
# only Outbound - see _generate_combat_layout()'s own doc) lands, and how
# much of the room stays reserved for everything else placed alongside
# it (2026-08-27, escaping-enemy-position pass). Deliberately identified
# by the mechanic flag, not a hardcoded enemy name - a future second
# escaping enemy gets this placement rule for free, automatically, the
# same way it already gets the rest of the escape mechanic for free.
#
# escaping_enemy_exit_gap_px is the distance back from _max_content_x()
# (the room's own hard, never-relaxed exit-clearance boundary) to the
# NEAR edge of a reserved zone escaping_enemy_zone_width_px wide - the
# enemy lands at a random point inside that zone, not a single fixed
# spot, for the same "some placement variety, not a deterministic same-
# spot-every-time" reasoning ordinary content placement already has.
# Both are FEEL values, not derived from anything - "close-ish to the
# exit" is a live, `Read the room` judgment call, expected to be retuned
# directly here once seen live, same spirit as min_separation_px's own
# doc on that. 50/300 are a starting point: comfortably inside _max_
# content_x() at the room's current 1296px-wide valid zone, not derived
# from it.

@export var boss_exit_gap_px: float = 50.0
@export var boss_zone_width_px: float = 300.0
# Where the BOSS blob lands (2026-08-29, "walk up to the boss" pass) -
# same reserved-zone shape escaping_enemy_exit_gap_px/escaping_enemy_
# zone_width_px above already established for the opposite mechanic
# (an enemy that runs AWAY from the player): boss_exit_gap_px is the
# distance back from _max_content_x() (the room's own hard exit-
# clearance boundary) to the NEAR edge of a reserved zone boss_zone_
# width_px wide, and the boss lands at a random point inside that zone,
# not a single fixed spot - same "some placement variety, not a
# deterministic same-spot-every-time" reasoning. Exists because a BOSS
# room's own _generate_boss_layout() used to call _place_content_
# positions(1) with NO zone override at all, rolling anywhere across the
# room's full [_min_content_x(), _max_content_x()] zone (1296px wide at
# today's standard_room_width) - close enough to entrance_clearance's
# own 30%-in boundary often enough that the boss could read as right on
# top of the player the instant they walked in, instead of a real
# distance to close. Pinning the boss to the FAR side of that same zone
# (today: roughly the rightmost 23% of it) guarantees the walk-up
# distance the fight's own dramatic weight calls for, every run, not
# just on a lucky roll.

const WALL_INSET := 40.0 # Matches field_room.gd's ROOM_FLOOR_LEFT_X - the wall's own collision thickness.

# How far a standard room's spawn point sits past the left wall's inner
# face (WALL_INSET) - matches field_room.tscn's baked Player position
# (140 = WALL_INSET + this), and mirrors field_room.gd's own EXIT_MARGIN
# (the exit's equivalent distance in from the RIGHT wall). Needed here,
# not just in the .tscn, because the entrance-clearance rule below has to
# measure FROM this exact point, not from the wall - see _min_content_x().
const ENTRANCE_MARGIN := 100.0

func _standard_spawn_x() -> float:
	return WALL_INSET + ENTRANCE_MARGIN

# --- Entrance clearance (DECIDED - see DESIGN.md's Run Structure &
# Navigation: entrance clearance) ---
#
# No room content of any kind - encounters, chests, event markers, shop
# markers, or any future placeable type - may be placed within this
# fraction of a room's walkable width, measured from the player's own
# entrance/spawn point (NOT the wall behind it, which sits ENTRANCE_
# MARGIN further back - see _min_content_x()). A fraction of the room's
# own walkable width, not a fixed pixel value, so the same rule holds
# correctly at any standard_room_width AND at the opening room's own
# spawn point (see opening_room_player_spawn_x below) without needing a
# second, room-specific number. Generalizes what used to be a much
# looser, effectively-10%-margin convention baked into SPAWN_SLOT_
# FRACTIONS' own smallest value (0.1) - that margin was never actually
# enemy-specific (chests/markers drew from the exact same list), but it
# WAS measured from the wall rather than the true spawn point, and the
# opening room's hand-placed positions (see OPENING_ROOM_ENEMY_X below)
# bypassed it entirely rather than respecting any shared number - both
# gaps this rule closes.
@export var entrance_clearance_fraction: float = 0.3

func _min_content_x(spawn_x: float) -> float:
	var interior_width := room_width() - 2.0 * WALL_INSET
	return spawn_x + entrance_clearance_fraction * interior_width

# --- Exit clearance (DECIDED - see DESIGN.md's Run Structure &
# Navigation: exit clearance) ---
#
# The enemy-only counterpart to entrance clearance above: no enemy blob
# may spawn within this fraction of the room's walkable width of the
# exit door - an enemy near the exit makes it ambiguous whether moving
# right triggers a fight or advances the run. Unlike entrance clearance,
# this is scoped to enemies specifically (see _place_blob_positions()),
# not every content type - a chest or event marker near the exit was
# never the actual problem this rule exists to solve, and filtering them
# too would shrink their own placement variety for no reason.
@export var exit_clearance_fraction: float = 0.15

const EXIT_MARGIN := 100.0
# Mirrors field_room.gd's own EXIT_MARGIN constant - same "duplicated on
# purpose" reasoning WALL_INSET already carries above (matches ROOM_
# FLOOR_LEFT_X): room layout is generated here, before field_room.tscn
# exists to ask directly, so _exit_x() below needs its own copy of the
# same number rather than a cross-scene dependency on a script that
# hasn't loaded yet. Routed through room_width() now (2026-08-29,
# placement-zone fix), not standard_room_width directly - see that
# function's own doc for why reading the wrong width here was a real
# bug, not just a naming nicety.
func _exit_x() -> float:
	return room_width() - WALL_INSET - EXIT_MARGIN

func _max_content_x(exit_x: float) -> float:
	var interior_width := room_width() - 2.0 * WALL_INSET
	return exit_x - exit_clearance_fraction * interior_width

# THE single shared entry point every room-content layout generator below
# calls (_generate_combat_layout(), _generate_treasure_layout(),
# _generate_marker_layout(), _generate_boss_layout(), _generate_elite_
# layout() - _generate_shop_layout() goes through _generate_marker_
# layout()) - one function, one placement algorithm, so a content type
# can't accidentally bypass separation by rolling its own position a
# different way (2026-08-27, blob-overlap fix - REPLACES the old split
# between _place_blob_positions()'s continuous-random-with-an-ad-hoc-
# pairwise-check for blobs, and a separate fixed 5-point SPAWN_SLOT_
# FRACTIONS grid for chests/markers/boss/elite - the two systems never
# knew about each other, which is exactly how a chest ended up able to
# land on top of an enemy blob).
#
# Rejection sampling within [_min_content_x(), _max_content_x()] - the
# only zone that clears BOTH entrance and exit clearance, which are never
# relaxed (see this room's own constraint doc): for each of `count` items
# (blobs and/or a chest today, in whatever order the caller wants
# positions back), try up to max_placement_attempts random candidates,
# accept the first one at least min_separation_px from every already-
# placed item THIS ROOM (regardless of what type it is), and track
# whichever candidate came closest along the way. If every attempt fails,
# fall back to that best candidate and log a warning - the room is
# genuinely crowded (min_separation_px's own doc works out the expected
# worst case at today's room width), so this should be rare, not a
# routine occurrence silently papering over a bad roll.
#
# ONE flat min_separation_px for every item regardless of type/size, not
# per-blob-width math the way the old 2-blob check computed a required
# gap from each sprite's own real rendered width - deliberately simpler,
# per this pass's own brief ("one generous constant... not per-type
# math"). Revisit with real per-type sizing later if a generous flat
# floor ever proves too loose or too tight for a specific content type.
#
# zone_min/zone_max default to the room's own full entrance/exit-
# clearance zone (-INF is a sentinel, not a real bound - GDScript default
# parameters can't call functions, so the real values are resolved
# inside the body instead). The ESCAPING-enemy pass (2026-08-27 - see
# escaping_enemy_exit_gap_px/escaping_enemy_zone_width_px's own doc)
# is the one caller that overrides these: everything placed ALONGSIDE
# a reserved escaping enemy is bounded to the room's LEFT of it, not the
# full zone, which is what makes "always last" true by construction
# rather than by chance.
func _place_content_positions(count: int, zone_min: float = -INF, zone_max: float = -INF) -> Array[float]:
	var min_x := zone_min if zone_min != -INF else _min_content_x(_standard_spawn_x())
	var max_x := zone_max if zone_max != -INF else _max_content_x(_exit_x())
	var placed: Array[float] = []
	for i in count:
		var best_candidate := 0.0
		var best_distance := -1.0
		var accepted := false
		for attempt in max_placement_attempts:
			var candidate := randf_range(min_x, max_x)
			var distance := _distance_to_nearest(candidate, placed)
			if distance > best_distance:
				best_distance = distance
				best_candidate = candidate
			if distance >= min_separation_px:
				accepted = true
				break
		if not accepted:
			push_warning("RoomState: placement fallback for item %d/%d - best candidate found was only %.1fpx from its nearest neighbor (min_separation_px=%.1f, zone width=%.1f, %d attempts)." % [i + 1, count, best_distance, min_separation_px, max_x - min_x, max_placement_attempts])
		placed.append(best_candidate)
	return placed

func _distance_to_nearest(candidate: float, placed: Array[float]) -> float:
	if placed.is_empty():
		return INF
	var nearest := INF
	for p in placed:
		nearest = minf(nearest, absf(candidate - p))
	return nearest

var current_room_type: RoomType.Kind = RoomType.Kind.COMBAT

# How far inland the current room sits, normalized 0.0 (the run's very
# start) to 1.0 (the boss) - Region 1's wet-to-dry gradient is driven by
# this (docs/REGION_01_v1.md §§3-4: room depth, not room type, is what
# should read as "further from the shore"). RunState.current_node.layer
# and RunState.layer_count are the raw truth this is derived from -
# RunState owns what has to survive the whole run, RoomState stages the
# derived convenience field_room.gd actually reads, same split this
# file's own header already describes for everything else it holds.
# Computed ONCE per room by load_room() below (see _compute_region_
# progress()), not recomputed on every read - same "generated once, just
# read afterward" shape room_layout already uses.
var region_progress: float = 0.0

# --- Opening room variant switch (EXPERIMENTAL, dev/test only - see
# DESIGN.md's Run Structure & Navigation: opening room) ---
#
# Which visual treatment field_room.gd's opening-room-only styling
# applies (see its _apply_opening_room_layout()) - the coastal beach, or
# a parallel industrial/space-adjacent prototype built purely for a
# side-by-side aesthetic comparison, not a commitment. Real run
# generation never touches this; it only ever changes via the two "Dev:
# Opening Room" buttons on the title screen (see title_screen.gd),
# which exist purely to preview each direction on demand. Nested here
# (not its own file, unlike RoomType.Kind) since nothing needs this as
# a TYPE elsewhere - only as a value read off this singleton, the same
# distinction RoomType.Kind's own header comment explains. Delete this
# field (and the two title-screen buttons, and field_room.gd's
# industrial-specific code) to remove the industrial option entirely if
# the coastal direction wins.
enum OpeningRoomVariant { COASTAL, INDUSTRIAL }
var opening_room_variant: OpeningRoomVariant = OpeningRoomVariant.COASTAL

# What's in the current room, generated ONCE by load_room() and then just
# read (never re-rolled) by field_room.gd every time it renders - see
# _generate_layout() below. Each entry is a small Dictionary shaped like
# one of:
#   {"kind": "blob", "id": "blob_0", "position": Vector2(...)}
#   {"kind": "chest", "chest_id": "chest_gold", "reward_kind": FieldChest.RewardKind.GOLD, "position": Vector2(...), "min_gold": 40, "max_gold": 60}
#   {"kind": "marker", "position": Vector2(...)}
#   {"kind": "structure", "structure_id": "pay_house", "position": Vector2(...)}
# Generating this once and holding onto it (rather than field_room.gd
# re-rolling on every _ready()) is what keeps a room's contents stable
# across a "walk into a blob, fight it, come back" round trip - without
# it, the whole room would reshuffle underneath the player every time
# they returned from a fight.
var room_layout: Array[Dictionary] = []

var blob_defeated: Dictionary = {}

var forge_used: Dictionary = {}
# forge_id -> bool (2026-09-02, forge pass) - mirrors chest_opened's own
# shape exactly, same reasoning: survives a same-room reload (a battle
# round trip rebuilds field_forge.gd fresh from room_layout, same as it
# does field_chest.gd) so a forge already spent this visit doesn't offer
# itself again. Only one forge ever exists per room today (see field_
# forge.gd's own forge_id doc), but the id-keyed shape costs nothing and
# needs no rework if that ever changes.

var chest_opened: Dictionary = {}
# chest_id -> bool (2026-08-29, three-chest treasure room) - REPLACES a
# single shared bool. That was fine when at most one chest could ever
# exist in a room (true of every room type until now - see this pass's
# own report: COMBAT stopped spawning chests entirely in the 2026-08-29
# single-screen pass, so TREASURE's new three-chest layout is actually
# the ONLY thing that has ever needed this to distinguish more than one
# chest at a time), but a single flag can't tell three siblings apart -
# same "blob_defeated already solved this" reasoning structure_resolved
# below already follows. Keyed by field_chest.gd's own chest_id, read/
# written there (see its _ready()/_on_body_entered()) the exact same way
# blob_id/blob_defeated already are.
#
# Deliberately does NOT also record which chests were FORECLOSED (see
# field_chest.gd's own close_permanently()) - foreclosure is live, in-
# memory, this-visit-only coordination between sibling chests (field_
# room.gd's _on_any_chest_claimed()), not something that needs to
# survive a reload: nothing in this game reloads a TREASURE room mid-
# visit (it has no blobs, so it never round-trips through battle.tscn
# and back the way blob_defeated/chest_opened's own reload-survival role
# actually gets exercised for COMBAT). If TREASURE ever gains a reason to
# reload mid-visit, this would need a second per-chest key for "was I
# foreclosed by a sibling," not just "was I the one opened" - flagged
# here rather than built speculatively.

var structure_resolved: Dictionary = {}
# structure_id -> bool, same shape/spirit as blob_defeated above - which
# enterable structures (see field_structure.gd/field_interior.gd and
# DESIGN.md's Sunken Works: The Pay House) in THIS room have already been
# resolved. Read by a structure's own interior content script (pay_
# window.gd, for the Pay House) to decide whether it's still live or
# should render its inert "already resolved" look - never read by the
# EXTERIOR trigger (field_structure.gd), which stays enterable
# indefinitely regardless of this value (resolution is something the
# INTERIOR shows, not something that gates walking back in). Survives a
# same-room round trip exactly like blob_defeated/chest_opened do (the
# structure -> reward_screen -> field_room round trip never calls load_
# room()/reset_room()), and is cleared here alongside them.

var shop_stock: Array[CardData] = []
# The current SHOP room's card offering - rolled ONCE by _generate_shop_
# layout() when the room itself is generated, same "generated once, just
# read afterward" relationship room_layout has with field_room.gd. shop_
# window.gd removes an entry the instant it's bought (never rerolls this
# list) - that's what makes leaving the shop window and re-entering the
# marker show exactly what's left rather than a fresh offering. Cleared in
# reset_room() like everything else here, so the NEXT room generated
# never inherits stale stock.

# Where the player was standing when they walked into a blob, so
# field_room.gd can put them back there instead of at the entrance -
# "the player stands where the encounter happened."
var player_position: Vector2 = Vector2.ZERO
var has_saved_position: bool = false

# A point clear of the structure's own trigger box, on the far (right)
# side - set by field_structure.gd's _on_body_entered() at the same
# moment it saves player_position above, so it's ready if the interior's
# own back door (see field_interior.gd's optional back_exit_door) ever
# needs it. Lets a structure that sits in the middle of a room (like the
# Pay House, now scaled to 2x the player's height - see DESIGN.md) be
# WALKED THROUGH via its own interior instead of forcing the player back
# out the front and around it, which would just re-trigger the door
# again (see field_structure.gd's own note on why that door can never
# just be walked past safely from the outside). Not read at all by a
# structure whose interior has no back door - never cleared in reset_
# room() for the same reason player_position isn't: always overwritten
# fresh before it could ever be read stale.
var structure_bypass_position: Vector2 = Vector2.ZERO

# True for the stretch between "the player touched a blob" and "we're
# back in the field room after that fight's loot is settled." field_blob.gd
# sets this right before starting the battle; reward_screen.gd reads it
# to send Victory back to the field room instead of the dev battle-chain
# path (see its _continue_to_next_battle()); each blob's own _ready()
# consumes last_encountered_blob_id to know if IT was the one just
# fought.
var in_field_encounter: bool = false
var last_encountered_blob_id: String = ""

var pending_enemy_data: EnemyData = null
# Which enemy the blob the player just touched represents - set by
# field_blob.gd right before transitioning to battle.tscn (see its
# _on_body_entered()), read by battle.gd's _spawn_enemy() so the fight is
# against the SAME enemy the field silhouette already showed, not a
# fresh random pick (see EnemyPool.pick_random(), which is what decided
# it in the first place - see _generate_combat_layout()/
# _generate_boss_layout() below). Left null, battle.gd falls back to a
# fresh random pick itself - the title screen's "Dev: Battle Chain"
# shortcut skips the field entirely, so there's never a pending pick to
# read in that case.
#
# Mutually exclusive with pending_encounter_enemies below - a touched
# blob sets exactly one of the two and clears the other, so nothing
# leaks stale across two blobs of different kinds touched in the same
# room visit (reset_room() only runs between ROOMS, not between blobs).

var pending_encounter_enemies: Array[EnemyData] = []
# The AUTHORED group (see encounter_data.gd/EncounterPool and DESIGN.md's
# Bestiary: Authored encounters) the blob the player just touched
# represents, when it's one of the rare multi-enemy encounters rather
# than a normal single-enemy blob (see _generate_combat_layout()'s
# encounter_chance roll) - read by battle.gd's _resolve_enemies_data(),
# checked BEFORE the single-enemy fallback above. Empty (not null, same
# typed-array-safe default as everywhere else this pattern's used) means
# "no pending encounter, use pending_enemy_data instead."

var pending_chest_gold: int = -1
# DEAD for the field-chest path as of the in-field reward pass (2026-08-27)
# - field_chest.gd grants gold directly now (RunState.add_gold(), see its
# own _on_body_entered()) instead of routing it through reward_screen.tscn,
# so nothing writes this any more. Left declared, unused, rather than
# deleted: reward_screen.gd (still untouched - combat victory and the Pay
# House keep their original full-scene behavior) still reads this at
# _ready() to decide whether to build a chest-style gold-only loot list;
# deleting the field out from under that read would break a caller this
# pass was explicitly told not to touch. Always -1 now in practice - the
# `if RoomState.pending_chest_gold >= 0:` branch in reward_screen.gd is
# permanently unreachable dead code as a direct result, not a bug.

var pending_weapon_grant: WeaponData = null
# Same shape as pending_chest_gold above, for a weapon instead of gold -
# set by whatever wants to hand the player a SPECIFIC weapon outside the
# normal reward roll: title_screen.gd's dev-only "Grant Weapon" buttons, or
# the Pay House's payment (see pay_window.gd). NOT a TREASURE chest's own
# weapon roll any more (2026-08-27, in-field reward pass) - that now goes
# through field_chest.gd's own weapon_offered signal straight to field_
# room.gd's own WeaponPickupWindow instance, never touching RoomState at
# all (there's no scene boundary left for a chest's weapon to cross). Null
# means "nothing pending," read (and cleared back to null) by reward_
# screen.gd's _ready() the same way pending_chest_gold is.

var pending_non_battle_reward: bool = false
# Set alongside pending_weapon_grant by a reward source that ISN'T a
# battle victory or a chest (today: only pay_window.gd) - reward_
# screen.gd's _continue_to_next_battle() needs to know this so it can
# skip RunState.advance_to_next_battle() the same way it already skips
# it for a chest (see _is_chest_reward's own note there: "a chest never
# fought a battle"), without ALSO needing to look like a chest (a chest
# always carries pending_chest_gold too; the Pay House deliberately
# never sets that, since its reward is weapon-only, no gold row). Read
# once and cleared the same one-shot way every other pending_* field
# here is.

# Called by whatever wants a SPECIFIC type of room - title_screen.gd for
# the run's first room, field_exit.gd for every room after (both reading
# the type straight off a RunState graph node - see run_state.gd). Rolls
# this room's actual contents once, right here, so field_room.gd never
# has to.
func load_room(room_type: RoomType.Kind) -> void:
	current_room_type = room_type
	region_progress = _compute_region_progress()
	reset_room()
	room_layout = _generate_layout(room_type)
	SceneTransition.go_to("res://field_room.tscn")

# The opening room is layer -1 by construction (RunState.opening_node,
# outside run_graph's own numbering - see that field's own doc) - an
# explicit branch here, not letting -1 / (layer_count - 1) fall out of
# the arithmetic on its own, since that would produce a small NEGATIVE
# value rather than 0.0. Same explicit `== RunState.opening_node` shape
# every other opening-room special case in this file already uses (see
# _generate_combat_layout()'s own branch, further down) - this isn't a
# new pattern, just this pass's own use of it.
func _compute_region_progress() -> float:
	if RunState.current_node == RunState.opening_node:
		return 0.0
	return clampf(float(RunState.current_node.layer) / float(RunState.layer_count - 1), 0.0, 1.0)

func _generate_layout(room_type: RoomType.Kind) -> Array[Dictionary]:
	match room_type:
		RoomType.Kind.COMBAT:
			return _generate_combat_layout()
		RoomType.Kind.TREASURE:
			return _generate_treasure_layout()
		RoomType.Kind.EVENT:
			return _generate_event_layout()
		RoomType.Kind.SHOP:
			return _generate_shop_layout()
		RoomType.Kind.ELITE:
			return _generate_elite_layout()
		RoomType.Kind.BOSS:
			return _generate_boss_layout()
		RoomType.Kind.HEAP:
			return _generate_heap_layout()
		RoomType.Kind.FORGE:
			return _generate_forge_layout()
		_:
			return []

# OPENING_ROOM_ENEMY (Tideworn) is back in active use (2026-08-27,
# "Tideworn is always the first enemy" pass - see this pass's own
# report) - NOT for the opening room any more (that room no longer
# fights anyone at all, see _generate_opening_arrival_layout() below),
# but as the forced pick for whichever room turns out to be the first
# REAL combat room a run reaches, wherever it lands in the graph (see
# _generate_combat_layout()'s own RunState.first_combat_generated check).
#
# Tideworn is now ALSO a normal member of the general EnemyPool
# (2026-08-29, "Tideworn as a real encounter" pass - moved out of this
# opening/ subfolder into resources/enemies/ itself, see EnemyPool.list_
# all()'s scan) - this preload keeps working unchanged (a direct resource
# reference, not a pool lookup) and stays the forced pick for the run's
# first fight either way; nothing about that guarantee depended on
# Tideworn being UNREACHABLE any other way, only on this constant always
# resolving to the same real tideworn.tres. A run can perfectly well
# force Tideworn as its first fight AND later roll it again normally -
# not a bug, no different from any other repeatable enemy in the pool.
#
# OPENING_ROOM_INDUSTRIAL_ENEMY (Unrelieved) stays UNUSED - the
# industrial variant was already EXPERIMENTAL/dev-buttons-only (see
# RoomState.opening_room_variant, which never leaves COASTAL in real
# play), and this pass's ask ("make Tideworn always be the first combat
# enemy") named Tideworn specifically, unconditionally, not "whichever
# variant's enemy" - flagged rather than guessed at; ask if Unrelieved
# should get the same treatment for the industrial dev path.
#
# What they were originally for: the coastal and industrial rooms
# (EXPERIMENTAL parallel prototype - see the industrial opening-room
# note) each had their own dedicated single enemy, picked by RoomState.
# opening_room_variant (see its own comment) instead of the normal
# weighted blob-count/authored-encounter roll below. The Tideworn (see
# DESIGN.md's Bestiary): 20 HP, weak 3-damage attacks, an erratic (not
# fixed-loop) intent pattern - see its own erratic_intent_selection and
# battle.gd's _advance_enemy_intent(). The Unrelieved (see DESIGN.md's
# Bestiary): also 20 HP/3-damage attacks - same overall difficulty by
# design, a parallel opening encounter, not a harder or easier one - but
# a perfectly FIXED, repeating intent loop instead: no erratic_intent_
# selection, no escalation_multipliers, just the plain default
# fixed-cycle advance every enemy already has when it opts into neither
# of those. Unrelieved still lives in its own resources/enemies/opening/
# subfolder, kept out of EnemyPool.pick_random()'s scan the same way as
# before (DirAccess.get_files() doesn't recurse into it) - it stays
# EXPERIMENTAL/dev-only, never an ordinary random encounter. Tideworn no
# longer shares that isolation (2026-08-29 - see OPENING_ROOM_ENEMY's own
# doc above): it moved out to resources/enemies/ itself, so it's now a
# real member of the general pool alongside Beachwrack/Outbound.
const OPENING_ROOM_ENEMY := preload("res://resources/enemies/sputter.tres")
const OPENING_ROOM_INDUSTRIAL_ENEMY := preload("res://resources/enemies/opening/unrelieved.tres")

# Authored, not rolled (2026-09-06, "authored first fight" pass) - this is
# the one encounter in the game where the player's own state is fully known
# ahead of time, so OPENING_ROOM_ENEMY's spawn x is a hand-picked value
# instead of going through _place_content_positions() like every other
# combat room's blob. ~37.5% into standard_room_width (2800) - see
# _generate_combat_layout()'s own RunState.first_combat_generated branch
# for where this gets applied.
@export var first_combat_enemy_spawn_x: float = 1050.0

# BOSS_01, Sunken Works' own boss (2026-08-29, BOSS_01 pass - see enemy_
# data.gd's Charge section and _generate_boss_layout() below) - same
# "one preload, referenced by its own layout function" shape OPENING_
# ROOM_ENEMY above uses, but UNLIKE it, genuinely "never rolled
# elsewhere" (OPENING_ROOM_ENEMY lost that property 2026-08-29 - see its
# own doc): this one's isolation comes from EnemyPool.BOSS_ENEMY_FOLDER
# being excluded from list_all()/pick_random() by default (see that
# file's own doc), a separate mechanism nothing about the Tideworn change
# touches - dev_encounter_picker.gd was NOT extended to reach this folder
# in this pass, so today the only way to fight BOSS_01 at all is through
# this exact const, in an actual boss room. No per-biome branch needed -
# SUNKEN_WORKS is the only biome that exists today (see RunState.
# current_biome), so this is simply THE boss until a second biome (and a
# second boss) exists to choose between.
const BOSS_01_ENEMY := preload("res://resources/enemies/bosses/boss_01.tres")

# The opening room's own NPC (see npc_data.gd and this feature's own
# brief: the first NPC in the game, one hand-placed instance, no pool/
# roll of any kind - unlike the enemies above, there's no "never let this
# get rolled elsewhere" concern to design around, since nothing scans for
# NPCs at all yet). Same "one preload, referenced by the opening room's
# own layout function" shape as OPENING_ROOM_ENEMY - not tucked into an
# excluded subfolder the way opening/'s enemies are, since that exclusion
# exists specifically to keep EnemyPool.pick_random() from finding them,
# and nothing here scans resources/npcs/ at all.
const OPENING_ROOM_NPC := preload("res://resources/npcs/opening_room_npc.tres")

# The opening room's own spawn point - moved here from field_room.gd
# (which still reads it, as RoomState.opening_room_player_spawn_x, to
# actually place the player) for the same reason floor_line_y lives here
# rather than in field_room.gd: OPENING_ROOM_ENEMY_X/_CHEST_X below are
# tuned RELATIVE to this exact number, and now so is the shared entrance-
# clearance check (_min_content_x()) - one shared source of truth instead
# of a value field_room.gd owned alone with everyone else trusting it
# stayed in sync by hand. @export, not const, matching floor_line_y/
# standard_room_width's own "eyeballed number, expect to retune" stance.
@export var opening_room_player_spawn_x: float = 850.0
# RETUNED from 700 (2026-08-26, "quiet arrival room" pass - see this
# pass's own report). With the enemy and chest gone (see OPENING_ROOM_
# ENEMY_X/_CHEST_X below, now unused), nothing to the right of spawn
# constrains it any more - entrance_clearance_fraction's own _min_
# content_x() has no forward content left to protect. Free to move
# spawn itself now, which is the only real lever for "give the NPC a
# real walking distance" (see this pass's own investigation: widening
# standard_room_width does NOT help - it only extends the room to the
# RIGHT of spawn, away from her, since OPENING_ROOM_NPC_X sits BEHIND
# spawn on the fixed-origin left side).
#
# NOT the room's own midpoint (that would be ~1550, splitting the
# 450<->2660 NPC-to-exit span evenly) - capped lower by a REAL
# constraint OPENING_ROOM_NPC_X's own comment already worked out: the
# camera centers on the player, viewport width 1920 (project.godot), so
# at spawn the visible range is [spawn - 960, spawn + 960]. That range
# has to still cover her (x=450, collision spanning [415, 485]) with
# real margin, or she'd render entirely off-screen to the left the
# instant the room loads - the opposite of "quiet arrival room." 1200
# keeps the visible range at [240, 2160], a 175px margin past her left
# edge (415) - comfortable, not razor-thin. A true midpoint (1550) would
# put the visible range at [590, 2510], which clips her ENTIRELY out of
# frame at spawn - checked, not assumed; see this pass's own report,
# which flags this trade-off explicitly rather than silently picking
# whichever number happened to look bigger.
#
# Distance to her: 1200 - 450 = 750px = 1.0s at player.gd's 750px/s
# SPEED - a real, clearly-felt walk (3x the old 250px/0.33s gap), while
# still leaving 2660 - 1200 = 1460px (1.95s) forward to the exit, close
# to the room's original ~2.6s entrance-to-exit pace. Eyeballed, expect
# to retune once seen live, same stance as every other feel-tuned number
# in this file.
#
# TRADE-OFF, not fixed here: the OLD 700 was deliberately only 80px past
# the coastal variant's shoreline (field_room.gd's OPENING_ROOM_OCEAN_
# DEPTH inner edge, x=620), tuned so spawning read as "just stepped off
# the boat." At 1200, the player spawns 580px inland instead - that
# framing is weakened, if not fully gone. Flagged, not silently patched
# around; see this pass's own report.

# UNUSED as of the "quiet arrival room" pass (2026-08-26) - the opening
# room no longer places an enemy at all (see _generate_opening_arrival_
# layout() below). Left in place, commented rather than deleted, per
# this pass's own explicit instruction: reverting this change later
# shouldn't require re-deriving the entrance-clearance math below by
# hand a second time.
#
# Hand-placed, not drawn from SPAWN_SLOT_FRACTIONS (the exit sits at
# field_room.gd's standard EXIT_X, currently 2660, both paired with
# floor_line_y like everything else here): the proportional slots would
# land at the wrong relative position for this room's own narrative
# beats, and (for the chest) with no guarantee of actually sitting near a
# wall edge - both things this specific room needs to control
# deliberately rather than roll for. X-only, like SPAWN_SLOT_FRACTIONS -
# see floor_line_y's own comment. Still has to clear the same shared
# entrance-clearance rule every other room's content does (see
# _min_content_x()) - this room's hand-placed positions used to bypass
# that check entirely rather than just being exempt from the RANDOM slot
# system, which is what let OPENING_ROOM_ENEMY_X quietly fall short of it
# once entrance_clearance_fraction was raised to 0.3 (checked directly
# below, not just eyeballed - see _ready()).
# const OPENING_ROOM_ENEMY_X := 1600.0
# Re-tuned (from 1300) to clear the entrance-clearance rule once it
# generalized to 0.3 of the room's walkable width, measured from THIS
# room's own spawn point (opening_room_player_spawn_x) - the old value
# was tuned against a "~30% of the way from spawn to the EXIT" pacing
# instead, a smaller distance than 30% of the full walkable width, so it
# fell just short (1300 < the rule's 1516 minimum at the current
# standard_room_width) rather than merely rounding differently.

# UNUSED as of the "quiet arrival room" pass (2026-08-26) - the opening
# room no longer places a chest at all (see _generate_opening_arrival_
# layout() below). Left in place, commented rather than deleted, for the
# same revert-friendliness reason as OPENING_ROOM_ENEMY_X above.
#
# The chest's own placement (opening room ONLY, no other room's chest
# placement changes): a single fixed spot on the room's floor line,
# between the Tideworn/Unrelieved (at OPENING_ROOM_ENEMY_X) and the
# exit - reads as "found along the way, not tucked against the ocean"
# without needing a top/bottom wall to sit near, now that the room is a
# strict single-line layout (see DESIGN.md's Run Structure & Navigation:
# field movement redesign). Previously randomized between three wall-
# adjacent spots (top/bottom/right); top and bottom are no longer
# reachable positions at all now that vertical movement is gone, so that
# variation collapsed to this one spot rather than three. Already clears
# the entrance-clearance rule with room to spare (2000, well past the
# rule's 1516 minimum) - unlike OPENING_ROOM_ENEMY_X, this one didn't
# need retuning.
# const OPENING_ROOM_CHEST_X := 2000.0

# Her spot - BEHIND opening_room_player_spawn_x, not ahead of it like
# OPENING_ROOM_ENEMY_X/_CHEST_X above, on purpose (see this feature's own
# brief): reaching her means deliberately walking AWAY from the exit,
# never a detour on the way to it, so she can never sit between spawn
# and the exit and can never be brushed by a player just walking
# forward. That also means she's exempt from entrance_clearance_
# fraction's own _min_content_x() check (see _ready()'s asserts below,
# which don't cover this constant) - that rule only ever protected
# FORWARD content from crowding the spawn point, which was never a risk
# here in the first place.
#
# 450 puts her well clear of the left wall (ROOM_FLOOR_LEFT_X, field_
# room.gd's own 40.0) while still reading as "just behind you" rather
# than "all the way at the back." Originally ALSO comfortably inside the
# camera's initial framing at spawn (opening_room_player_spawn_x was 700
# when this was tuned - FieldCamera clamps to limit_left = 0, so a
# 1920-wide viewport centered there shows roughly [0, 1920], covering
# her with room to spare). That's no longer automatic now that spawn
# moved to 1200 (2026-08-26, "quiet arrival room" pass) - see spawn's
# own comment, which re-derives the camera-visibility bound this const
# now has to stay under instead of just clearing it by accident. A
# FEEL-TUNABLE number either way, same "eyeballed, expect to retune once
# seen live" stance as OPENING_ROOM_ENEMY_X's own history - not derived
# from any formula, just picked to be checked live and moved if it reads
# wrong.
const OPENING_ROOM_NPC_X := 450.0

# Filters the weight dictionary down to only counts <= max_encounters_
# per_room BEFORE handing it to WeightedRandom.pick() - excluded, not
# clamped after the fact, so a count above the cap never has a chance to
# be rolled at all (clamping post-roll would silently fold whatever
# three_blob_weight's odds were into "2," distorting the ratio between
# one_blob_weight and two_blob_weight in the process).
func _pick_blob_count() -> int:
	var weights: Dictionary = {
		1: one_blob_weight,
		2: two_blob_weight,
		3: three_blob_weight,
	}
	var allowed: Dictionary = {}
	for count in weights:
		if count <= max_encounters_per_room:
			allowed[count] = weights[count]
	return WeightedRandom.pick(allowed)

func _generate_combat_layout() -> Array[Dictionary]:
	if RunState.current_node == RunState.opening_node:
		return _generate_opening_arrival_layout()
	# ONE blob, always (2026-08-29, placement-zone + blob-count pass) -
	# DECIDED, a design choice, not a workaround for the separation
	# fallback (that got fixed properly this same pass - see _room_
	# width()'s own doc above). _pick_blob_count() (and the one_blob_
	# weight/two_blob_weight/three_blob_weight/max_encounters_per_room
	# exports it reads) is now fully unreferenced anywhere in the project -
	# left in place rather than deleted, flagged here instead, same
	# treatment CHEST_CHANCE/COMBAT_CHEST_* got when the chest roll was
	# removed. ELITE has its own completely separate path (_generate_
	# elite_layout()) that never called this function or _pick_blob_
	# count() to begin with - unaffected by this change either way.
	var blob_count: int = 1

	# Roll WHAT each blob is (unchanged selection logic/odds) - positions
	# for everything in this room are decided together, AFTER this loop,
	# by _place_content_positions() - see its own doc for why widths no
	# longer factor into placement at all (2026-08-27, blob-overlap fix).
	var picks: Array[Dictionary] = []
	var first_combat_fixed_x := -1.0
	# Set only in the i == 0/first_combat_generated branch below - applied
	# to positions[0] after placement runs, overriding whatever it rolled
	# (see first_combat_enemy_spawn_x's own doc).
	for i in blob_count:
		var pick: Dictionary = {}
		var encounter: EncounterData = null
		# The run's first real fight, wherever it lands (2026-08-27,
		# "Tideworn is always the first enemy" pass - see this pass's own
		# report): NOT the same thing as _past_first_layer()/layer == 0
		# below, which only protects the graph's literal first LAYER - a
		# layer can roll TREASURE/EVENT/SHOP, so the first COMBAT room a
		# real playthrough reaches can land on any layer. RunState.first_
		# combat_generated is the flag that actually tracks "has any
		# combat room's content been rolled yet this run" - see its own
		# doc. Claimed immediately (before the encounter/EnemyPool roll
		# below even runs) so only this ONE pick, in this ONE room, is
		# ever forced - a second blob in this same room (if blob_count
		# rolled 2 or 3) and every combat room after it roll completely
		# normally, encounter chance and all.
		if i == 0 and not RunState.first_combat_generated:
			RunState.first_combat_generated = true
			pick["enemy"] = OPENING_ROOM_ENEMY
			pick["wander"] = true
			picks.append(pick)
			first_combat_fixed_x = first_combat_enemy_spawn_x
			continue
		if _past_first_layer() and randf() < encounter_chance:
			encounter = EncounterPool.pick_random()
		if encounter != null:
			pick["encounter"] = encounter
		else:
			var enemy: EnemyData = EnemyPool.pick_random(false, RunState.current_node.layer) # Elites are ELITE-room-exclusive now - see DESIGN.md's ELITE Rooms section. current_layer gates layer-restricted enemies (today: Outbound - see EnemyData.min_layer's own note).
			pick["enemy"] = enemy
		picks.append(pick)

	# No chest in a COMBAT room any more (2026-08-29, single-screen pass -
	# DECIDED: removed from generation entirely, not just left unrolled).
	# total_count is just blob_count now. CHEST_CHANCE/COMBAT_CHEST_GOLD_
	# MIN/COMBAT_CHEST_GOLD_MAX/COMBAT_CHEST_WEAPON_CHANCE (below) are now
	# fully unreferenced - this was their only reader - left in place
	# rather than deleted, flagged in this pass's own report instead, same
	# treatment _pick_blob_count() got the last time something here went
	# unreferenced. TREASURE's own chests (treasure_chest_gold_min/max,
	# a completely separate set of exports) and field_chest.gd itself are
	# both untouched by this pass - see _generate_treasure_layout() for
	# TREASURE's own three-chest layout, added later (2026-08-29).
	var total_count := blob_count

	# Escaping-enemy placement (2026-08-27 - see escaping_enemy_exit_gap_
	# px's own doc). Identified by the mechanic flag (EnemyData.escape_
	# distance_max > 0.0), never a hardcoded name - encounter picks are
	# never checked here (an authored EncounterData is placed/treated as
	# ONE blob regardless of what it contains, and no authored encounter
	# includes an escaping enemy today). At most one match is expected in
	# practice; if a future room somehow rolled two, the first one found
	# claims the reserved zone and the second is placed as ordinary
	# "everyone else" content - not a crash, just an unspecified ordering
	# between two enemies that both want to be "last," same spirit as
	# battle.gd's own "_escaping_enemy is whichever was found last" note.
	var escaping_index := -1
	for i in picks.size():
		if picks[i].has("enemy") and picks[i]["enemy"].escape_distance_max > 0.0:
			escaping_index = i
			break

	var positions: Array[float]
	if escaping_index == -1:
		positions = _place_content_positions(total_count)
	else:
		positions = []
		positions.resize(total_count)
		var min_x := _min_content_x(_standard_spawn_x())
		var max_x := _max_content_x(_exit_x())
		var reserved_right: float = minf(max_x, max_x - escaping_enemy_exit_gap_px)
		var reserved_left: float = maxf(min_x, reserved_right - escaping_enemy_zone_width_px)
		positions[escaping_index] = randf_range(reserved_left, reserved_right)
		var remaining_count := total_count - 1
		if remaining_count > 0:
			# Bounded to the LEFT of the escaping enemy's own position, not
			# the room's full zone - this is what guarantees "always last"
			# by construction, rather than relying on separation alone to
			# usually work out that way.
			var others_max_x: float = maxf(min_x, positions[escaping_index] - min_separation_px)
			var other_positions := _place_content_positions(remaining_count, min_x, others_max_x)
			var other_iter := 0
			for i in total_count:
				if i != escaping_index:
					positions[i] = other_positions[other_iter]
					other_iter += 1

	if first_combat_fixed_x >= 0.0:
		positions[0] = first_combat_fixed_x

	var layout: Array[Dictionary] = []
	for i in blob_count:
		var entry: Dictionary = {
			"kind": "blob",
			"id": "blob_%d" % i,
			"position": Vector2(positions[i], floor_line_y),
		}
		entry.merge(picks[i])
		layout.append(entry)

	return layout

# RENAMED from _generate_opening_combat_layout() (2026-08-26, "quiet
# arrival room" pass - see this pass's own report). The opening room no
# longer fights anyone or holds a chest - just the player, the NPC, and
# the exit, per this pass's own brief: the first fight moves to whichever
# room turns out to be the first real COMBAT node the run graph produces
# (NOT necessarily run_graph layer 0 - a layer can roll TREASURE/EVENT/
# SHOP instead; see _generate_combat_layout()'s own RunState.first_
# combat_generated check, added 2026-08-27, for the room that actually
# guarantees Tideworn there regardless of which layer it lands on). No
# blob-count roll, no encounter_chance roll, no chest roll here - this
# room's ENTIRE layout is just the one hand-placed NPC entry below.
#
# opening_node.room_type stays RoomType.Kind.COMBAT (run_state.gd's own
# _validate_run_graph() asserts this, unrelated to this pass, left
# alone) - that's fine even with zero blobs: field_room.gd's _update_
# exit_lock() only locks a COMBAT/ELITE room's exit while some entry in
# RoomState.room_layout has "kind"=="blob" and isn't yet in blob_
# defeated; with no blob entries at all, that loop never finds one to
# object to, so the door unlocks immediately, same as a real combat room
# the instant its last enemy falls - verified headlessly, see this
# pass's own report.
func _generate_opening_arrival_layout() -> Array[Dictionary]:
	return [
		{
			"kind": "npc",
			"position": Vector2(OPENING_ROOM_NPC_X, floor_line_y),
			"npc_data": OPENING_ROOM_NPC,
		},
	]

@export var treasure_chest_a_x_offset_px: float = 810.0
# Chest A's (gold) own x position, as an offset from the room's STANDARD
# spawn point (_standard_spawn_x()) - same "offset from a known
# reference point" shape opening_room_player_spawn_x/OPENING_ROOM_NPC_X
# already use, rather than an absolute room-space x, so retuning
# entrance_clearance_fraction or standard_room_width doesn't silently
# walk this chest into the entrance-clearance zone. Chest B and C are
# then placed relative to THIS one via the two gap exports below, not
# each independently offset from spawn - a deliberate, fixed left-to-
# right LAYOUT (gold, card, weapon - this room's own brief), not the
# rejection-sampled random placement every other room type's content
# uses (_place_content_positions()) - three chests always reading in the
# same order is the point, not an incidental default.
#
# RETUNED 820 -> 810 (2026-08-31, treasure-overhang pass) - TREASURE
# joined COMBAT as a single-screen room type (see field_room.gd's own
# _is_single_screen_room()), shrinking its width from standard_room_width
# (2800) to combat_room_width() (viewport_width(), 1920 at zoom 1.0) - the
# three chests now need to cluster and fit within that one static frame
# instead of a room a camera used to scroll across. Chosen so chest B
# (the cluster's own center, now that gap_ab/gap_bc are equal - see
# treasure_gap_bc_px's own doc) lands at spawn_x + 810 + 240 = 1190,
# matching room_width() * treasure_overhang_center_ratio (1920 * 0.62 =
# 1190.4, field_room.gd's own export) almost exactly - the overhang built
# from that same ratio centers directly over this cluster rather than the
# two drifting apart as independent numbers. Both sides of that math are
# fixed/spawn_x-relative except room_width() itself, which now moves with
# RoomState.field_zoom (2026-09-06, field-pull-back pass) - at any zoom
# other than 1.0 the overhang's center_x and this cluster's fixed x will
# drift apart again. Left unaddressed on purpose for this pass (same
# "note but don't fix, see it first" stance as field_room.gd:3056's own
# NPC-offer-card note).
@export var treasure_gap_ab_px: float = 240.0
@export var treasure_gap_bc_px: float = 240.0
# RETUNED 600 -> 240 (2026-08-31, treasure-overhang pass) - equal to gap_
# ab now, UNLIKE this pair's own prior "deliberately uneven" brief (gold-
# to-card close, card-to-weapon a longer walk, when TREASURE was a wide
# room with real walking distance between beats). A static single-screen
# frame has no room left for that pacing - three chests need to read as
# ONE cluster the player takes in at a glance, not a short pair followed
# by a separate long walk to a third. Equal gaps also make chest B (the
# middle chest) exactly the cluster's own geometric center, which
# treasure_chest_a_x_offset_px's own doc above uses to line up with the
# overhang's center_ratio - an uneven split would leave no single point
# to call "the cluster's center" for that alignment to target.
#
# Resulting positions at these defaults: chest A at spawn_x + 810 = 950,
# chest B at 1190, chest C at 1430 - all comfortably inside the 1920-wide
# single-screen frame (490px clear to the right wall), with chest B
# sitting right of the frame's own screen-center (960) as asked, and
# chest A still past the room's own entrance-clearance reference point
# (692 at this width - see entrance_clearance_fraction's own doc; this
# layout only roughly matches that zone, per treasure_chest_a_x_offset_
# px's own doc above, since it doesn't route through _place_content_
# positions() to have it enforced).

@export_multiline var treasure_chest_a_prompt: String = "You hear coins inside."
@export_multiline var treasure_chest_b_prompt: String = "Paper, kept dry."
@export_multiline var treasure_chest_c_prompt: String = "Someone left this closed on purpose."
# The three approach-prompt flavor lines (2026-08-29, prompt-first
# interaction pass) - exported here, not hardcoded in _generate_treasure_
# layout() below, so they can be revised without a code change, per this
# pass's own brief. Threaded into each chest's own field_chest.gd prompt_
# text at spawn time, same "set per-instance at spawn" shape min_gold/
# max_gold already use for Chest A.

@export var treasure_chest_a_texture: Texture2D = preload("res://assets/regions/beach/Belongings/belonging_pack.png")
@export var treasure_chest_b_texture: Texture2D = preload("res://assets/regions/beach/Belongings/belonging_case.png")
@export var treasure_chest_c_texture: Texture2D = preload("res://assets/regions/beach/Belongings/belonging_roll.png")
# The three chests' own painted belongings art (2026-09-01, belongings-
# sprite pass) - same "one export per chest, threaded through the layout
# dict at spawn" shape treasure_chest_a/b/c_prompt above already use, not
# a shared/pooled asset, since each chest is a specific object (coins,
# paper, a locked case) that needs its own texture. Null leaves that chest
# on FieldChest's own polygon fallback - see field_chest.gd's belonging_
# texture doc. Real assets wired in directly (2026-09-01, real-asset pass) -
# same convention every other RoomState default here already uses (a plain
# script default, no separate .tscn override layer - see room_state.tscn's
# own near-empty property list). RE-PAIRED (2026-09-01, belongings-tuning
# pass) - pack moved a<-b, case moved b<-a; roll stays put on c. Texture
# assignment only - chest_a/b/c's own prompt strings/reward_kind/x-position
# above are untouched, since this dict's "belonging_texture" key is
# independent of all of those.

@export var treasure_chest_a_scale_multiplier: float = 1.0
@export var treasure_chest_b_scale_multiplier: float = 1.6
@export var treasure_chest_c_scale_multiplier: float = 1.0
# Per-chest multiplier on top of FieldChest.belonging_scale's own shared
# factor (2026-09-01, belongings-tuning pass) - same per-instance-export/
# threaded-through-the-layout-dict shape belonging_texture above already
# uses. b's 1.6 deliberately breaks the "one shared scale factor" property
# belonging_scale is otherwise supposed to hold: the case (currently on b -
# see treasure_chest_b_texture above) renders too small to read relative
# to the other two, and that's the CASE ASSET's own authored proportion
# being wrong, not a placement/anchoring bug - a per-instance correction
# belongs here, not in a second shared scale constant that would then be
# wrong for the other two. Retune/reassign this alongside whichever
# texture slot the case ends up on if the a/b/c pairing changes again.

@export var treasure_chest_a_offset: Vector2 = Vector2.ZERO
@export var treasure_chest_b_offset: Vector2 = Vector2.ZERO
@export var treasure_chest_c_offset: Vector2 = Vector2.ZERO
# Manual per-chest x/y nudge for the belonging sprite, on top of its own
# automatic centering/bottom-anchoring (2026-09-01, belongings-tuning
# pass) - same per-instance-export/threaded-through-the-layout-dict shape
# belonging_scale_multiplier above already uses. See FieldChest.belonging_
# offset's own doc for what x/y actually move.

func _generate_treasure_layout() -> Array[Dictionary]:
	var chest_a_x: float = _standard_spawn_x() + treasure_chest_a_x_offset_px
	var chest_b_x: float = chest_a_x + treasure_gap_ab_px
	var chest_c_x: float = chest_b_x + treasure_gap_bc_px
	return [
		{
			"kind": "chest",
			"chest_id": "chest_gold",
			"reward_kind": FieldChest.RewardKind.GOLD,
			"position": Vector2(chest_a_x, floor_line_y),
			"min_gold": treasure_chest_gold_min,
			"max_gold": treasure_chest_gold_max,
			"prompt_text": treasure_chest_a_prompt,
			"belonging_texture": treasure_chest_a_texture,
			"belonging_scale_multiplier": treasure_chest_a_scale_multiplier,
			"belonging_offset": treasure_chest_a_offset,
		},
		{
			"kind": "chest",
			"chest_id": "chest_card",
			"reward_kind": FieldChest.RewardKind.CARD,
			"position": Vector2(chest_b_x, floor_line_y),
			"prompt_text": treasure_chest_b_prompt,
			"belonging_texture": treasure_chest_b_texture,
			"belonging_scale_multiplier": treasure_chest_b_scale_multiplier,
			"belonging_offset": treasure_chest_b_offset,
		},
		{
			"kind": "chest",
			"chest_id": "chest_weapon",
			"reward_kind": FieldChest.RewardKind.WEAPON,
			"position": Vector2(chest_c_x, floor_line_y),
			"prompt_text": treasure_chest_c_prompt,
			"belonging_texture": treasure_chest_c_texture,
			"belonging_scale_multiplier": treasure_chest_c_scale_multiplier,
			"belonging_offset": treasure_chest_c_offset,
		},
	]

# A single wreckage pile, same one-piece-of-content shape as _generate_
# treasure_layout()'s chest above (2026-08-28, wreckage-heap room v1) -
# min_gold/max_gold/weapon_chance have no equivalent here since the heap's
# own tunables (sifting_start_cost/sifting_cost_step, which outcome table
# to draw from) live on field_heap.gd itself, the same way a chest's own
# color/geometry exports live on field_chest.gd rather than being rolled
# per-room.
func _generate_heap_layout() -> Array[Dictionary]:
	var position: float = _place_content_positions(1)[0]
	return [{"kind": "heap", "position": Vector2(position, floor_line_y)}]

# A single forge, same one-piece-of-content shape as _generate_heap_
# layout() above (2026-09-02, forge pass, commit 3 of 3 - REPLACES the
# empty-layout stub commit 2 shipped). "forge" is a constant id, not
# generated per-room - only one forge ever exists per room today (see
# field_forge.gd's own forge_id doc), so there's no risk of two entries
# colliding on the same RoomState.forge_used key.
func _generate_forge_layout() -> Array[Dictionary]:
	var position: float = _place_content_positions(1)[0]
	return [{"kind": "forge", "forge_id": "forge", "position": Vector2(position, floor_line_y)}]

func _generate_marker_layout() -> Array[Dictionary]:
	var position: float = _place_content_positions(1)[0]
	return [{"kind": "marker", "position": Vector2(position, floor_line_y)}]

@export var event_content_weights: Dictionary = {"pay_house": 70.0, "curio": 30.0}
# Which SPECIFIC content an EVENT room gets, rolled fresh every time one
# loads (2026-08-28, second-event pass) - REPLACES "every EVENT room
# spawns the Pay House unconditionally" (a known, explicitly flagged
# limitation - see this pass's own report - not an oversight). Same
# filter-then-pick shape run_state.gd's own room_type_max_instances
# already uses for ROOM TYPES, just one level down: a weights dict here,
# a matching event_content_max_instances cap below, and RunState.event_
# content_generated tracking counts across the WHOLE RUN (not just this
# room) - same cross-file split RunState.first_combat_generated already
# establishes (a RunState-owned "has this happened yet" flag, read/
# written from HERE, in RoomState, not from run_state.gd itself, since
# room CONTENT stays decided lazily at load time - see this pass's own
# report on why that's the better fit than pre-deciding it at graph
# generation).
#
# Untuned placeholder weights (70/30) - both event contents here are
# explicitly placeholder-quality (field_curio.gd's own header says so
# directly), so there's nothing real yet to balance these against.

@export var event_content_max_instances: Dictionary = {"pay_house": 1}
# Mirrors RunState.room_type_max_instances exactly (Kind -> max there,
# content-id -> max here) - any id absent is uncapped, same "not a
# special case" stance that dict's own doc establishes. pay_house: 1 is
# this pass's own actual ask ("it should appear at most once per run") -
# curio has no cap, so it's what every OTHER EVENT room gets once pay_
# house's own single slot is spent.

# EVENT rooms used to fall through to _generate_marker_layout() (the
# "an event would happen here" placeholder marker - see field_marker.gd's
# EVENT branch), then spawned the Pay House unconditionally - now picks
# from event_content_weights above, filtered by event_content_max_
# instances the same "exclude before picking, don't clamp after" way
# _assign_room_types()'s own leftover-fill loop already filters room_
# type_max_instances (a capped-out option loses its share of the odds
# entirely, rather than folding into whatever's still open). allowed can
# never end up empty here in practice - curio has no cap entry, so it's
# always eligible, the same "always at least one uncapped fallback"
# invariant room_type_max_instances's own COMBAT/TREASURE/HEAP already
# rely on.
func _generate_event_layout() -> Array[Dictionary]:
	var allowed: Dictionary = {}
	for content_id in event_content_weights:
		var cap: int = event_content_max_instances.get(content_id, -1)
		var generated: int = RunState.event_content_generated.get(content_id, 0)
		if cap < 0 or generated < cap:
			allowed[content_id] = event_content_weights[content_id]
	var chosen_id: String = WeightedRandom.pick(allowed)
	RunState.event_content_generated[chosen_id] = RunState.event_content_generated.get(chosen_id, 0) + 1
	match chosen_id:
		"pay_house":
			# Fixed at the room's horizontal center, NOT placed via
			# _place_content_positions() the way curio below is (2026-
			# 08-27, blob-overlap fix - this call predates and is
			# deliberately exempt from that unification, unchanged by
			# this pass) - the Pay House exterior renders at 2x the
			# player's height (~550px wide, see DESIGN.md's own note on
			# that scale pass), and the room's exit door always sits at
			# a fixed spot near the right wall (field_room.gd's EXIT_X).
			# A random position could land the structure right on top of
			# that door - center placement clears both the entrance and
			# the exit by a wide, safe margin regardless of which edge
			# the player enters from. "interior_scene_path" is
			# deliberately NOT part of this entry: field_pay_house.tscn's
			# own FieldStructure export already carries that (see field_
			# structure.gd's interior_scene) - repeating it here would
			# just be a second place it could drift out of sync.
			return [{
				"kind": "structure",
				"structure_id": "pay_house",
				"position": Vector2(room_width() / 2.0, floor_line_y),
			}]
		"curio":
			var position: float = _place_content_positions(1)[0]
			return [{"kind": "curio", "position": Vector2(position, floor_line_y)}]
		_:
			return [] # Unreachable in practice - see allowed's own doc above for why.

# A shop room is a single marker, the same layout shape as an EVENT room -
# what's different is the fixed card offering rolled once here (see
# shop_stock above) rather than left for shop_window.gd to generate when
# it opens, which is what lets a purchase actually deplete the stock
# instead of it getting rerolled away the next time the window opens.
func _generate_shop_layout() -> Array[Dictionary]:
	shop_stock = _roll_shop_stock()
	return _generate_marker_layout()

func _roll_shop_stock() -> Array[CardData]:
	var pool: Array[CardData] = CardPool.load_class_pool().filter(func(c): return c.rarity <= CardData.Rarity.RARE)
	var stock: Array[CardData] = []
	var stock_count := randi_range(shop_stock_min, shop_stock_max)
	for i in stock_count:
		if pool.is_empty():
			break
		var chosen := _pick_shop_card_by_rarity(pool)
		pool.erase(chosen)
		stock.append(chosen)
	return stock

# Rolls a rarity, then picks a random card matching it from `pool` -
# same "fall back a tier at a time until something in the pool actually
# has one" idiom as reward_screen.gd's _pick_card_by_rarity(), kept as
# its own copy (rather than calling into reward_screen.gd, a per-scene
# Node2D script RoomState has no instance of) so the shop's own weights
# stay independently tunable.
func _pick_shop_card_by_rarity(pool: Array[CardData]) -> CardData:
	var rarity: CardData.Rarity = WeightedRandom.pick({
		CardData.Rarity.COMMON: shop_common_weight,
		CardData.Rarity.RARE: shop_rare_weight,
	})
	while rarity >= CardData.Rarity.COMMON:
		var matches := pool.filter(func(card): return card.rarity == rarity)
		if not matches.is_empty():
			return matches.pick_random()
		rarity -= 1
	return pool.pick_random()

# One blob, same as any other field encounter - the only thing that makes
# it a boss fight is battle.gd checking RoomState.current_room_type ==
# BOSS when it spawns the enemy. ALWAYS BOSS_01_ENEMY now (2026-08-29,
# BOSS_01 pass - REPLACES the old EnemyPool.pick_random() + scale-up
# placeholder, see that const's own doc for why no per-biome branch is
# needed yet). This function's OWN job was never "decide a BOSS-kind
# room sits here" - that's run_state.gd's _assign_room_types() (graph
# topology, untouched by this pass) - only "what fight populates a room
# already known to be one," which is exactly what changed here.
func _generate_boss_layout() -> Array[Dictionary]:
	# Pinned to a reserved zone near the exit (see boss_exit_gap_px/boss_
	# zone_width_px's own doc) rather than the full room-wide roll every
	# other content type uses, so the player always has real distance to
	# close before reaching the boss, not however close a random roll
	# happened to land this run.
	var zone_max := _max_content_x(_exit_x()) - boss_exit_gap_px
	var zone_min := zone_max - boss_zone_width_px
	var position: float = _place_content_positions(1, zone_min, zone_max)[0]
	return [{
		"kind": "blob",
		"id": "boss_blob",
		"position": Vector2(position, floor_line_y),
		"enemy": BOSS_01_ENEMY,
	}]

# One blob, always drawn from the dedicated elite encounter pool - never
# EnemyPool directly, even for a solo elite (see wardling_solo.tres and
# DESIGN.md's ELITE Rooms section) - so an ELITE room's fight is always a
# deliberate, authored pick, the same "authored, not randomly assembled"
# standard Bestiary's Authored encounters note already holds ordinary
# multi-enemy fights to.
func _generate_elite_layout() -> Array[Dictionary]:
	var encounter: EncounterData = EncounterPool.pick_random(EncounterPool.ELITE_ENCOUNTER_FOLDER)
	var position: float = _place_content_positions(1)[0]
	return [{
		"kind": "blob",
		"id": "elite_blob",
		"position": Vector2(position, floor_line_y),
		"encounter": encounter,
	}]

# A layer-0 combat room shouldn't get anything extra-spicy (the rare
# general encounter_chance roll - see _generate_combat_layout()) - layer
# 0 is NOT excluded from the normal COMBAT/TREASURE/EVENT/SHOP room-type
# roll (see run_state.gd's _assign_room_types(), which only excludes the
# last/boss layer and now also excludes ELITE from the first
# elite_excluded_post_opening_layers layers), so without this a
# deliberately harder authored encounter could ambush a layer-0 fight.
# Every layer after that rolls normally.
#
# NOT the same guarantee as "the player's actual first fight ever" -
# layer 0 can roll TREASURE/EVENT/SHOP instead of COMBAT, so the run's
# real first fight can land on any layer, past this check's reach. See
# RunState.first_combat_generated (checked in _generate_combat_layout(),
# 2026-08-27) for the mechanism that actually tracks that, unconditionally
# forcing Tideworn there regardless of which layer it turns out to be.
func _past_first_layer() -> bool:
	return RunState.current_node.layer > 0

# UNUSED as of the "quiet arrival room" pass (2026-08-26) - both asserts
# below guarded OPENING_ROOM_ENEMY_X/_CHEST_X, which the opening room no
# longer places (see _generate_opening_arrival_layout()). Commented
# alongside those two consts rather than deleted, for the same
# revert-friendliness reason - if they come back, this is the exact
# check that already caught a real bug once (see its own history below)
# and would need to come back with them.
#
# Dev aid, same "announce a violation loudly at boot instead of letting
# it surface later as a misplaced object" philosophy as run_state.gd's
# own _validate_run_graph() - the opening room's OPENING_ROOM_ENEMY_X/
# _CHEST_X are hand-placed, not generated through _available_spawn_
# slots()'s own filter, so nothing would otherwise catch a future retune
# of either constant (or of entrance_clearance_fraction/exit_clearance_
# fraction/standard_room_width/opening_room_player_spawn_x) drifting one
# of them back inside the entrance- or exit-clearance zone - exactly the
# bug OPENING_ROOM_ENEMY_X actually had until entrance clearance
# generalized to cover every content type. OPENING_ROOM_ENEMY_X is the
# only one of the two exit clearance actually applies to (see exit_
# clearance_fraction's own note: enemies only, not chests) - OPENING_
# ROOM_CHEST_X keeps its entrance-only check. Runs once at boot, since
# RoomState is an autoload.
func _ready() -> void:
	pass
	# var min_x := _min_content_x(opening_room_player_spawn_x)
	# var max_x := _max_content_x(_exit_x())
	# assert(OPENING_ROOM_ENEMY_X >= min_x, "OPENING_ROOM_ENEMY_X (%s) violates entrance_clearance_fraction (min %s)" % [OPENING_ROOM_ENEMY_X, min_x])
	# assert(OPENING_ROOM_ENEMY_X <= max_x, "OPENING_ROOM_ENEMY_X (%s) violates exit_clearance_fraction (max %s)" % [OPENING_ROOM_ENEMY_X, max_x])
	# assert(OPENING_ROOM_CHEST_X >= min_x, "OPENING_ROOM_CHEST_X (%s) violates entrance_clearance_fraction (min %s)" % [OPENING_ROOM_CHEST_X, min_x])

# Called whenever a fresh room is about to be generated (see load_room()
# above) - clears the PREVIOUS room's tracking so nothing about it leaks
# into the new one.
func reset_room() -> void:
	blob_defeated.clear()
	chest_opened.clear()
	forge_used.clear()
	structure_resolved.clear()
	shop_stock = []
	has_saved_position = false
	in_field_encounter = false
	last_encountered_blob_id = ""
	pending_enemy_data = null
	pending_encounter_enemies = []
	pending_chest_gold = -1
	pending_weapon_grant = null
	pending_non_battle_reward = false
