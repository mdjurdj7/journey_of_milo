extends Node2D
# The field room - the run's main scene between fights. Doesn't decide
# anything itself (see room_state.gd for what does, and run_state.gd for
# the fuller RunState/RoomState split) - it renders whatever RoomState
# already decided (the room's type, and the room_layout list of what's
# where) and reads RoomState to restore the player's position on return.
# room_layout is generated ONCE, by RoomState.load_room(), not re-rolled
# on every _ready() here - that's what keeps a room's contents stable
# across a "walk into a blob, fight it, come back" round trip instead of
# reshuffling underneath the player each time they return.

const BLOB_SCENE := preload("res://field_blob.tscn")
const CHEST_SCENE := preload("res://field_chest.tscn")
const MARKER_SCENE := preload("res://field_marker.tscn")
const NPC_SCENE := preload("res://field_npc.tscn")
const HEAP_SCENE := preload("res://field_heap.tscn")
const FORGE_SCENE := preload("res://field_forge.tscn")
const HEAP_SIFT_OUTCOME_TABLE := preload("res://resources/wreckage_heap/sift_outcomes.tres")
# This heap's own pool (TRIMMED from 6 to 4 entries, 2026-09-01 pool-
# scoping pass, then REMOVE_CARD restored to bring it to 5 the same day,
# same-day follow-up pass - card removal is a strong deckbuilder reward,
# the shop already sells it, and dropping it wasn't actually required for
# "the last dig always yields something," see field_heap.gd's own _ready()
# assert for what that guarantee actually depends on: entries.size() >=
# stage_textures.size(), not equality). REPLACES this constant's old "one
# shared table, referenced by every heap this run generates" role. This
# event appears at most once per run, so a run-shared drawn-set had
# nothing left to accomplish and actively prevented a BOUNDED per-heap dig
# count - field_heap.gd's own sift_outcome_table now defaults to
# SiftPoolScope.PER_INSTANCE, so despite this constant's name, draws
# against it are no longer tracked in RunState.sift_outcomes_drawn by
# default (see field_heap.gd's own sift_pool_scope doc for the full
# reasoning, and SiftOutcomePool.draw()'s own doc for the mechanism -
# unchanged, still available for a future SiftPoolScope.PER_RUN event
# that actually wants shared continuity).
const CURIO_SCENE := preload("res://field_curio.tscn")
const CURIO_OUTCOME_TABLE := preload("res://resources/events/curio_outcomes.tres")
# One shared table for every curio a run generates (2026-08-28, second-
# event pass) - no draw-without-replacement tracking needed here the way
# HEAP_SIFT_OUTCOME_TABLE's own doc describes (see field_curio.gd's own
# header: this is a one-shot pick, not a repeat-until-exhausted pool), so
# unlike that table there's no RunState-tracked "already drawn" set this
# needs to stay in sync with - every curio just picks fresh from this
# same table, independently, the instant it resolves.
const CARD_SCENE := preload("res://card.tscn")
# Reused as-is from battle/reward-screen/shop/deck-viewer (see this
# feature's own investigation report: card.gd is a self-contained
# Control, already instantiated outside battle by all three of those) -
# no field-specific Card variant needed.
const EXIT_SCENE := preload("res://field_exit.tscn")
const PAY_HOUSE_SCENE := preload("res://field_pay_house.tscn")
# One preload per known structure_id (see room_state.gd's _generate_
# event_layout() and field_structure.gd's own header for the full "adding
# a second structure" recipe) - _spawn_structure() below is the one new
# match case a second structure needs added here.

const FIELD_PARTICULATE_SCRIPT := preload("res://field_particulate.gd")
# See _populate_particulate_layer() below - set_script() onto a plain
# Polygon2D.new(), not an instanced scene, so this preloads the SCRIPT
# resource directly rather than a .tscn like the preloads above.

const SILHOUETTE_VERTICAL_SHADE_SHADER := preload("res://silhouette_vertical_shade.gdshader")
# See _apply_vertical_shade() below - one shared shader resource, a fresh
# ShaderMaterial per call so each element's own top_color/bottom_color can
# differ (2026-08-31 silhouette-shading pass, Art Direction Bible §7).

const PAINTED_PREVIEW_BACKGROUND_TEXTURE := preload("res://assets/regions/beach/PaintedBackgrounds/background_plate.png")
const PAINTED_PREVIEW_GROUND_TEXTURE := preload("res://assets/regions/beach/PaintedBackgrounds/ground_strip_tall.png")
const PAINTED_PREVIEW_FOREGROUND_TEXTURE := preload("res://assets/regions/beach/PaintedBackgrounds/foreground_band_tileable.png")
# REPLACES foreground_band.png (2026-09-05, foreground-seam fix) - the old
# asset was NOT a true seamless tile at viewport width (1915px content
# plus a 5px transparent sliver, needing region_rect to crop it down to
# an even 1920 and motion_mirroring retuned to match), which is exactly
# what produced the hard vertical seam where the band repeated. This one
# is a genuine seamless tile at exactly 1920x290 - see _apply_painted_
# preview()'s own foreground-band section for what that lets the code
# drop entirely.
const PAINTED_PREVIEW_BLOOM_TEXTURE := preload("res://assets/regions/beach/PaintedBackgrounds/sky_light_bloom.png")
# 1024x1024 RGBA (2026-09-05, sky-bloom pass) - a diffuse cool brightening
# patch composited over the background plate where cloud thins. See
# painted_preview_bloom_enabled's own doc and _apply_painted_preview()'s
# own bloom section for how it's placed/scaled/blended.
#
# See painted_preview_enabled's own doc / _apply_painted_preview() below -
# THROWAWAY preview assets, preloaded here rather than wired into
# field_room.tscn as ext_resources so the whole preview path lives in
# this one script and leaves nothing behind in the scene file.

const NORMAL_WALL_COLOR := Color(0.35, 0.35, 0.4, 1)
const BOSS_WALL_COLOR := Color(0.55, 0.15, 0.15, 1)
const ELITE_WALL_COLOR := Color(0.55, 0.45, 0.15, 1)
# Same weight/saturation as BOSS_WALL_COLOR, just gold-hued instead of
# red - the elite color language enemy.gd's elite name-intro and field_
# exit.gd's elite door preview already establish, extended to the room
# itself (see DESIGN.md's ELITE Rooms section).

# Where the single door sits near the far end of the room's floor line -
# on RoomState.floor_line_y, the same fixed y the player is always on -
# a door off that line would be visible but unreachable, since the
# player has no vertical movement at all (see player.gd). See _exit_x().
#
# ONE door only (DECIDED - see DESIGN.md's field movement redesign:
# navigation redesign step 1) - a room used to spawn one door per
# forward graph edge (up to RunState.max_forward_edges, 2 by default),
# spread horizontally when there were two. That's gone: every room gets
# exactly one door now, regardless of how many edges its graph node
# actually has - the run graph itself is UNCHANGED (still branches for
# real, see run_state.gd), only how many doors a room shows for it. See
# _spawn_exits() for which edge that one door temporarily follows, and
# why.
const EXIT_MARGIN := 100.0
# How far the exit sits in from the right wall's inner face - see
# RoomState.standard_room_width's own comment for the walking-time math
# this margin is one term of. Computed against the room's ACTUAL current
# width (via _exit_x() below) rather than a fixed X, so retuning
# standard_room_width keeps the exit at the same relative distance from
# the wall instead of drifting into it or floating in empty space.

# The room's actual current width (wall-to-wall, outer edge to outer
# edge) - RoomState.room_width() (2026-09-06, _room_width() dedup: this
# file used to keep its own identical copy, which is exactly what let it
# silently disagree with RoomState's own copy on TREASURE - see that
# function's own doc). Every wall/camera/exit position that depends on
# room width reads that ONE shared function now, so retuning combat_
# room_width/standard_room_width (on RoomState, the same "shared layout
# config" home floor_line_y already lives in) is the only edit needed to
# resize a room end to end - see RoomState.standard_room_width's own
# comment for the walking-time math behind its default, and RoomState.
# combat_room_width's for the single-screen override _is_single_screen_
# room() below gates on.

# True for every COMBAT or TREASURE room except the opening/arrival one
# (that exclusion only ever actually matters for COMBAT - see RoomState.
# room_width()'s own doc) - RENAMED from _is_single_screen_combat_room()
# (2026-08-31, treasure-overhang pass) when TREASURE joined COMBAT as a
# single-screen type. Shared by every single-screen-specific rendering
# concern (the static camera, the treasure overhang's own room-width-
# relative sizing) so none of them can disagree with RoomState.room_
# width() about which rooms this applies to.
func _is_single_screen_room() -> bool:
	var is_single_screen_type := RoomState.current_room_type == RoomType.Kind.COMBAT or RoomState.current_room_type == RoomType.Kind.TREASURE
	return is_single_screen_type and RunState.current_node != RunState.opening_node

# The room's fixed true height (unlike width, never retuned per-room -
# see ROOM_VERTICAL_CENTER below, which this mirrors as a full span
# rather than a center point). Used for the same "true outer edge, not
# the walls' inner collision face" purpose RoomState.room_width() serves
# horizontally - see _position_floor()/_populate_far_layer()'s own notes
# on why the sky/ground now extend all the way to it.
func _room_height() -> float:
	return ROOM_VERTICAL_CENTER * 2.0

func _exit_x() -> float:
	return _room_floor_right_x() - EXIT_MARGIN

# The room's true full-height vertical center (half of the 1080-tall
# room) - NOT the floor line (RoomState.floor_line_y). Used ONLY to
# center a full-height wall (the opening room's ocean/void - see
# left_wall.configure() calls below), which spans the entire room top to
# bottom regardless of where the player's floor line happens to sit.
# These two numbers coincided back when the floor line WAS the room's
# vertical center (both 540); they're independent now, and conflating
# them would misplace the ocean/void wall off-center.
const ROOM_VERTICAL_CENTER := 540.0

# --- Background layering (DECIDED - see DESIGN.md's field movement
# redesign note) ---
#
# The room is now a side view, not a top-down one: RoomState.floor_line_y
# is both the player's fixed floor line AND the horizon where "sky" ends
# and "ground" begins. Floor (see field_room.tscn, resized at runtime by
# _position_floor() below) represents ONLY the ground band, from that
# line down to the bottom wall - its top edge is the actual walkable
# surface, not just a flat room-wide tint anymore. Everything above that
# line, between the top wall and the ground, is this Background node's
# job.
#
# STRUCTURE vs CONTENT, deliberately split into two functions
# (_build_background_layers() below configures the layering itself;
# _populate_background_layer() fills each one with placeholder shapes) -
# this is the seam a future region's content would use: it would keep
# the exact same ParallaxBackground/ParallaxLayer setup (motion_scale,
# mirroring, layer count) and just call a DIFFERENT populate function -
# swapping which shapes/colors go into an already-correct layering
# system, not rebuilding the system itself.
@onready var background_far: ParallaxLayer = $Background/FarLayer
@onready var background_mid: ParallaxLayer = $Background/MidLayer
@onready var sky_layer: CanvasLayer = $SkyLayer
@onready var sky_rect: TextureRect = $SkyLayer/SkyRect
@onready var particulate_far_layer: ParallaxLayer = $Background/ParticulateFarLayer
@onready var particulate_near_layer: ParallaxLayer = $Background/ParticulateNearLayer
@onready var painted_mid_layer: ParallaxLayer = $Background/PaintedMidLayer
# Scene-authored (2026-09-05, mid-layer scene-node fix) - REPLACES a
# ParallaxLayer.new() created and added to Background at runtime.
# Matches every OTHER working ParallaxLayer in this room (FarLayer/
# MidLayer/ParticulateFarLayer/ParticulateNearLayer, all above), all
# authored directly in field_room.tscn rather than created at runtime.
# Empty in the scene - _apply_painted_preview() still populates it with
# sprites at runtime, same as before. (The actual reason the mid plates
# stayed invisible turned out to be unrelated to this - see
# painted_preview_bg_canvas_layer's own doc: bg_layer was covering the
# entire Background stack. This scene-authoring change is kept anyway
# since it's still the right convention to match.)
@onready var occluder_background: ParallaxBackground = $Foreground
@onready var occluder_layer: ParallaxLayer = $Foreground/OccluderLayer
@onready var occluder_far_layer: ParallaxLayer = $Foreground/OccluderFarLayer
# Added this pass (2026-08-30, foreground-depth pass) - a second
# ParallaxLayer under the SAME Foreground ParallaxBackground/CanvasLayer
# (so it inherits the same layer=1 override fixed two passes ago, and
# stays in front of Player for the same reason occluder_layer already
# does), declared BEFORE OccluderLayer in field_room.tscn so normal
# sibling draw order puts it BEHIND the near band while both stay in
# front of Player. A second ParallaxLayer, not a second ParallaxBackground -
# a different motion_scale is all either instance needs, and that's a
# per-ParallaxLayer property.

@export_group("Background layers")
@export_range(0.0, 1.0, 0.01) var far_layer_motion_scale: float = 0.15
@export_range(0.0, 1.0, 0.01) var mid_layer_motion_scale: float = 0.45
@export var use_field_backdrop: bool = false
# Subtle on purpose - a far layer that barely moves and a mid layer that
# moves noticeably more (but still well under the camera's own 1:1 speed)
# is what reads as depth; anything close to 1.0 would just look like a
# second, slightly-lagging copy of the room instead of something farther
# away. Both well clear of the ground/foreground (Floor, walls, content),
# which are ordinary scene geometry moving exactly 1:1 with the camera -
# not inside a ParallaxLayer at all, since they have to align exactly
# with the player's real world position, not lag behind it.

# --- Far/mid structure layers (2026-08-30 strip pass: both shape pools
# are now empty - see _populate_far_layer()/_populate_mid_layer() - so
# these layers currently render only the sky/haze and vegetation set up
# elsewhere in this function). Same layering STRUCTURE as before (see
# the class doc above this @export group, and _build_background_layers()
# below) - only what fills each layer has changed over time. Applies to
# every room, not just the opening one: the opening room already runs
# this exact same function before its own coastal dressing (see
# _apply_opening_room_layout(), called AFTER this). ---
#
# Bug fixed along the way, not just a content swap: FarLayer used to be
# COMPLETELY invisible - both layers drew a full opaque sky rectangle,
# MidLayer is added as a LATER sibling so it draws on top, and an opaque
# rect exactly covers whatever's behind it. Confirmed by screenshotting
# with MidLayer hidden: a distinctly different silhouette was sitting
# back there the whole time, never once rendered. Only FarLayer draws the
# sky fill now (see _populate_far_layer()); MidLayer draws ONLY its own
# silhouettes with no rect behind them (see _populate_mid_layer()), so
# FarLayer's sky and distant shapes actually show through the gaps
# between MidLayer's nearer ones - real depth, not a hidden duplicate.
@export_group("Background layers - Sunken Works sky & haze")
@export var sky_gradient_top_color: Color = Color(0.7, 0.74, 0.78, 1)
@export var sky_gradient_horizon_color: Color = Color(0.85, 0.86, 0.86, 1)
# REVERTED (2026-08-31, field/battle decoupling pass) - back to the
# ~0.73/~0.86 pair the 2026-08-30 palette retune below established. A
# same-day battle-backdrop-match pass had briefly moved this to #E6E8E8/
# #EDEDED (luminance ~0.93, sampled straight from the battle plate) and
# chased the tower/cloud values to match - but field and battle are never
# on screen together, so matching them bought nothing and cost the field
# its own coherence: a sky uniformly that pale left no room to contain
# the tower silhouette, and the clouds all but vanished against it. Two
# internally coherent looks (field's own high-key-but-legible pale sky,
# battle's own separately art-directed backdrop) serve better than one
# compromised toward the other. tower_color and cloud_color are reverted
# alongside this, back to their own pre-match values - see each's own
# doc below.
#
# Retuned (2026-08-26, opening-room ground-texture pass) toward Sunken
# WorksPalette.SKY_HIGH/SKY_HORIZON (battle_background.gd's own fallback
# sky, modeled on the real SunkenWorks1.png battle art) - both rooms sit
# under the same light, so the field's own sky should read as the same
# pale, high-key sunlight the battle backdrop already establishes,
# instead of the more saturated blue this used to be. NOT a straight copy
# of that palette's raw values: SKY_HORIZON's own luminance (~0.81) would
# fail the contrast ceiling below outright (max_background_luminance is
# ~0.676, derived from the palest enemy) - these two colors are chosen to
# read the same DIRECTION (paler, narrower R/G/B spread than before,
# horizon nearly neutral) while actually passing that check, not an
# approximation that happens to clear it by luck.
#
# Distinct from the 2026-08-24 desaturation pass reverted the very next
# day (see DESIGN.md's Sunken Works entry) - that pass is NOT being
# redone here, on purpose: it failed by desaturating AND darkening
# together (top luminance ~0.53 -> ~0.45, an actual dimming), which read
# as overcast and contradicted this biome's own HARSH BRIGHT SUNLIGHT
# pillar. This retune only desaturates - top luminance is ~0.60 and
# horizon ~0.65, BOTH HIGHER than the values being replaced (~0.53/~0.61),
# so the sky gets paler and less saturated without getting dimmer
# (the 2026-08-30 retune below pushed both stops paler still, to
# ~0.73/~0.86 - same direction, taken further). "High-
# key" and "harsh bright sunlight" are the same read, not opposed ones -
# a beach under strong direct sun bleaches OUT saturation precisely
# because the light is so strong, it doesn't go moody/gray from a lack of
# it. horizon_haze inherits this for free (its color is drawn straight
# from sky_gradient_horizon_color - see that field's own doc), so the
# seam blend follows automatically, no separate change needed there.
# Replaces the old flat sky_color fill (2026-08-24) with a real vertical
# gradient - deeper/cooler toward the top, lighter AND warmer toward the
# horizon (sea haze), per this pass's own brief. Built into sky_rect's
# texture by _build_sky_gradient() below from just these two colors - no
# separate GradientTexture2D/Gradient resource exposed on its own, same
# "simple exported Color, not a sub-resource to open a second inspector
# for" shape every other tunable in this file already uses.
#
# SUPERSEDED (2026-08-30 palette retune): the horizon stop no longer
# carries a deliberate warm shift - the region's own brief calls for no
# warm accent anywhere, a washed-out white sky rather than a blue or
# amber one. Both stops now sit close to neutral, narrow R/G/B spread,
# with the horizon still the paler/brighter of the two (nearly white)
# so the seam still reads as haze against ground_base_color, which is
# equally near-neutral now rather than the warm tan this paragraph
# used to describe. Still the brighter of the two stops by design
# (that's the whole point of a horizon read) - see
# _validate_background_contrast() below, which checks it (not the top
# color) against the ceiling, since it's the one that could actually
# violate it.
@export_range(0.0, 1.0, 0.01) var sky_warm_band_fraction: float = 0.15
# How much of the gradient's OWN vertical range (0 = sky top, 1 = the
# horizon - see _build_sky_gradient()'s fill_to note) carries the warm
# shift, counted backward from the horizon - the gradient holds flat
# sky_gradient_top_color from 0 up to (1 - this), then interpolates to
# sky_gradient_horizon_color only over the remaining fraction.
#
# Added 2026-08-24, second correction: the warmth retune above got the
# ENDPOINT color right, but a plain 2-stop linear gradient interpolates
# across its ENTIRE range - so the warm shift bled through most of the
# visible sky instead of staying near the seam, leaving sky and ground
# reading as nearly the same value across a big share of the frame. The
# horizon HAZE band is what's actually meant to do the sky-to-ground
# blending (see horizon_haze_height's own doc) - the gradient itself
# only needs to carry the warmth far enough to feed that band, not
# repaint the whole sky. Small by design (0.15 = the last 15% of the
# sky's vertical range, just above the horizon); if in doubt, tune this
# DOWN, not up.
@export var sky_light_enabled: bool = true
@export_range(-1.0, 1.0, 0.01) var sky_light_direction: float = 1.0
# -1 = light from the left (left side of the horizon reads brighter),
# 0 = no horizontal variation at all, 1 = light from the right. Bible §6
# permits the atmosphere to read as "faintly luminous without an obvious
# directional source" - this is that: not a sun, not a visible source,
# just a faint asymmetry suggesting one exists somewhere off-frame.
@export_range(0.0, 0.5, 0.01) var sky_light_strength: float = 0.06
# How far the horizon color shifts toward bright/dim on either side, via
# Color.lightened()/darkened() (see _signed_shade() below) - symmetric,
# named Godot operations already used elsewhere in this file for the
# same "shift around a base color, don't replace it" shape (see
# _depth_tinted_color()'s own doc from an earlier pass). At the default
# 0.06 against sky_gradient_horizon_color (0.85, 0.86, 0.86), that's
# roughly #E6E6E3 on the bright side and #CCD1D4 on the dim side - close
# to, not required to hit exactly (lightened()/darkened() move toward
# white/black proportionally per channel, not a flat per-channel offset,
# so the exact hex depends on the base color's own channel spread).
# Deliberately small (the @export_range's own upper bound is 0.5, well
# past anything this pass intends to ship at) - this must stay a "faint
# suggestion light comes from somewhere," never a visible effect; if it
# reads as an effect rather than atmosphere, the fix is turning this
# DOWN, not redesigning the technique.
#
# Applied ONLY to sky_gradient_horizon_color, never sky_gradient_top_
# color (this pass's own explicit instruction: "high sky stays even") -
# see _add_sky_light_gradient() below for how that's enforced spatially
# (a vertical alpha ramp, zero at the same point the base gradient's own
# warm band starts, full exactly at the horizon) rather than just by
# which color value gets read.
@export var far_structure_color: Color = Color(0.7803922, 0.7803922, 0.7803922, 0.6)
@export var far_structure_count: int = 1
# Pale, nearly neutral gray (2026-08-30 palette retune) - a distant
# silhouette bleached by the same harsh, high-key sunlight the sky and
# ground read under, not a distinct material color of its own. Still
# checked against background_detail_luminance_floor below (see
# _validate_background_contrast()) - lower alpha (0.6) is what reads as
# atmospheric haze at a distance, blended toward the sky behind it,
# never darker than it. NOW ACTUALLY APPLIED (2026-08-30 landform pass) -
# see _add_far_landform()/landform_far_width_fraction below; this color
# and far_structure_count sat unused since the 2026-08-30 strip pass
# emptied this layer's shape pool, kept because they were already
# checked by the validator and safe to reuse once this layer got real
# content again.
#
# RGB RETUNED (2026-08-31, battle-backdrop-match pass) - #C7C7C7
# (luminance 0.780), sampled from the battle plate's own distant
# landform (0.776, nearly colorless). Alpha (0.6) UNCHANGED on purpose -
# this pass is a colour match, not a re-tune of how hazy the silhouette
# reads at a distance.
@export var landform_far_texture: Texture2D
# assets/regions/beach/landform_far.png (2163x221, pure white on
# transparent, base-anchored) - REPLACES the procedural _landform_shape()
# (2026-08-30 landform-asset pass, deleted along with LANDFORM_PROFILE -
# a hand-tuned multiplier table reads as a row of triangles, not the
# rounded/eroded terrain a generated asset can be). White, not black -
# modulate multiplies, same lesson the vegetation clump assets already
# established (see that pass's own report: 0 x anything = 0, so a black
# mask can never be tinted). Assigned in the scene, not hardcoded as a
# preload here, matching every other generated-asset texture in this
# file. _add_far_landform() no-ops if this is unset.
@export_range(0.0, 1.0, 0.01) var landform_far_width_fraction: float = 0.55
@export_range(0.0, 1.0, 0.01) var landform_far_height_fraction: float = 0.10
# Fractions of background_tile_width/_sky_band_height() respectively -
# see _add_far_landform() below. Wider and lower than the mid layer's own
# equivalents (landform_mid_width_fraction/_height_fraction) - a distant
# ridge barely separated from horizon_haze, not a nearer feature with its
# own presence. Both fractions are honored EXACTLY via non-uniform
# Sprite2D.scale (the asset's own native aspect ratio is not preserved) -
# see _add_far_landform()'s own doc for why.
@export var landform_far_base_lift: float = 45.0
# How far ABOVE floor_line_y the far landform's own base sits (2026-08-30
# far-base-lift pass) - the mid landform keeps planting exactly at floor_
# line_y, unchanged. Real terrain further from the viewer has its base
# HIGHER in frame, because the ground itself recedes toward the horizon
# between the viewer and it - a far ridge and a near headland both
# planted on the exact same line read as a flat cut-out stack (paper
# silhouettes propped up side by side), not depth. Raising only the far
# base is what actually sells "this is further back," independent of its
# own width/height/color, which stay exactly as tuned. Any FUTURE far-
# layer occupant should use the same treatment (its own base lifted
# above floor_line_y, not planted on it) for the same reason - this
# isn't a one-off correction specific to this one asset.
@export_range(0.0, 1.0, 0.01) var landform_far_chance: float = 0.6
# Rolled once per room (2026-08-30 landform-variety pass) - REPLACES far_
# structure_count's old role of directly controlling how many landforms
# appear (see _populate_far_layer() below: far_structure_count is now
# just an on/off GATE checked before this roll runs, not a count). A room
# may end up with no far landform at all - some stretches of coast are
# flat, per this pass's own brief, and an absent landform is also the
# only way for a room to NOT expose the 2200px motion_mirroring repeat,
# since there's nothing repeating.
@export_range(0.0, 1.0, 0.01) var landform_size_variation: float = 0.3
# +/- fraction applied to landform_far_width_fraction/_height_fraction
# AND landform_mid_width_fraction/_height_fraction (2026-08-30 landform-
# variety pass) - ONE shared knob for both layers, not a separate far/mid
# pair, since it governs the same kind of per-instance variety in both
# places. Width and height are each rolled INDEPENDENTLY within this
# range (see _add_far_landform()/_add_mid_landform() below) - varying
# them together would just uniformly rescale one fixed silhouette;
# varying them apart is what makes different rooms' landforms differ in
# PROPORTION, not just size.

@export var horizon_haze_height: float = 90.0
@export_range(0.0, 1.0, 0.01) var horizon_haze_alpha: float = 0.35
# The strip that kills the hard sky/ground seam (this pass's own brief) -
# a soft top-to-bottom alpha fade (Polygon2D.vertex_colors, not a flat
# rect) sitting with its BOTTOM edge exactly on RoomState.floor_line_y
# and reaching horizon_haze_height upward from there, colored from sky_
# gradient_horizon_color at horizon_haze_alpha fading to fully transparent
# at its own top edge. Lives inside FarLayer (see _populate_far_layer())
# so it tiles/scrolls for free via that layer's own existing motion_
# mirroring - no separate ParallaxLayer or tiling logic needed just for
# this. Only ever visible ABOVE the seam - anything at or below floor_
# line_y is covered by Floor's own opaque fill regardless (Floor draws
# AFTER Background in field_room.tscn), so extending the band downward
# would be wasted geometry, not a visual difference.

@export_group("Background layers - clouds")
@export var clouds_enabled: bool = true
@export var cloud_textures: Array[Texture2D] = []
# assets/regions/beach/Clouds/cloud_00.png..cloud_05.png (six forms,
# 229-407 wide by 130-257 tall, pure white on transparent, alpha reaching
# zero on all four edges) - REPLACES cloud_band_texture and the tiled-band
# machinery entirely (2026-08-31, scattered-cloud pass). Eight passes tried
# to make ONE wide tiling band never show a seam (wrap-seam fixes, a
# coverage-step fix, a sign bug in the anchor math this project's own
# history now records in full) - discrete, individually-placed sprites
# eliminate the problem class instead of patching it further: there is no
# tiling, no region, no wrap, so there is nothing for a seam to be. White,
# not black - modulate multiplies (cloud_color combined with each
# instance's own alpha below), same reasoning landform/vegetation assets
# already established. Assigned in the scene, matching vegetation_clump_
# textures's own array-of-variants pattern below - _add_clouds() no-ops if
# this is empty.
@export var cloud_count: int = 11
@export var cloud_color: Color = Color(0.92, 0.93, 0.94, 1)
# REVERTED (2026-08-31, field/battle decoupling pass) - back to its
# original value. A same-day sky-rebalance pass had dropped this to
# (0.84, 0.85, 0.86) to keep clouds visible against a sky brightened to
# match the battle plate; with that brightening itself reverted (see
# sky_gradient_horizon_color's own doc above), this color's original
# near-identical-to-horizon luminance is back to reading correctly -
# a subtle value shift against the sky it sits on, not a hue - so no
# compensating shift is needed here either. cloud_color is exempt from
# the contrast validator (see that validator's own doc), so this was
# never about clearing a floor either way.
@export var cloud_alpha_min: float = 0.30
@export var cloud_alpha_max: float = 0.60
@export var cloud_scale_min: float = 1.6
@export var cloud_scale_max: float = 3.2
@export var cloud_vertical_squash: float = 0.7
# Applied on top of each sprite's own random uniform scale (see _add_
# clouds() below), not instead of it - a fixed flattening factor is what
# makes every cloud read as a broad, low shape near the horizon (Art
# Direction Bible §14: "clouds become broad value structures") rather
# than each one's own painted silhouette proportions varying whether it
# happens to look tall or wide at a given random scale.
@export var cloud_band_top_y: float = 40.0
@export var cloud_band_bottom_y: float = 340.0
@export var cloud_drift_enabled: bool = true
@export var cloud_drift_speed_min: float = 2.0
@export var cloud_drift_speed_max: float = 6.0
# px/sec, rolled once per cloud at creation (and kept for that cloud's
# whole lifetime, including across wraps - see _update_cloud_drift()
# below) - a shared speed for every cloud would have them all drift in
# visible lockstep, the same "one flat layer doubled" problem this file's
# other multi-instance systems (vegetation clumps, the old cloud bands)
# already solve by varying something per instance.

@export_group("Background layers - Sunken Works near structures")
@export var mid_structure_color: Color = Color(0.7215686, 0.7098039, 0.6980392, 1)
# NOW ACTUALLY APPLIED (2026-08-30 landform pass) - see _add_mid_
# landform()/landform_mid_width_fraction below. Sat unused since the
# 2026-08-30 strip pass emptied this layer's own shape pool, kept
# because it was already read by _validate_background_contrast() and
# safe to reuse once this layer got real content again.
#
# RETUNED (2026-08-31, battle-backdrop-match pass) - #B8B5B2, sampled
# from the battle plate's own distant landform (same 0.776 reference
# far_structure_color's own doc cites - this is the nearer, slightly
# more saturated of the two landform layers, not a second independent
# sample).
@export var mid_structure_count: int = 1
@export var landform_mid_textures: Array[Texture2D] = []
# assets/regions/beach/Landforms/landform_mid.png (2166x510) plus three
# silhouette variants added in the same pass - landform_mid_b.png (single
# centred peak), landform_mid_c.png (long asymmetric rise), landform_mid_d.png
# (two masses with a gap between them), each ~2170x355, pure white on
# transparent, base-anchored - same array-of-textures pattern as vegetation_
# clump_textures below, picked at random per instance in _add_mid_landform()
# (2026-08-31 landform-variety pass). See landform_far_texture's own doc for
# why these must be white, not black. _add_mid_landform() no-ops if this is
# empty.
#
# landform_mid_d's gap is a real hole in the silhouette, not a seam to hide -
# whatever already shows through the sky elsewhere (mid recession band 0 and
# horizon_edge, both added to MidLayer BEFORE the landform in _populate_mid_
# layer() below, then FarLayer/SkyLayer behind that) shows through the gap
# too, exactly as if there were no landform there at all. Confirmed those
# bands are uninterrupted _add_wavy_band() spans across the full background_
# tile_width with no landform-shaped notch of their own, so nothing behind
# the gap depends on the landform's own silhouette - there is no seam for
# them to line up with.
@export_range(0.0, 1.0, 0.01) var landform_mid_width_fraction: float = 0.35
@export_range(0.0, 1.0, 0.01) var landform_mid_height_fraction: float = 0.18
# Narrower and taller than the far layer's own equivalents
# (landform_far_width_fraction/_height_fraction) - a nearer headland or
# outcrop with its own presence, not a hazy distant ridge. mid_structure_
# color's full opacity (vs far_structure_color's 0.6 alpha) reinforces
# the same "more defined, closer" read. Both fractions honored exactly
# via non-uniform scale, same as the far layer - see landform_far_width_
# fraction's own doc. Now the CENTRE of a per-instance range, not a fixed
# value - see landform_size_variation's own doc (declared alongside
# landform_far_chance, shared by both layers).
@export_range(0.0, 1.0, 0.01) var landform_mid_chance: float = 0.65
# Rolled once per room, independently of landform_far_chance (2026-08-30
# landform-variety pass) - see that export's own doc for the mechanism;
# mid_structure_count plays the same on/off-gate role for this layer that
# far_structure_count now plays for far's.
@export var vegetation_color: Color = Color(0.46, 0.55, 0.44, 1)
@export var vegetation_per_structure: int = 1
@export var structure_scale: float = 1.25
@export_range(0.0, 1.0, 0.01) var vegetation_depth_fade: float = 0.35
# Matches ground_patch_depth_fade's default (2026-08-30 depth-variation
# pass, vegetation follow-up) - reuses _depth_tinted_color() exactly as
# ground patches/seam debris already do (see that function's own doc for
# the far-paler/near-slightly-darker formula). Mid-layer clumps sit at a
# single fixed Y (floor_line_y, no per-clump vertical range - see
# _populate_mid_layer()) so they get one fixed fade at t=0, the far end
# of the range, rather than a gradient; seam vegetation DOES still have a
# small per-clump Y jitter (see _add_seam_vegetation()) so it gets a real
# per-clump t like ground patches/seam debris do. Coastal seam vegetation
# is untouched - see _add_coastal_seam_vegetation()'s own doc for why.
# vegetation_color/vegetation_per_structure color and count the clumps
# _populate_mid_layer() scatters across the mid layer (see that
# function) - independent of structure placement since 2026-08-30 (the
# structure pool is now empty). structure_scale only affects structure
# silhouettes, which the (now-empty) far/mid pools no longer place.
#
# DENSITY (DECIDED - reworked after the first pass read as visually
# noisy): "the environment reads at a glance," not a field of same-sized
# objects competing for attention - composition and restraint, per
# Pillar 5's aesthetic. far_structure_count/mid_structure_count both
# dropped from 2 to 1 (one deliberate element per tile per layer, not
# several), and structure_scale (1.25) makes each one that DOES appear
# larger and simpler rather than making up for fewer shapes with smaller
# ones - see _populate_far_layer()/_populate_mid_layer() for where this
# multiplies each shape's own base size. The biggest lever, though, is
# background_tile_width below: a much wider repeat interval means more
# negative space between repeats, not just fewer shapes within one.

@export_group("Background layers - recession bands")
@export var recession_bands_enabled: bool = true
@export var recession_band_count: int = 4
@export var recession_band_color: Color = Color(0.79, 0.78, 0.75, 1)
@export var recession_band_top_y_offset: float = 300.0
@export var recession_band_wave_amplitude: float = 14.0
# Fills the sky band between floor_line_y and floor_line_y -
# recession_band_top_y_offset with recession_band_count wavy bands
# stacked upward from the walk line (band 0 sits directly on the line).
# Each band steps linearly toward sky_gradient_horizon_color and toward
# zero alpha as it goes up (Bible §4 - distance removes contrast and
# saturation) - see _add_recession_band()'s own doc for the formula.
#
# Rendered in background_mid/background_far, NOT content_root - value
# stepping alone reads as flat stripes sliding past once the camera
# pans; parallax speed is what actually sells "these are at different
# distances." Far/Mid are exactly the layers this needs: their old
# structure-silhouette pools are empty (2026-08-30 strip pass, see their
# own header) and were left that way for content like this.

@export var horizon_edge_enabled: bool = true
@export var horizon_edge_height: float = 10.0
@export var horizon_edge_color: Color = Color(0.70, 0.69, 0.67, 1)
@export var horizon_edge_wave_amplitude: float = 2.0
# A thin wavy band in the mid layer, giving the seam a soft but definite
# boundary, unlike horizon_haze's pure continuous fade (no edge
# anywhere).
#
# CENTERED ABOVE floor_line_y, not ON it (2026-08-30 fix - see
# _add_horizon_edge()'s own doc) - a band centered ON the line put half
# its own height at y >= floor_line_y, which Floor (drawn after
# Background, see field_room.tscn's own child order) overpaints
# unconditionally. That's fine as a way to get a soft BOTTOM edge for
# free, but centering there meant only the unjittered top half (height/2)
# was ever visible at all, and the nominal bottom edge sat exactly on
# the seam with nothing pinning it there. Offsetting the center to
# floor_line_y - height/2 puts the WHOLE band above the line by design;
# Floor still eats any downward jitter that dips below floor_line_y,
# which is the soft-bottom effect actually wanted, without wasting half
# the band's own height on guaranteed overpaint.
#
# wave_amplitude MUST stay <= height / 2.0 (enforced by an assert in
# _add_horizon_edge()) - _add_wavy_band() jitters the top and bottom
# edges independently per segment by up to +/-wave_amplitude each; once
# that jitter range is wider than the band's own unjittered half-height,
# a segment's top-edge draw can land below that same segment's
# bottom-edge draw, and the polygon self-crosses there instead of just
# reading as wavier. That's exactly what happened at the old 6.0/5.0
# pairing (half-height 3.0 < amplitude 5.0) - the "edge" was dominated by
# per-segment noise, not a jitter added on top of a real shape.

@export_group("Background layers - tower")
@export var tower_enabled: bool = true
@export var tower_color: Color = Color(0.775, 0.775, 0.775, 1)
# REVERTED (2026-08-31, field/battle decoupling pass) - back to its
# original value. This had been raised twice in the same day chasing a
# sky brightened to match the battle plate (0.775 -> 0.847, then
# re-expressed precisely as #D8D8D8 = 0.8470588) - each move restoring
# the tower's ORIGINAL 0.082 gap against a horizon that kept getting
# brighter. With that brightening itself reverted (sky_gradient_horizon_
# color is back to 0.857 luminance - see its own doc above), the tower's
# original value already sits at that same 0.082 gap again on its own;
# no rescale needed. The field_room.tscn override on this node is
# reverted alongside this, back to 0.775 as well.
@export_range(0.0, 1.0, 0.01) var tower_height_fraction_start: float = 0.50
@export_range(0.0, 1.0, 0.01) var tower_height_fraction_end: float = 0.56
# REPLACES the old flat tower_height_fraction (2026-08-31, region-progress
# pass) rather than keeping it alongside these two as an unused leftover -
# every reader of this height now has exactly one source, not a live pair
# plus a dead third value someone could still edit in the Inspector with
# no effect. _add_tower_silhouette() below interpolates between these two
# by RoomState.region_progress (docs/REGION_01_v1.md §§3-4: the tower
# grows nearer across the region as the player walks inland, toward the
# signal it calls from).
#
# The range is deliberately narrow - 0.50 to 0.56, six points of the
# tower's own height fraction across the ENTIRE region. This game spans
# three or four regions total (docs/REGION_PROGRESSION_v1.md), so Region
# 1's own share of the full approach to the tower is small; if this range
# were wide enough to read as obvious growth within Region 1 alone, later
# regions would have nowhere left to grow into and the tower would arrive
# "solved" long before the player actually reaches it. Per-room the change
# has to be imperceptible (region_progress moves by roughly 1/layer_count
# each room - a fraction of this already-narrow range) and only legible
# across the whole region, comparing a late room back to an early one, not
# felt as motion room to room.
@export_range(0.0, 1.0, 0.01) var tower_width_fraction: float = 0.09
@export_range(0.0, 1.0, 0.01) var tower_screen_x_fraction: float = 0.72
@export_range(0.0, 1.0, 0.01) var tower_taper: float = 0.55
# The tower is intact and calls across the whole run (see docs/REGION_
# PROGRESSION_v1.md §3) - a fixed landmark that only ever resolves with
# proximity, never moves on its own. Region 1 (docs/REGION_01_v1.md §4)
# has it "barely resolvable... merging with atmospheric illumination at
# extreme distance," which is why it lives here and not as a normal
# far-layer silhouette.
#
# PARENTED TO SkyLayer, NOT background_far (2026-08-30, investigated and
# rejected first - see that investigation's own report). FarLayer is a
# ParallaxLayer with far_layer_motion_scale = 0.15 (nonzero): any child
# of it scrolls at 0.15x the camera's pan. Most room types (standard_
# room_width, camera.follow_enabled = true) would drift the tower up to
# ~400px across the screen as the player walks a single room - exactly
# the "drifting" a fixed landmark can't do. Worse, non-opening COMBAT
# rooms run a STATIC camera (camera.follow_enabled = false, camera.
# position pinned to Vector2.ZERO - see _position_room_bounds()) where
# that same FarLayer child would sit frozen instead: one shape, two
# incompatible behaviors depending on room type. SkyLayer is a viewport-
# anchored CanvasLayer (layer -100, see its own doc above sky_rect) with
# no motion_scale at all - screen-fixed by construction, identical in
# every room type, which is also physically correct: an object at "the
# tower is visible from every region" distance shows no observable
# parallax from a single room's worth of walking (Bible §4).
#
# tower_screen_x_fraction is a fraction of the VIEWPORT's width, not
# background_tile_width - SkyLayer's children live in screen-pixel
# space (see sky_rect's own full-viewport anchoring), not the parallax
# tile space background_far/background_mid content is built in.
#
# The interpolated height fraction is of _sky_band_height() (the sky's
# own vertical span, floor_line_y - BACKGROUND_TOP_Y) - at tower_height_
# fraction_start's default 0.50 that's ~395px on today's ~790px band, top
# edge landing near y=435; at the region-1 end (0.56) roughly 24px taller.
# tower_width_fraction is of the tower's OWN computed height, not the sky
# band, so retuning height alone keeps the proportions sane without a
# second retune. tower_taper is the top width as a fraction of the base
# width (0.55 = top about half as wide as the base) - see _add_tower_
# silhouette()'s own doc for the actual point layout and where the
# asymmetry comes from.

@export_group("Background layers - vertical shading")
@export var silhouette_shading_enabled: bool = true
@export_range(0.0, 0.5, 0.01) var landform_vertical_shade: float = 0.08
@export_range(0.0, 0.5, 0.01) var foreground_vertical_shade: float = 0.10
# Every textured silhouette element (mid/far landform, near/far foreground
# band) currently renders at one flat modulate tint with no internal value
# variation - the main reason the frame reads flat (Art Direction Bible §7:
# dark areas should retain a relationship with the palette, not be
# uniform). _apply_vertical_shade() below applies a shared gradient-multiply
# shader (silhouette_vertical_shade.gdshader) instead: top_color = the
# element's existing base color (far_structure_color, mid_structure_color,
# occluder_color, or the far band's own lerped tint) lightened by the
# matching shade amount here, bottom_color = the same base darkened by it -
# a lit crest, a shadowed base, still centered on the exact color already
# tuned for that element. landform_vertical_shade covers both landform
# layers (they share one knob, same as landform_size_variation above);
# foreground_vertical_shade covers both foreground bands. No existing color
# value changes - this only adds variation AROUND each one.
#
# MODULATE INTERACTION: these elements used to carry their tint entirely
# via Sprite2D.modulate. That can't stay true once this shader is attached
# - modulate is still multiplied into COLOR before the shader ever runs
# (see the shader's own comment), so leaving modulate at the full base
# color AND multiplying by a lightened/darkened copy of that same color in
# the shader would double-apply it, darkening (or lightening) everything
# well past the tuned value. _apply_vertical_shade() avoids this by moving
# color entirely into the shader's uniforms and reducing modulate to
# Color(1, 1, 1, base_color.a) - alpha only, RGB is a no-op multiply by
# white. That keeps each element's existing alpha (far_structure_color's
# 0.6, occluder_color's 0.92, etc.) working exactly as before while
# leaving color with exactly one source of truth per pixel.
#
# DISABLED (silhouette_shading_enabled = false): top_color and bottom_
# color both get set to the plain base color, no lighten/darken - the
# gradient mix becomes a flat fill equal to that color, and modulate still
# carries only alpha, so the rendered result is pixel-identical to today's
# flat-modulate tint either way.
#
# TEXTURE ASSETS MUST BE WHITE, NOT BLACK (2026-08-31 white-mask pass) -
# the shader multiplies texture RGB by the gradient (see silhouette_
# vertical_shade.gdshader's own comment); a black mask forces that product
# to (0,0,0) regardless of what top_color/bottom_color compute to, the
# same trap the foreground bands originally shipped into (see occluder_
# color's own doc) and the same lesson vegetation_clump_textures already
# established. landform_far_texture, landform_mid_textures, and both
# foreground_band_texture* assets are all white masks today, for exactly
# this reason. tower_color's own Polygon2D (_add_tower_silhouette()) is
# the one remaining silhouette this shader ISN'T applied to, and it isn't
# a texture asset at all - no black-vs-white question applies to it as
# drawn today. If a gradient is ever added there, note that an untextured
# Polygon2D samples TEXTURE as opaque white by default, so it would behave
# like the landform/foreground assets do now (tintable) with no separate
# asset to swap - the trap only exists for an actual black texture file.

@export_group("Region gradient")
@export var region_gradient_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var gradient_variance: float = 0.15
@export var ground_color_wet: Color = Color(0.74, 0.70, 0.65, 1)
@export var ground_color_dry: Color = Color(0.81, 0.76, 0.71, 1)
# WARMED (2026-09-01, battle-plate ground-match pass) - same ochre-lean
# hue construction as ground_base_color's own warm shift above (R/G/B
# spread around a fixed midpoint, not a hue-neutral darkening), solved
# per-color to preserve EACH color's own prior luminance (wet: 0.7063 vs
# 0.7059 before; dry: 0.7693 vs 0.7691 before - both within 0.0004,
# background_plane_luminance_floor's 0.70 clears with essentially the
# same margin as before either color). Chroma (max-min) landed at 0.09
# (wet) and 0.10 (dry) - both inside the battle backdrop's own measured
# 0.077-0.106 ground chroma range, with wet deliberately the lower of the
# two so it still reads cooler/less saturated than dry - damp sand is
# cooler than dry sand, and that relationship is part of what the
# gradient communicates, not just an incidental side effect of matching
# a floor. ground_texture_depth_tint is UNCHANGED - the falloff-strength
# mismatch against the battle plate is a separate decision, deferred
# because closing it for real would push the near edge below the plane
# floor (see that export's own doc).
@export_range(0.0, 1.0, 0.01) var foreground_band_crossover: float = 0.55
# Region 1's wet-to-dry gradient (docs/REGION_01_v1.md §3: tidal flat to
# dry inland) driven by RoomState.region_progress, which the tower already
# reads (see tower_height_fraction_start/_end's own doc) - this group
# wires the SAME depth signal into the ground/vegetation/foreground/
# landform systems _roll_region_gradient_value() and _build_background_
# layers()/_apply_standard_ground_treatment() below actually touch. Does
# NOT wire standing water or visible life - neither exists in the game
# yet.
#
# region_progress alone would make every run's arc identical - the same
# layer always reading exactly the same wetness. gradient_variance is the
# fix: each room's ACTUAL gradient value (_region_gradient_value, rolled
# once by _roll_region_gradient_value() below) is region_progress plus a
# random offset of up to +/-gradient_variance, clamped back to [0, 1] -
# a TARGET the room varies around, not a value it lands on exactly, so
# two rooms at similar depth read as similar but not identical (this
# pass's own explicit brief). Every consumer below reads THIS rolled
# value, never RoomState.region_progress directly, so they all agree with
# each other about how wet/dry a given room actually is.
#
# ground_color_wet/_dry replace ground_base_color as the ground's actual
# rendered tint when region_gradient_enabled is true (see _region_ground_
# color() and _apply_standard_ground_treatment() below) - ground_base_
# color itself is UNCHANGED and stays the exact fallback used when the
# gradient is disabled, not repurposed as either endpoint. Both endpoints
# were chosen to clear background_plane_luminance_floor (0.70) on their
# own - ground_color_wet's luminance is ~0.706, barely above the floor,
# which is why it reads as damp/cool/grey rather than simply darker: this
# palette (Bible §7) can't render "wet" as "dark" without failing
# _validate_background_contrast() (see that function's own doc, updated
# to check both endpoints below), so wetness is carried entirely by a
# cooler, greyer hue instead of by lowering value. ground_color_dry sits
# comfortably higher (~0.769), warmer and paler - the "bright, empty, not
# cold" read Region 1's own light section calls for at its driest.
#
# foreground_band_crossover selects which band asset plays outside the
# opening room (see _populate_occluder_layer() below): the wrack-line
# coastal band below the threshold (a tide that still reaches), the plain
# grass band at or above it (a tide that no longer does). The opening
# room keeps the coastal band regardless of this threshold or its own
# gradient value (RoomState.region_progress is 0.0 there by construction
# anyway - see that field's own doc - so it would pick coastal either
# way, but the check is explicit, matching every other opening-room
# special case in this file, not left to arithmetic to get right by
# coincidence).
#
# region_gradient_enabled = false is a full, real off switch, not a
# partial one - every consumer below branches on it independently and
# falls back to EXACTLY today's flat behavior (ground_base_color, the
# unmodified vegetation_min_clumps/vegetation_cluster_count/landform_mid_
# chance export values, the unconditional foreground_band_texture pick),
# not an approximation of it.

var _region_gradient_value: float = 0.0
# This room's actual rolled wet/dry value - RoomState.region_progress
# plus this room's own +/-gradient_variance offset, clamped to [0, 1] -
# see the Region Gradient export group's own doc above for why this
# varies around region_progress rather than landing on it exactly. Rolled
# ONCE per room by _roll_region_gradient_value() below (called first
# thing in _ready()), then just READ by every consumer (ground tint,
# vegetation counts, landform chance, foreground band selection) - same
# "generated once, read many times" shape RoomState.region_progress
# itself already uses, kept local to this scene instance rather than
# staged on RoomState since (unlike region_progress) nothing outside this
# file ever needs it, and gradient_variance - the thing it's rolled
# against - is itself a field_room.gd export, not a RoomState field.

func _roll_region_gradient_value() -> void:
	_region_gradient_value = clampf(RoomState.region_progress + randf_range(-gradient_variance, gradient_variance), 0.0, 1.0)

# Vegetation/landform wet-dry ENDPOINTS - deliberately plain consts, not
# exports, unlike ground_color_wet/_dry or foreground_band_crossover
# above: this pass's own brief asks to "scale vegetation_min_clumps and
# the cluster count by the gradient value" and "raise landform_mid_chance
# toward the dry end," treating those three EXISTING exports as the
# tunable baseline an artist would already reach for, not asking for a
# second pair of wet/dry exports per field on top of them. Each range is
# centered on that field's own existing default (4, 3, 0.65) at gradient
# 0.5, so a room landing near the middle of the region reads close to
# today's flat behavior, with the spread doing the actual "sparse and
# flat at the wet end, dense and rising at the dry end" work outward from
# there. See _build_background_layers() below for where these interpolate
# in.
const VEGETATION_MIN_CLUMPS_WET := 2
const VEGETATION_MIN_CLUMPS_DRY := 6
const VEGETATION_CLUSTER_COUNT_WET := 2
const VEGETATION_CLUSTER_COUNT_DRY := 4
const LANDFORM_MID_CHANCE_WET := 0.40
const LANDFORM_MID_CHANCE_DRY := 0.90

@export_group("Opening room - empty skyline")
@export var opening_room_far_structure_count: int = 0
@export var opening_room_mid_structure_count: int = 0
# Overrides far_structure_count/mid_structure_count for the opening room
# ONLY (2026-08-27 - see _build_background_layers()'s own branch) - she
# stands near the left edge of a room whose mid/far structures live
# inside the motion_mirroring tile (background_tile_width above), not
# world space, so a structure can't be excluded from just her corner of
# the room by position - the whole tile either has them or doesn't (see
# this pass's own investigation report). Zero by default: an empty
# skyline behind her, no crane/gantry/platform/pipe competing with her
# for attention right where the player's first real choice in the game
# happens. Exported rather than hardcoded zeros specifically so this can
# be dialed back up without a code change if empty reads as unfinished
# once seen live - horizon_haze_height/alpha above are untouched by this
# (still atmosphere, not a structure) and stay exactly as populated
# either way.
#
# LEFT AT 0 (2026-08-30 landform pass) - far_structure_count/mid_
# structure_count now populate real landform (_add_far_landform()/_add_
# mid_landform()), not the industrial props ("crane/gantry/platform/
# pipe") this override's own doc still names, so these two zeros now
# also suppress landform in the opening room, not just Sunken Works
# structures. That's INHERITED behavior, not a re-decision made by this
# pass: the original choice was about not competing with her for
# attention, made before the region's re-theme from Sunken Works to the
# current coastal setting, and this pass didn't re-litigate whether an
# empty skyline is still the right call for a landform-populated far/mid
# layer - it just left the existing override in place.

@export_group("NPC Card Offer")
@export var npc_offer_card_scale: float = 0.55
# RAISED (2026-08-27, readability pass) - 0.35 (~121px tall) had correct
# proportions (see the pass right above this one) but read as too small
# for the name/description to be comfortably legible at rest. 0.55
# (~190px tall) targets "comfortably readable," at the cost of a
# tighter (but still clear - confirmed headlessly, ~24px) gap to her
# own sprite than 0.35 had (~49px) - a bigger card at the same position
# necessarily eats into that margin. Drives a plain uniform `scale` on
# `_npc_offer_card_wrapper`, applied OUTSIDE the card's own set_scale_
# factor(1.0) hand-card layout - see that var's own doc (still accurate)
# for why this lives on a wrapper rather than on `visual` or on set_
# scale_factor() itself.
@export var npc_offer_card_hover_multiplier: float = 1.65
# NEW (2026-08-27, readability pass) - card.gd's own SHARED hover_scale
# (1.1) still applies to `visual` on hover exactly as it does for every
# other Card instance (untouched - other callers depend on it), but
# 1.1 stacked on this wrapper's own 0.55 rest scale is only a 0.605
# effective scale, barely perceptible against a card already the
# player's full attention is on. This multiplier applies to the
# WRAPPER's own scale specifically while hovered (wrapper.scale =
# npc_offer_card_scale * this, see _on_npc_offer_card_hover_changed()),
# stacking with visual's own hover_scale rather than replacing it:
# 0.55 * 1.65 * 1.1 ≈ 0.998 - "roughly hand-card size," per this pass's
# own brief, without hardcoding 1.0 directly (this stays a genuine
# multiplier on the rest scale, so retuning npc_offer_card_scale keeps
# the hover target proportionally sensible instead of drifting toward
# a now-stale absolute number).
@export var npc_offer_card_x_offset: float = -150.0
# Where the card's own CENTER lands AT REST, as an X offset from the
# NPC's own Area2D origin. Negative moves the card toward LOWER world x
# - the water/shore side of this room (the coastal shoreline hugs low
# world x - see this room's own water-extent notes), and the side AWAY
# from the player's only approach direction (spawn/exit both sit at
# higher x than her). If a future NPC in a room where water/the far
# side sits at HIGHER x than her, flip the sign - the direction lives
# in this value, not hardcoded into the code that applies it (see _on_
# npc_offer_card_hover_changed()'s own use of signf() on this exact
# value, for the same reason).
@export var npc_offer_card_y_offset: float = -120.0
# Where the card's own CENTER lands, as a Y offset from the NPC's own
# Area2D origin (a Y offset from her feet, roughly - same local space
# CollisionShape2D/OfferLabel already use) - lands at her own measured
# mid-height (world Y 783, i.e. -117 from her Area2D origin at 900,
# rounded to -120), "roughly her hand height, so it reads as an object
# she's holding out" per this feature's own brief. A hand-eyeballed
# constant - expect to retune again if she's rescaled (visual_scale/
# Sprite.offset.y) further. Unaffected by the proportions fix above -
# see npc_offer_card_x_offset's own note on why the envelope is
# unchanged.
@export var npc_offer_card_delay_sec: float = 0.5
# How long after her world-voice text starts fading in the card waits
# before it starts its OWN fade-in - "the text fades in first, then the
# card fades in after a short beat," per this feature's own brief. The
# card's own fade-in/out DURATIONS deliberately reuse the NPC's own
# offer_fade_in_sec/offer_fade_out_sec (field_npc.gd) rather than a
# second pair of exports here - "reuse the existing fade timing
# approach," per the brief, taken literally: same numbers, so card and
# text read as one paced reveal instead of two independently-tuned
# fades that happen to overlap.
@export var npc_offer_card_accept_duration_sec: float = 0.5
# How long the "fly to the deck" acceptance animation takes (position,
# scale, and alpha all tweened together) - a one-off spend gesture, not
# a fade tied to her own offer_fade_in_sec/_out_sec above, so it gets
# its own tunable rather than borrowing theirs.

@export_group("Treasure Chest Card Offer")
@export var treasure_card_scale: float = 0.55
# Chest B's own sight-unseen card reveal (2026-08-29, three-chest
# treasure room) - matches npc_offer_card_scale's own value above (the
# established "comfortably readable" world-space card size), not
# independently retuned, since there's no reason the two should read at
# different sizes.
@export var treasure_card_offset: Vector2 = Vector2(0, -180)
# Where the card's own CENTER lands, as an offset from Chest B's own
# Area2D origin - same "offset from the anchor, not an absolute
# position" shape npc_offer_card_x_offset/_y_offset use for the Keeper.
@export var treasure_card_fade_in_sec: float = 0.4
# Deliberately its OWN function, not a third caller of _show_npc_offer_
# card() (see _on_chest_card_offered()'s own doc for why) - so this has
# its own fade timing rather than reusing offer_fade_in_sec, which lives
# on field_npc.gd and has no equivalent on a chest.

@export_group("Foreground occluders")
@export var foreground_occluders_enabled: bool = true
# ENABLED (2026-08-30 foreground-framing pass, was false) - Art
# Direction Bible §10/§5: foreground framing is the first layer in the
# side-scroller stack with its own visual responsibility (darkest
# values, strong silhouettes, limited internal information), not an
# optional extra evaluated separately from everything else. Still a
# SEPARATE ParallaxBackground (Foreground, positioned AFTER Player in
# the scene tree, not a child of the existing Background node - a
# ParallaxLayer's draw order is fixed by wherever its OWN
# ParallaxBackground sits in the tree, so there's no way to get "some
# Background children draw behind Player, one draws in front" out of a
# single ParallaxBackground) - that's what makes this draw in front of
# Player regardless of what Background's own children do.
#
# Mutated to false for TREASURE specifically (2026-08-31, treasure-
# overhang pass) when treasure_overhang_enabled is true - see _build_
# background_layers()'s own TREASURE branch. The GLOBAL default here
# stays true either way; only that one room type's own live value gets
# overridden per-load, same "mutate the shared export once, before
# anything reads it" pattern the opening-room branch just above it in
# that function already uses for far_structure_count/mid_structure_count.
@export var occluder_layer_motion_scale: float = 1.12
# Lowered from 1.4 (2026-08-30 foreground-framing pass) - 1.4 was picked
# for a prop hanging well above the play plane; at the proximity this
# pass places objects (cropped by the bottom edge, right in front of the
# player) that scale would streak the band past far faster than a mass
# this close should read. Still > 1.0 on purpose - this is what makes
# the layer scroll FASTER than the play plane (which moves at the
# camera's own 1:1 rate), the parallax cue for "closer than the camera,
# not farther" - every other layer in this room uses a scale < 1.0 for
# exactly the opposite reason - just a subtler push at this distance.
#
# Single-screen rooms (_is_single_screen_room() - COMBAT and, since
# 2026-08-31, TREASURE) get ZERO parallax on EVERY layer here, not just
# this one - camera.limit_left/limit_right span exactly one viewport
# width in those rooms (see _position_room_bounds()), so the camera's
# rendered center never moves and every ParallaxLayer's scroll offset
# stays permanently zero regardless of its own motion_scale. That's a
# known, existing property of those room types, not something this pass
# introduces or should try to work around - the motion cue is simply
# absent there by design, and should NOT be compensated for (e.g. by
# faking motion some other way just for that room type); the band still
# reads correctly as a static foreground silhouette there, just without
# the scroll cue standard rooms get.
@export var occluder_color: Color = Color(0.2117647, 0.1882353, 0.1607843, 0.92)
# RGB RETUNED (2026-08-31, battle-backdrop-match pass) - #363029
# (luminance 0.192), sampled from the battle plate's own foreground band,
# which carries a warm brown cast the field's old near-black (0.118,
# closer to neutral) didn't. Alpha (0.92) UNCHANGED - still near-opaque,
# this pass only moves the RGB toward that warm cast. treasure_overhang_
# color (below) reads this export's OWN default directly (`= occluder_
# color`, a per-instance construction-time copy - see its own doc), so
# it picks up this new value automatically; nothing there needed a
# separate edit.
#
# Deliberately near-black, near-opaque - unlike every background color
# below, this is EXEMPT from _validate_background_contrast()'s floors:
# an occluder is foreground framing, not background, and Art Direction
# Bible §5 assigns framing the darkest values in the frame - the exact
# opposite requirement from the pale-plane/pale-detail floors that rule
# enforces on everything actually behind the play plane. Supplied to the
# band as _apply_vertical_shade()'s base_color (see _populate_occluder_
# layer() below), which feeds it into silhouette_vertical_shade.gdshader's
# top_color/bottom_color - NOT a per-instance Polygon2D.color.
#
# REQUIRES a WHITE mask asset to have any visible effect at all (2026-08-31
# white-mask pass) - foreground_band_texture/_coastal below used to be pure
# black on transparent, which forced the rendered RGB to (0,0,0) regardless
# of this color's own RGB (or, later, the shader's gradient): black
# multiplied by anything is still black, so this color's RGB - and the
# entire vertical-shading gradient - had zero visible effect; only the
# alpha (0.92) ever did anything, same limitation the vegetation clump
# assets already established (see vegetation_clump_textures's own doc) and
# landform_far_texture/landform_mid_textures already avoid by being white.
# Both foreground band assets are white masks now specifically so this
# color's RGB - and the shader's gradient built from it - actually renders,
# rather than being silently clamped to black no matter what's configured
# here.
@export var foreground_band_texture: Texture2D
# assets/regions/beach/foreground_band.png (2172x294, pure WHITE on
# transparent, horizontally seamless - REPLACES a pure-black version of
# the identical asset, 2026-08-31 white-mask pass, same dimensions/alpha,
# only the RGB channel changed - see occluder_color's own doc for why a
# tintable mask has to be white, not black) - assigned in the scene, not
# hardcoded as a preload here, matching how ground_texture already does
# this for the floor. Used for every room EXCEPT the opening room (see
# foreground_band_texture_coastal below) - _populate_occluder_layer()
# no-ops if whichever of the two applies is unset (see its own doc).
@export var foreground_band_texture_coastal: Texture2D
# assets/regions/beach/foreground_band_coastal.png - same 2172x294, pure
# WHITE on transparent (2026-08-31 white-mask pass, same as foreground_
# band_texture above), interchangeable slot as foreground_band_texture,
# different art (a wrack line rather than grass). Selected by the SAME
# condition _apply_coastal_opening_room_layout() already uses (RunState.
# current_node == RunState.opening_node) - see _populate_occluder_layer()
# below. Runs the FULL tile width with no shore-line bound, unlike the
# coastal ground decoration functions (_add_coastal_seam_debris() etc.,
# which start at _coastal_shore_x()) - a wrack line sitting in front of
# the water's edge, past the shore, is correct here, not an oversight to
# fix.
@export var foreground_band_height: float = 260.0
# On-screen height in pixels - the asset scales UNIFORMLY to this (see
# _populate_occluder_layer()'s own scale_factor), preserving its native
# 2172:294 aspect ratio rather than stretching it, so the tile's own
# horizontal repeat period scales along with its height instead of
# distorting.
@export var foreground_band_overshoot: float = 40.0
# How far below the VISIBLE bottom edge the band's own bottom edge sits -
# same "anchor below the crop line, not at it" reasoning the procedural
# occluders this replaces already used for occluder_base_overshoot,
# applied to one continuous strip instead of many small shapes.
#
# REMOVED this pass (2026-08-30, generated-asset pass): occluder_count,
# occluder_band_height, occluder_height_variation, occluder_growth_
# fraction, occluder_alpha_variation - all governed per-instance
# procedural shape generation that no longer runs here, per this pass's
# own brief: at foreground scale (~200px+) those shapes read as
# geometric spikes and slabs, not organic masses; a generated texture
# replaces them entirely rather than being tuned further. (At the time,
# vegetation still used its own procedural shape too - a later pass, the
# same day, replaced that with textured clumps and deleted the function;
# _irregular_blob_shape() remains in use for ground patches/seam debris.)
@export var foreground_band_far_enabled: bool = true
# A second instance of the SAME band texture (see foreground_band_
# texture/_coastal's own doc - no new assets), placed further back and
# shorter, so the layer reads as depth rather than one flat strip
# uniformly hugging the bottom edge (this pass's own brief). Left
# completely unpopulated when disabled, not just hidden - same
# convention foreground_occluders_enabled already uses.
@export var foreground_band_far_height: float = 180.0
# Shorter than the near band's own foreground_band_height (260) - a
# smaller silhouette is the size cue for "further back," reinforcing the
# slower motion_scale and paler tint below rather than standing alone.
@export var foreground_band_far_overshoot: float = 40.0
# Same meaning as foreground_band_overshoot, independent value - how far
# below the visible bottom edge THIS instance's own bottom edge sits.
@export var foreground_band_far_motion_scale: float = 1.04
# Slower than the near band's own occluder_layer_motion_scale (1.12) but
# still > 1.0 - both bands read as closer than the play plane, the far
# one just less aggressively so, the same relative-speed depth cue
# far_layer_motion_scale/mid_layer_motion_scale already use for the
# background stack (there, slower = farther; here, slower = LESS close,
# same underlying "speed encodes distance from camera" principle applied
# on the near side of 1.0 instead of the far side).
@export var foreground_band_far_offset_x: float = 700.0
# Shifts where this instance's own tile content starts, so its
# silhouette doesn't line up 1:1 with the near band's identical texture -
# see _populate_occluder_layer()'s own doc for why an offset alone is
# sufficient (texture_repeat/motion_mirroring already guarantee no seam
# regardless of where the tile "starts").
@export_range(0.0, 1.0, 0.01) var foreground_band_far_fade: float = 0.3
# How far the far band's own tint lerps from occluder_color toward sky_
# gradient_horizon_color (see _build_background_layers()'s own occluder
# block for the exact call) - Bible §4: "distance removes contrast," so
# the further-back instance reads paler/lower-contrast, not just
# smaller and slower. Alpha is preserved from occluder_color's own
# (reset after the lerp - the same correction _depth_tinted_color()
# already makes for ground decoration, so this only shifts hue/value,
# never transparency). Subtle by default - this is a depth cue, not a
# second, competing color.

@export_group("Painted preview (TEMPORARY)")
@export var painted_preview_enabled: bool = true
# THROWAWAY preview toggle (2026-09-05) - lets us see the three painted
# plates (background_plate/ground_strip/foreground_band_tileable.png,
# under assets/regions/beach/PaintedBackgrounds/) in motion without touching or
# removing any procedural layer. False reproduces today's room exactly -
# _apply_painted_preview() below is the ONLY thing this flag gates, called
# once at the very end of _build_background_layers() so nothing existing
# needs restructuring. Not meant to survive as a real feature: no other
# code in this file should ever branch on this export.
@export var painted_preview_bg_canvas_layer: int = -101
# MUST stay below Background's own runtime layer of -100 (2026-09-06,
# CanvasLayer-ordering fix - ROOT CAUSE of the whole mid-layer/Background
# investigation this session: bg_layer used to be hardcoded to -99, ABOVE
# Background's -100, so the opaque, full-height painted plate covered the
# entire Background stack - FarLayer, MidLayer, both particulate layers,
# and PaintedMidLayer - regardless of what any of them held or how
# visible they were). Background itself has no layer= in field_room.tscn
# and no script anywhere in this project ever assigns a CanvasLayer's
# .layer (confirmed by project-wide search - the ONLY `.layer =`
# assignment anywhere is this export feeding bg_layer, right below) -
# so -100 is whatever an unconfigured ParallaxBackground/CanvasLayer
# resolves to at runtime, not a value anything here could change; -101
# only needs to stay one step below THAT. Kept as a real export instead
# of a hardcoded -101 so the relationship stays visible and retunable
# from the Inspector rather than a second magic number to keep in sync
# by hand.
@export_range(0.0, 1.0, 0.001) var painted_preview_bg_horizon_fraction: float = 0.685
# Where the painted plate's own horizon sits, as a fraction of the
# plate's height from its top edge. NO LONGER used to POSITION the plate
# (2026-09-05, letterboxing fix) - the plate's position is now pinned to
# fill the frame edge to edge (see _apply_painted_preview()'s own doc for
# why that and horizon-position-solving couldn't both control position at
# once). This fraction still decides where the horizon actually LANDS on
# screen, though: with position pinned, that screen Y is exactly
# `viewport_size.y * this fraction` (the plate's own native size cancels
# out). Set this to `RoomState.floor_line_y / viewport_size.y` to land the
# horizon exactly on the walk line with zero remaining gap - the current
# 0.685 default was tuned under the OLD position-solving math and almost
# certainly does not equal that ratio for this room; nudge by eye (or to
# that exact computed value) from the Inspector.
@export var painted_preview_ground_modulate: Color = Color.WHITE
# A clean tuning knob now (2026-09-06, ground-tint fix) - REPLACES its
# old role compensating for _apply_floor_depth_tint()'s leftover
# vertex_colors gradient, which _apply_painted_preview() now clears
# outright (along with resetting floor_polygon.color, for the opening
# room's own flat OPENING_ROOM_SAND_COLOR) rather than asking this
# export to multiply it away. WHITE means the painted ground_strip
# renders exactly as authored; nudge this only for a deliberate creative
# tint, not to correct an inherited one.
@export var painted_preview_fg_y_offset: float = 270.0
# Vertical nudge (px) for the painted foreground band, on top of the same
# camera-derived visible-bottom anchor _populate_occluder_layer() already
# uses for the procedural band it replaces here. Raised from 0.0 to 130.0
# (2026-09-06, Track A foreground-mass pass) to sink the base band's own
# top edge back down - see this pass's own investigation report on why
# the base band was covering too much of the frame at a wider RoomState.
# field_zoom, into the ground strip. The mass pieces below are placed
# relative to this same shifted band, not independently of it.
@export var painted_preview_fg_color: Color = Color8(45, 50, 59)
# The one color source for the foreground band AND the mass pieces
# (2026-09-06, band-flatten pass - REPLACES the band's own baked-in paint
# and the masses' own separate Color8(45, 50, 59) literal): foreground_
# band_tileable.png is now a white mask, keyed the same way fg_mass_
# wrack_mound_a.png/fg_mass_driftwood_a.png/fg_mass_grass_a.png already
# are, so retuning this one export recolors the base band and every piece
# planted on it together instead of them drifting apart as independent
# numbers. See _add_vegetation_clump()'s own doc for why this is still a
# SEPARATE export from vegetation_color, not a shared one - the two
# families must be tintable independently.

@export var painted_preview_fg_mass_per_screen: float = 1.5
# How many discrete foreground-mass pieces (wrack mound/driftwood/grass -
# loaded in _apply_painted_preview() below) to place per 1920px of
# RoomState.room_width(), i.e. per one old-viewport-width's worth of room
# (2026-09-06, Track A foreground-mass pass). A density, not a literal
# count, so a
# wider room at a lower field_zoom gets proportionally more pieces rather
# than the same fixed handful stretched thin.
@export var painted_preview_fg_mass_scale_min: float = 0.22
@export var painted_preview_fg_mass_scale_max: float = 0.32
# Uniform scale range applied to both axes of a picked piece - these
# source masks are large (hundreds of px tall even after their own crop),
# authored for slicing down to a foreground-scale piece, not to render at
# native size.
@export var painted_preview_fg_mass_overlap_px: float = 40.0
# How far a piece's own base sinks below the base band's solid body top
# (see band_body_top's own doc at its use site below) - a piece planted
# exactly AT the band's own top edge would look like it's floating just
# above the mass rather than growing out of it; sinking it down by this
# much lets it visually root into the band instead.
@export var painted_preview_fg_mass_min_gap_px: float = 600.0
# Minimum distance between two pieces' own centers - purely a horizontal
# spacing floor (world-space px), not a true bounding-box overlap check,
# same simplification the mid-plate loop's own gap check makes.

@export var painted_preview_bloom_enabled: bool = true
# A second, independent gate INSIDE painted_preview_enabled's own (see
# that export's own doc for why this whole path only exists at all when
# it's true) - lets the bloom specifically be toggled off while still
# checking the rest of the painted preview, without deleting/re-adding
# code. See _apply_painted_preview()'s own bloom section.
@export var painted_preview_bloom_strength: float = 0.35
# Modulate ALPHA only - painted_preview_bloom_color below carries the
# RGB. _apply_painted_preview() renders the bloom with ADDITIVE
# compositing (CanvasItemMaterial.BLEND_MODE_ADD, hardcoded, not a
# separate toggle export - see that function's own bloom section) - flag
# from this pass's own report: additive strength and plain-alpha strength
# are NOT the same visual weight for the same number (additive keeps
# ADDING light a plain-alpha blend would instead just fade toward), so
# 0.35 is tuned for additive specifically. If this is ever switched to
# plain alpha blending, this value will likely need RAISING to read at a
# comparable brightness, not just left as-is.
@export var painted_preview_bloom_scale: float = 0.62
# Fraction of the VIEWPORT'S OWN width (not the texture's native 1024px,
# and not a fixed pixel size) - the bloom's rendered width is always
# viewport_size.x * this, uniformly scaled on both axes (the source
# texture is square, so a uniform scale keeps it circular rather than
# stretching it into an ellipse). Holds correct if the viewport size
# ever changes, per this pass's own brief.
@export var painted_preview_bloom_pos: Vector2 = Vector2(0.30, 0.02)
# Top-left position as a FRACTION of viewport size (x of width, y of
# height), not pixels - actual position is Vector2(viewport_size.x *
# this.x, viewport_size.y * this.y). Same "fraction, not pixels" reason
# as painted_preview_bloom_scale above: holds correct across viewport
# sizes without retuning.
@export var painted_preview_bloom_color: Color = Color(0.988, 0.992, 1.0)
# Cool near-white, deliberately - a hair of blue lean (B slightly above
# R/G), never warm. This pass's own brief is explicit that ANY warm
# (golden/orange/amber) read here is a defect, not a style choice to
# revisit - if this ever needs retuning, stay on this exact side of
# neutral, cooler if anything, never warmer.

@export var painted_preview_cloud_enabled: bool = true
# Re-enables JUST _add_clouds()'s own sprites over the painted plate
# (2026-09-05, cloud-reenable pass) - the master gate for the whole
# section below in _apply_painted_preview(). Everything ELSE FarLayer
# holds (landform, recession bands, horizon haze) stays hidden - see
# _painted_preview_cloud_nodes' own doc for how clouds specifically are
# pulled out and re-shown without touching any of that.
@export var painted_preview_cloud_alpha: float = 0.20
# REPLACES each cloud's own randomly-rolled cloud_alpha_min/_max (0.30-
# 0.60) with one fixed, lower value once reparented for preview - paler
# than the procedural default on top of cloud_color/painted_preview_
# cloud_tint already being light, per this pass's own brief ("paler than
# the plate's painted clouds, not darker").
@export var painted_preview_cloud_motion_scale: float = 0.04
# NOT CURRENTLY WIRED TO ANYTHING (2026-09-05, cloud-reenable pass) -
# flagging honestly rather than pretending this does something. Real
# ParallaxLayer.motion_scale only applies to a node whose DIRECT parent
# is a ParallaxBackground; the draw-order requirement (between the plate
# and the bloom, both siblings on bg_layer - a plain CanvasLayer, not a
# ParallaxBackground) put those two requirements in genuine conflict -
# reported before implementing, per this pass's own instructions, and
# resolved (by explicit direction) in favor of draw order: clouds are
# reparented onto bg_layer itself and keep their own independent drift-
# speed animation (cloud_drift_speed_min/_max, unrelated to motion_scale),
# but get no camera-tied parallax movement at all. This export is left
# declared, at the requested default, in case a future pass revisits the
# tradeoff differently (e.g. accepting clouds drawing above the bloom
# instead, which WOULD let this be real) - it is not read anywhere today.
@export var painted_preview_cloud_tint: Color = Color(1.0, 1.0, 1.0)
# Multiplies with painted_preview_cloud_alpha above to form each
# reparented cloud's modulate - plain white by default, on top of an
# already-pale cloud_textures asset set and cloud_color (0.92, 0.93,
# 0.94 - already light, not dark, so nothing here is correcting a dark
# existing color, just adding the preview's own explicit paleness on top).

@export var painted_preview_mid_enabled: bool = true
# Master gate for the whole mid-distance parallax section in
# _apply_painted_preview() (2026-09-05, mid-layer pass) - checked
# alongside painted_preview_enabled itself; with either off, none of
# this section's nodes get created at all.
@export var painted_preview_mid_opening_room_hulls_enabled: bool = true
# RENAMED from painted_preview_mid_skip_opening_room (2026-09-06,
# opening-room hull pass). That name and its old behavior ("skip the
# whole layer for the opening room") stopped fitting once the opening
# room got real content of its own here - the dune/bank/grass plates
# still place LAND seaward of the shoreline, still wrong there
# specifically since that room's whole left side is ocean (see
# _apply_coastal_opening_room_layout()), so they're still never shown in
# the opening room - but instead of leaving painted_mid_layer empty, the
# opening-room branch below now swaps in an authored line of boat hulls.
# This flag gates ONLY that swap-in content, not the layer itself:
# painted_mid_layer.visible is never forced false for the opening room
# any more (see the unconditional assignment above this function).
# Checked via RunState.current_node == RunState.opening_node, the same
# room-identity check this file already uses everywhere else it needs to
# single out this one room (_build_background_layers()'s own far/mid
# structure-count override, _floor_span_left_x()/_floor_span_right_x(),
# _add_seam_vegetation()'s coastal branch, etc.) - not a new kind of
# check.
@export var painted_preview_mid_motion_scale: float = 0.35
# Real ParallaxLayer.motion_scale, unlike painted_preview_cloud_motion_
# scale above (which stayed inert) - this layer has no fixed-sibling
# draw-order constraint forcing it onto a plain CanvasLayer, so it gets
# to be an ordinary child of Background and inherit true camera-tied
# parallax. Between far_layer_motion_scale and mid_layer_motion_scale's
# own likely range - see this pass's own report for what was measured.
@export var painted_preview_mid_modulate: Color = Color(0.92, 0.93, 0.95)
# Slightly darkened so the mid mass separates from the ground strip
# rather than blending into it - shared by all three plates alike.
@export var painted_preview_mid_plates_enabled: bool = false
# Master gate for mid_plate_specs specifically (2026-09-08, mid-plate
# retirement pass) - distinct from painted_preview_mid_enabled above,
# which still gates the WHOLE mid-distance section (the motion_scale/
# motion_mirroring setup, the child-clearing loop, and the opening
# room's own hull swap-in below, none of which this flag touches). This
# one wraps ONLY the dune/bank/grass loop in the else branch below.
# Defaults FALSE: all three plates (mid_dune_mass.png/mid_bank_long.png/
# mid_grass_clumps.png) are the weakest art in the game - pale, low-
# contrast masses doing very little work at the horizon, worse still at
# field_zoom - and are being retired pending real replacement art, not
# redesigned here. mid_plate_specs itself, every per-plate export above,
# the retry/gap-check placement machinery, and the opening-room branch
# are all left fully intact below - flipping this back to true is the
# entire re-enable path, nothing else to touch. painted_mid_layer has no
# children in any non-opening room while this is false; the opening room
# is unaffected either way, since its hull swap-in is a separate branch
# this flag does not gate (see painted_preview_mid_opening_room_hulls_
# enabled's own doc).
@export var painted_preview_mid_dune_height_frac: float = 0.14
@export var painted_preview_mid_bank_height_frac: float = 0.10
@export var painted_preview_mid_grass_height_frac: float = 0.065
# Each plate's rendered height is viewport_size.y * its own _height_frac
# (aspect ratio preserved from there, never a hardcoded pixel size),
# further scaled by painted_preview_mid_scale_jitter below. Horizontal
# position no longer has a per-plate _x_frac export (2026-09-06,
# per-room variation pass - REMOVED painted_preview_mid_dune_x_frac/
# _bank_x_frac/_grass_x_frac rather than leaving them as dead, unused
# knobs): every room placed the same three plates at the same three
# fixed fractions, butting into one continuous ridge regardless of room
# - see painted_preview_mid_x_min_frac/_max_frac below for the seeded
# range that replaces them.
@export var painted_preview_mid_spawn_chance: float = 0.55
# Per-plate presence roll (2026-09-06, per-room variation pass) - each of
# the three plates independently may or may not appear in a given room.
# Some rooms end up with one plate, some with none - Region 1's own
# spatial rule (open, horizontal, nothing closing the frame off) and its
# subject (emptiness) mean a mostly-empty mid layer is the intended
# common case, not a bug to fix later.
@export var painted_preview_mid_x_min_frac: float = -0.25
@export var painted_preview_mid_x_max_frac: float = 1.10
# Seeded per-plate horizontal placement range, as a fraction of viewport
# width - REPLACES the old fixed per-plate x-fraction exports. Extends
# past [0, 1] on both ends (a plate's LEFT edge, not its center, is what
# viewport_size.x * this fraction lands on - see this section's own
# code) so plates can partially bleed off either edge, the same license
# the old fixed fractions already took (dune's own -0.10 always start
# partly off the left edge).
@export var painted_preview_mid_scale_jitter: float = 0.35
# Each plate's height_frac is multiplied by a seeded factor in
# [1.0 - jitter, 1.0 + jitter] (2026-09-06, per-room variation pass) -
# internal depth cue within the mid distance itself (nearer-reading
# plates larger, farther-reading ones smaller) rather than one flat
# plane every room repeats identically.
@export var painted_preview_mid_min_gap_frac: float = 0.30
# Minimum horizontal gap enforced between any two placed plates' own
# rendered edges (2026-09-06, per-room variation pass), as a fraction of
# viewport width - what actually prevents plates from butting into a
# continuous ridge now that position is randomized rather than fixed.
# See this section's own code for the retry-then-drop resampling shape.
@export var painted_preview_mid_y_offset: float = 0.0
# Shared by all three plates (not one export per plate) - matches this
# pass's own final @export list exactly; nudges each plate's bottom edge
# away from its RoomState.floor_line_y anchor by the same amount.
# CHANGED 10.0 -> 0.0 (2026-09-05, confirmed-defect fix) - at 10.0 every
# plate's bottom edge landed 10px PAST floor_line_y, into Floor polygon's
# own rect ([floor_line_y, room_height] - see _position_floor()), which
# draws in front of Background (this pass's own investigation: Floor is
# a later sibling of Background at the same implicit CanvasLayer 0, so it
# draws on top of anything Background holds where they overlap). Wrong
# regardless of the separate mid-layer visibility question. Still read by
# the opening room's own hull branch below too, on TOP of each hull's own
# _y_offset export - see those exports' own doc - not superseded by it.

# --- Opening-room boat hulls (2026-09-06, opening-room hull pass): the
# opening room's own swap-in for the dune/bank/grass plates above, which
# never appear there (see painted_preview_mid_opening_room_hulls_
# enabled's own doc). One export triple per hull - height_frac/x_frac/
# y_offset - rather than a shared range and a seeded roll, because this
# is a SINGLE authored composition (one specific room, not "some room
# along the way"), so there's no reason to hide the actual numbers
# behind randomness the way mid_plate_specs' shared exports do for every
# OTHER room. x_frac is a fraction of viewport width, same convention as
# painted_preview_mid_x_min_frac/_max_frac above (a plate's LEFT edge,
# not its center) - hand-constrained here to the landward (right) side
# of this room's fixed shoreline, since a random draw across the full
# [x_min_frac, x_max_frac] range used elsewhere could just as easily
# park a hull in the ocean. See OPENING_ROOM_OCEAN_DEPTH's own doc: the
# water reaches ~400 world units in from the left wall, ~0.2 of this
# project's 1920px viewport width.
@export var painted_preview_mid_hull_a_height_frac: float = 0.055
@export var painted_preview_mid_hull_a_x_frac: float = 0.36
@export var painted_preview_mid_hull_a_y_offset: float = -28.0
@export var painted_preview_mid_hull_b_height_frac: float = 0.100
@export var painted_preview_mid_hull_b_x_frac: float = 0.81
@export var painted_preview_mid_hull_b_y_offset: float = -2.0
@export var painted_preview_mid_hull_c_height_frac: float = 0.115
@export var painted_preview_mid_hull_c_x_frac: float = 0.58
@export var painted_preview_mid_hull_c_y_offset: float = 6.0
@export var painted_preview_mid_hull_a_modulate: Color = Color.WHITE
@export var painted_preview_mid_hull_b_modulate: Color = Color.WHITE
@export var painted_preview_mid_hull_c_modulate: Color = Color.WHITE
# Per-hull color knob (2026-09-06, hull-color-tuning pass) - MULTIPLIES
# on top of the shared painted_preview_mid_modulate every mid-layer plate
# already gets (see that export's own doc), not a replacement for it -
# white here is the identity multiplier, so leaving these at their
# default changes nothing about how the hulls render today. Exists
# because these three PNGs are Track B painted plates with color baked
# directly into the art: this can only ever darken/tint via multiply, it
# cannot cool an already-warm bake without also darkening it - the cheap
# knob to reach for first, before regenerating the plates themselves.
# RETUNED TWICE since the first cut (2026-09-06, opening-room hull
# tuning passes 1 and 2) - see this section's own history for what each
# pass actually changed. height_frac and y_offset are pass-1 values,
# confirmed correct in a live in-editor check (left-to-right screen order
# is a, c, b - NOT the order this file's own comments originally
# assumed - hull_a reads clearly smallest/furthest, hull_c/hull_b read
# larger and close in size to each other; all three meet the ground with
# visibly different, non-zero clip depths) - CORRECTION to an earlier
# version of this doc, which claimed hull_a's -28 left it entirely
# unclipped: the live check confirms it still meets the ground, just
# with visibly less clip than hull_c/hull_b - "least clipped," not
# "clipped not at all."
#
# x_frac is pass-2's own retune, from that same live check's report of
# three remaining problems: hull_c/hull_b were overlapping (0.02 of
# viewport width apart against several-hundred-px rendered widths reads
# as touching, not paired), hull_b's own right edge ran past the visible
# frame, and the whole group sat far enough right to leave a long empty
# walk from spawn to hull_a. All three x_fracs shifted left as a group
# (hull_a 0.536 -> 0.36) to shorten that walk while keeping hull_a's own
# left edge comfortably above 0.30 - the exact x_frac confirmed BY A
# SEPARATE live check to put hull_a directly on the player's spawn x
# (world x=140 in field_room.tscn). hull_c (0.58) and hull_b (0.81) then
# reopen a real, larger gap between themselves than the broken 0.02 (now
# ~0.034 of viewport width) while keeping a bigger gap still between
# hull_a and hull_c (~0.058) so the two-plus-one grouping stays legible,
# and hull_b's own right edge (0.81 + its own ~0.174 rendered width ~=
# 0.984) now lands inside the frame instead of past it. This whole
# layout trades against a tight budget - three rendered widths alone
# sum to roughly half the viewport - so the margins here are real but not
# large; if the next live check finds any of these three fixes only
# partially landed, that budget is why, not a mistake in this doc.
#
# Landed on explicit instruction to commit rather than a live re-check
# confirming pass 2's own x_frac numbers specifically (pass 1's height_
# frac/y_offset values above WERE live-confirmed - see this doc's own
# opening paragraph). If a later live look finds any of the three x_frac
# fixes under- or over-shot, that's what to revisit first.

# --- Opening-room hull line (2026-09-06, positional world-voice pass): a
# single line about the boat hulls AS A GROUP, fired once by the player's
# world x crossing a threshold - deliberately NOT attached to any one
# hull's own Area2D/contact zone, since a world-space trigger cannot stay
# aligned with a sprite parallaxing at painted_mid_layer's own motion_
# scale 0.35 (see this project's own investigation into exactly that,
# which is also why the middle hull's brief move to gameplay-plane depth
# was reverted rather than extended to all three - the group stays
# parallaxed, so nothing here can be contact-based). A threshold on the
# PLAYER's own world x sidesteps that entirely - player.position is real
# world-space with no parallax involved, same space _process()'s existing
# exit_haze proximity check below already reads it in.
@export var opening_room_hull_line_threshold_x: float = 1400.0
# Roughly this room's own midpoint - RoomState.standard_room_width (2800
# default) / 2, the width the opening room actually uses (see RoomState.
# room_width()'s own doc: it's excluded from the single-screen COMBAT
# default, so it's the wide standard width, not the viewport-matched
# combat one). Not derived from RoomState.room_width() directly - export
# defaults are static, and this is exactly the kind of "eyeball and
# retune by feel" number this file's other opening-room exports already
# are (floor_line_y, opening_room_player_spawn_x).
@export var opening_room_hull_line_text: String = "Pulled up above the tide. Never put back."
@export var opening_room_hull_line_font_size: int = 24
# Matches field_npc.gd's own offer_font_size exactly - same world-voice
# register, same visual weight against this project's established Deck/
# Map HUD text (see that export's own doc for the full reasoning: world-
# voice text reading smaller than the system-voice UI around it inverts
# this project's established register hierarchy).
@export var opening_room_hull_line_screen_y_fraction: float = 0.15
# Screen-space Y, as a fraction of viewport height - fixed regardless of
# player/camera position (this line is an observation about the group of
# boats, not something following the player or pinned to one hull - see
# this section's own header). 0.15 sits in the pale sky band above the
# hulls/ground clutter (which read at floor_line_y, well below this),
# clear of Deck/Map's own top-anchored HUD icons.
@export var opening_room_hull_line_fade_in_sec: float = 0.2
@export var opening_room_hull_line_hold_sec: float = 3.0
@export var opening_room_hull_line_fade_out_sec: float = 1.1
# Same fade-in/hold/fade-out shape as field_heap.gd's own outcome_display_
# sec and every "heap-shape" prompt's own fade timing, but NOT proximity-
# driven the way those are (body_exited fades them) - this line has no
# exit event to fade on, since it isn't tied to a contact zone at all
# (see this section's own header). Runs on a plain timer instead once
# triggered - see _play_opening_room_hull_line() below.

const OPENING_ROOM_HULL_LINE_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")
# Same world-voice serif field_npc.gd/field_heap.gd/field_chest.gd's own
# OFFER_FONT already uses - this line is world content (an observation
# about the boats), not a system-voice HUD readout, so it gets the same
# treatment: this exact font, HudPalette.WORLD_TEXT, OverlayStyle's light
# outline - see _setup_opening_room_hull_line() below for where all three
# actually apply.

var _opening_room_hull_line_label: Label = null
# Null for every room except the opening one (see _setup_opening_room_
# hull_line()'s own early-return) - _update_opening_room_hull_line()'s
# own null check is what makes its per-frame call from _process() a cheap
# no-op everywhere else, without needing to re-check RunState.current_
# node == RunState.opening_node on every single frame.

var _opening_room_hull_line_tween: Tween = null
# Tracks the single fade-in/hold/fade-out Tween _play_opening_room_hull_
# line() below builds (2026-09-06, map-overlay fix) - null whenever no
# fade is in flight. The one handle _clear_opening_room_hull_line() needs
# to kill an in-progress fade outright, rather than letting it keep
# running (and re-appearing) behind whatever just opened over it. Same
# "null means unaffected" idiom _opening_room_hull_line_label above and
# _offer_tween-shaped vars elsewhere in this project already use.

var _ground_line_decoration_nodes: Array[Node] = []
# Every sprite _populate_ground_line_decoration() below has created THIS
# room load, appended by that function itself - the same "content_root
# already holds real interactive content, so it can't be blanket-cleared;
# track exactly what we added instead" idiom _painted_preview_decoration_
# nodes (just below) uses, needed here for the same reason: this function
# must be safely re-callable (see its own doc) without stacking a second
# copy of every mask on top of the first.

var _painted_preview_decoration_nodes: Array[Node] = []
# Every node _add_floor_decoration()/_add_wavy_band()/_add_vegetation_
# clump() have ever created THIS room load, appended by those three
# functions themselves (2026-09-05, painted-preview visibility fix) -
# _apply_painted_preview() hides everything in this list at the end of
# the room build. A tracked LIST, not a container node these three
# helpers get reparented under, on purpose: none of them get a dedicated
# parent of their own today - _add_floor_decoration() always targets
# content_root, and _add_wavy_band()'s default (when no explicit parent
# is passed) is ALSO content_root - the same node real, clickable content
# (chests, NPCs, structures, the heap/curio/forge) lives in, so content_
# root itself can never be hidden wholesale without taking working
# gameplay content down with it. Tracking exactly what these three
# helpers built, regardless of which parent a given call happened to pass
# them, reaches every current caller (mid/far-layer landform vegetation,
# recession bands, horizon edge, standard ground patches/cracks/seam
# debris, every coastal-only decoration) and any future one, without
# needing this list updated by hand each time a new caller is added.
# Harmless to double-hide a node whose PARENT is already invisible
# (background_mid/background_far's own children, already hidden via
# their own layer's visible=false above) - setting visible=false on an
# already-non-rendering node is a no-op.

var _painted_preview_cloud_nodes: Array[Sprite2D] = []
# Every cloud Sprite2D _add_clouds() has ever created THIS room load,
# appended by that function itself (2026-09-05, cloud-reenable pass) -
# UNLIKE _painted_preview_decoration_nodes above, these are not simply
# hidden: _apply_painted_preview() REPARENTS each one out of background_
# far (which stays hidden wholesale, taking landform/recession-bands/haze
# down with it) and onto bg_layer, the same CanvasLayer the painted plate
# and bloom live on, as siblings positioned between the two - see that
# function's own cloud section for the full reasoning, including why real
# ParallaxLayer.motion_scale had to be given up for this (painted_preview_
# cloud_motion_scale's own doc).

var _painted_preview_cloud_drift_state: Array[Dictionary] = []
# The preview's OWN drift-state list, separate from _cloud_drift_state
# above - reparented clouds live in viewport-space now (bg_layer has no
# parallax transform), while _cloud_drift_state/_update_cloud_drift()'s
# own wrap bounds (_cloud_drift_range_min/_max) are sized for the
# ORIGINAL tile-space FarLayer lived in. Reusing that single global,
# shared mechanism for a different coordinate space would either wrap
# preview clouds somewhere nonsensical or require changing _update_cloud_
# drift() itself, regressing every non-preview room's own cloud drift for
# a throwaway feature. A small, separate {"sprite", "speed"} list plus
# its own _update_painted_preview_cloud_drift() (below) keeps the two
# completely independent instead - same shape, own bounds, zero shared
# state. Empty (a no-op) whenever no room has ever populated it, same
# "harmless when nothing's registered" pattern _update_cloud_drift()
# itself already establishes.
var _painted_preview_cloud_drift_min: float = 0.0
var _painted_preview_cloud_drift_max: float = 0.0

@export_group("Treasure overhang")
@export var treasure_overhang_enabled: bool = true
@export var treasure_overhang_texture: Texture2D
# assets/regions/beach/overhang_mask_r1.png (2026-09-01, textured-overhang
# pass - REPLACES the procedural _irregular_blob_shape() mass this group
# used to scale/tint at runtime) - 1672x941, white-on-transparent, opaque
# content roughly x 430-1671 / y 16-448 (confirmed directly against the
# file - see this pass's own investigation). Right-anchored and tapering
# to a blunt free end on the left, running off the texture's own right
# edge by design - assigned in the scene, not preloaded here, matching
# how foreground_band_texture/ground_texture already do this.
@export var treasure_overhang_content_uv_top: float = 16.0 / 941.0
@export var treasure_overhang_content_uv_bottom: float = 448.0 / 941.0
# Where treasure_overhang_texture's own opaque silhouette sits within its
# full UV.y span (2026-09-01, overhang-contrast pass) - measured directly
# against the file (1672x941, opaque content y 16-448) and must be
# updated by hand if the asset is ever regenerated at different bounds.
# Fed straight into _apply_vertical_shade()'s content_uv_top/_bottom
# below, which forwards them to silhouette_vertical_shade's own uniforms
# of the same name - see that shader's doc for why: without this, the
# top_color/bottom_color ramp spans the WHOLE texture (UV.y 0-1), and the
# opaque content - confined to UV.y ~0.017-0.476 - only ever received the
# fraction of the swing that falls within its own band (never reaching
# bottom_color at all). Also consumed by _add_treasure_overhang() itself
# to convert treasure_overhang_content_height_px (below) into the right
# uniform scale factor.
@export var treasure_overhang_content_height_px: float = 367.2688
# On-screen height, in pixels, of the OPAQUE CONTENT band specifically -
# RENAMED and REDEFINED from the old treasure_overhang_height_px
# (2026-09-01, overhang-contrast pass), which named itself for an on-
# screen height it didn't actually produce: it scaled the texture's FULL
# 941px (padding included), so its "800" default rendered the visible
# shape at only ~367px, a misleading name for a live-tunable export.
# Still one uniform scale_factor across the whole sprite (preserving
# aspect ratio, same as before) - just computed as content_height_px /
# (the content band's own native pixel height, via treasure_overhang_
# content_uv_top/_bottom * native_size.y) instead of full_height_px /
# native_size.y. Retuned 800.0 -> 367.2688 = the old default's own actual
# on-screen content height (800 * (448-16)/941), specifically so this
# rename+redefine is a no-op on today's render - see this pass's own
# brief ("do not change the on-screen result"). Retune this value
# directly now; it means what its name says.
@export var treasure_overhang_y_offset_px: float = 0.0
# Added downward offset from BACKGROUND_TOP_Y for the sprite's own
# position.y (2026-09-01, overhang-contrast pass) - previously hardcoded
# with no export at all, so nudging the overhang down (independent of
# every other BACKGROUND_TOP_Y-anchored element) required a code edit.
# Default 0.0 reproduces the prior fixed y = BACKGROUND_TOP_Y exactly.
@export var treasure_overhang_center_ratio: float = 0.62
# Horizontal placement, as a fraction of RoomState.room_width() - correct TREASURE's
# own room width specifically (now single-screen, see field_room.gd's own
# _is_single_screen_room()), not background_tile_width (the background
# LAYER's own repeat period, an unrelated number this mass has no reason
# to share now that TREASURE doesn't scroll). Positions the TEXTURE's own
# horizontal center (not the opaque content's own visual center - the
# asset is asymmetric, right-anchored, tapering left) at this x - kept as
# a plain, mechanical anchor rather than trying to derive "correct"
# alignment from the asset's own content bounds, per this pass's own
# brief: retune by hand against the chest cluster, the same way 0.62 was
# originally tuned against it for the old procedural blob (see RoomState.
# treasure_chest_a_x_offset_px's own doc) - a coincidental match, not a
# live dependency either way (see this pass's own investigation report).
@export var treasure_overhang_color: Color = Color(0.1276, 0.1529, 0.1867, 0.92)
# REPLACES the old treasure_overhang_color, which defaulted to `=
# occluder_color` and was applied as a flat Polygon2D.color (2026-09-01,
# textured-overhang pass - see this pass's own investigation report for
# the exact old symbol/value/application before this change). Now the
# vertical-shade BASE color (see _apply_vertical_shade() below), not a
# flat fill - independent of occluder_color, since this shape now needs
# its own tuned two-tone read rather than a borrowed default. Solved so
# that darkened(treasure_overhang_shade below) lands almost exactly on
# the requested main-mass target #1E242C - see treasure_overhang_shade's
# own doc for why the underside target (#2E3742) can only be approximated,
# not hit exactly, by this same pair of numbers.
@export_range(0.0, 1.0, 0.01) var treasure_overhang_shade: float = 0.08
# Fed into _apply_vertical_shade(treasure_overhang_shape, treasure_
# overhang_color, treasure_overhang_shade, true) - the trailing `true`
# inverts the ramp (see that function's own new `invert` parameter): DARKER
# at top (the main mass, in shadow, away from any light source) and
# LIGHTER at the bottom (the underside, catching ambient bounce light from
# the ground/interior) - the opposite of the foreground band's own
# lighter-top/darker-bottom read, per this pass's own brief.
#
# Cannot hit both requested hex targets exactly with one shared shade
# value: darkened(0.08) on treasure_overhang_color's own default lands at
# (30,36,44) = #1E242C, an exact match for the requested main-mass color -
# but lightened(0.08) on that SAME base lands at (50,56,64) = #323840,
# not the requested #2E3742 (46,55,66). The two targets don't differ by a
# uniform shift toward white on all three channels (the per-channel delta
# is 0.063/0.075/0.086 - R, G, B all different), which is the only kind of
# difference base_color.lightened(shade)/.darkened(shade) can express from
# a single shared shade scalar - hitting both exactly would need two fully
# independent colors, which this pass's own brief explicitly ruled out
# ("add an explicit parameter for direction rather than... a second
# shader or a second sprite"). Picked to land the darker, more visually
# dominant main-mass value exactly on target and let the lighter underside
# fall close (within ~4/255 per channel) rather than the reverse - retune
# this value (and/or treasure_overhang_color itself) by eye if the
# underside needs to read closer to #2E3742 specifically.

@export_group("Treasure ground shade")
@export var treasure_ground_shade_spread: float = 1.5
# RAISED 1.15 -> 1.5 (2026-09-02, ground-shade size pass) - read too
# subtle at 1.15. Width = the overhang's own on-screen OPAQUE x extent
# (measured the same way _add_treasure_overhang() itself is - see
# _add_treasure_ground_shade() below) times this factor. >1.0 on purpose -
# a soft patch under diffuse light reads wider than its own occluder, not
# as a tight projection of its silhouette the way a hard cast shadow would.
@export var treasure_ground_shade_center_x_offset: float = 0.0
# Added to the overhang's own opaque x-extent CENTER (not the texture's
# own center_ratio anchor - see treasure_overhang_center_ratio's own doc
# for why those two differ) - 0.0 by default centers the patch under the
# overhang's real visual mass exactly.
@export var treasure_ground_shade_height_px: float = 140.0
# RAISED 90 -> 140 (2026-09-02, ground-shade size pass) - read too subtle
# at 90. On-screen height, independent of contact_shadow.png's own
# 512x192 native aspect (see _add_treasure_ground_shade()'s own doc on the
# non-uniform scale this requires) - still much flatter than the texture's
# native ~0.375 aspect, since this reads as a broad patch on a ground
# plane seen near-edge-on, not a shadow directly beneath an object viewed
# from above.
@export var treasure_ground_shade_center_y_offset: float = 40.0
# Added to RoomState.floor_line_y for the patch's own center y - positive
# (down into the sand) so the patch sits WITHIN the ground band rather
# than straddling the sky/sand seam at floor_line_y itself.
@export var treasure_ground_shade_color: Color = Color(0.11, 0.13, 0.16, 0.48)
# RAISED alpha 0.22 -> 0.34 -> 0.48 across two darken passes (2026-09-02) -
# still read too light at 0.34. RGB untouched both times, only the third
# channel of "how dark" (the other two being the color itself and the
# texture's own soft radial falloff) moved. Dark blue-charcoal, low alpha -
# the ONLY color information this patch
# carries, via Sprite2D.modulate (see _add_treasure_ground_shade()'s own
# doc for why that's correct for a white source texture, and why this
# export deliberately does NOT get added to _validate_background_
# contrast()'s plane_colors/detail_colors registers: same EXEMPT category
# cloud_color already holds there - "a plain white asset, tinted purely
# by this color plus... alpha," not a background PLANE or a material-
# bearing DETAIL - see that function's own doc on cloud_color for the
# identical reasoning).

@export_group("Treasure groundsheet")
@export var treasure_groundsheet_texture: Texture2D = preload("res://assets/regions/beach/Belongings/belonging_groundsheet_lighter.png")
# assets/regions/beach/Belongings/belonging_groundsheet_lighter.png
# (2026-09-02, groundsheet pass) - 1048x130, a sheet of cloth laid flat on
# the ground the three belongings sit on. Filename note: the brief that
# introduced this asked for belonging_groundsheet.png; the file actually
# dropped in the Belongings folder is named belonging_groundsheet_lighter.
# png (confirmed 1048x130, matching spec exactly - this is the intended
# asset, just not under the exact name asked for). Referenced as delivered
# rather than renamed, since renaming a dropped-in asset file wasn't part
# of this pass's brief either.
@export var treasure_groundsheet_width_px: float = 250

# Uniform scale target for the sprite's own width (see _add_treasure_
# groundsheet() below for why uniform, unlike the ground shade patch's
# deliberately non-uniform stretch). Default = 2.5x the pack's own on-
# screen width, "matching how the asset was authored": pack native width
# 419 * FieldChest.belonging_scale's own default (0.167) * chest_a's
# scale_multiplier (1.0) = 69.973, * 2.5 = 174.93. A fixed number, not a
# live formula - FieldChest.belonging_scale lives on a script that has no
# instance yet at the point this builds (see that function's own doc on
# call order) - retune by hand if belonging_scale or the pack's own
# texture ever change.
@export var treasure_groundsheet_center_x_offset: float = 0.0
# Added to the midpoint of the three belongings' own real x positions
# (chest position + belonging_offset.x each, read from RoomState.room_
# layout - see _add_treasure_groundsheet()'s own doc) - 0.0 by default
# centers the sheet under the belongings' own actual spread, not the
# chests' bare origins.
@export var treasure_groundsheet_bottom_y_offset: float = 75.0
# Added to RoomState.floor_line_y for the sheet's own BOTTOM edge - this
# is the asset's NEAR edge (the cloth's front hem, closest to the camera/
# player), not a contact point the way a chest's or belonging's own base
# is, so it sits slightly FORWARD of floor_line_y rather than exactly on
# it, per this pass's own brief.

@export_group("Treasure foreground rock")
@export var treasure_foreground_rock_enabled: bool = true
# Composition-test placeholder (2026-09-02) - a procedural Polygon2D, not
# real art. Gated behind its own bool (default true) so it can be toggled
# off from the Inspector without a code change, same convention every
# other optional element in this room already follows.
@export var treasure_foreground_rock_height_fraction: float = 0.25
@export var treasure_foreground_rock_width_fraction: float = 0.18
# Fractions of the viewport, not fixed pixels - see _add_treasure_
# foreground_rock()'s own doc for the exact bounding-box fit that turns
# these into a guaranteed on-screen size (not just an average of a
# randomly-jittered shape).
@export var treasure_foreground_rock_color: Color = Color(0.09, 0.11, 0.14, 1.0)
# Darkest value in the frame - slightly darker than the overhang's own
# darkened() result (#1E242C) since this mass is nearer the camera, and
# fully OPAQUE (alpha 1.0), unlike the overhang's 0.92 - a framing element
# sitting in front of the play plane has no reason to let anything show
# through it the way a hanging, further-back mass does.

@export_group("Background layers - particulates")
@export var particulate_far_count: int = 3
@export var particulate_far_color: Color = Color(0.52, 0.51, 0.5, 0.16)
@export var particulate_far_drift_speed_px_sec: float = 4.0
@export var particulate_far_motion_scale: float = 0.2
@export var particulate_near_count: int = 2
@export var particulate_near_color: Color = Color(0.52, 0.51, 0.5, 0.26)
@export var particulate_near_drift_speed_px_sec: float = 9.0
@export var particulate_near_motion_scale: float = 0.55
@export var particulate_radius: float = 2.5
# Two depth bands (this pass's own brief), same "far moves slower/fainter,
# near moves faster/slightly more visible" depth language the structure
# layers already establish, just with drift speed and alpha standing in
# for the size/height cues structures use. VERY sparse by default (2-3
# each, low alpha) - motes are meant to be a barely-there ambient read
# (ash/spore/salt register, depending on how a future biome dresses this
# same mechanism), not a snow effect. Each mote is its own field_
# particulate.gd instance (see that script) - drift is a constant
# per-frame crawl independent of this layer's own motion_scale (the
# engine-driven camera-pan parallax), not a replacement for it; a mote
# gets BOTH cues at once, same as everything else here gets its parallax
# speed AND its own size/detail as separate depth signals.
#
# DARKER than the sky behind them, not lighter (2026-08-24 retune) -
# shipped once already as light specks (0.85 RGB) against the sky, which
# read as stars: small, bright, roughly round dots on a darker backdrop
# is exactly what a star looks like, and their apparent "clustering" in
# the upper sky was really a contrast illusion (positions were already
# uniform across the full band - see _populate_particulate_layer()'s
# randf_range - light motes just vanished against the lighter horizon
# and only stood out against the darker upper sky). A mid gray (2026-08-
# 30 palette retune - no longer near-black, but still clears
# background_detail_luminance_floor with room to spare while staying
# darker than the now much paler sky around it) reads as a silhouette
# against bright air instead - debris, not stars - and stays reasonably
# visible across the WHOLE band rather than only the darker half.

@export_group("Background layers - contrast & tiling")
@export var background_plane_luminance_floor: float = 0.70
@export var background_detail_luminance_floor: float = 0.45
# Authored decisions about how pale this world is - NOT derived from any
# enemy, resource, or other in-game reference color. The world reads as
# dark figures (enemies, the player, chests, doors) against pale ground;
# these two floors exist so a future palette retune can't silently drift
# the background back toward those figures' own value range without
# _validate_background_contrast() (below) catching it immediately - the
# same "announce a violation loudly" philosophy RoomState's own
# entrance-clearance assertion already uses.
#
# Two floors, not one: a broad PLANE (sky, ground) and a small DETAIL
# sitting within that plane (a crack, a mote, a structure silhouette)
# aren't held to the same standard - a detail is legitimately darker
# than the plane it sits on without threatening the "pale world" read,
# since it never dominates the frame the way the plane itself does.
# background_plane_luminance_floor is the higher of the two;
# background_detail_luminance_floor is deliberately lower. See
# _validate_background_contrast()'s own doc for which colors sit in
# which tier, and for the third category (exempt from either floor).

func _luminance(color: Color) -> float:
	return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b

# under.lerp(over_rgb, over_alpha) is exactly the alpha-composite math a
# player would actually see (over_rgb drawn at over_alpha on top of
# under) - luminance is a linear function of RGB (see _luminance()), so
# this is equivalent to blending the two colors' LUMINANCES by the same
# weight, not an approximation of it.
func _blend_luminance(under: Color, over_rgb: Color, over_alpha: float) -> float:
	return _luminance(under.lerp(over_rgb, over_alpha))

# PLANE tier - the broad surfaces a room is built from. DETAIL tier -
# smaller elements sitting within a plane, held to the lower detail
# floor (see background_plane_luminance_floor's own doc for why the two
# are split). EXEMPT, checked by neither tier: occluder_color (see its
# own doc - foreground framing, meant to be dark), opening_room_foam_
# color (already pale, never at risk), OPENING_ROOM_OCEAN_COLOR (was
# never checked here, unaffected by this pass), and cloud_color
# (2026-08-30, cloud pass; still exempt through both the cloud-asset pass
# and the 2026-08-31 scattered-cloud rewrite that REPLACED the tiled band
# those passes built with discrete sprites - see _add_clouds()'s own doc)
# - atmosphere, not a background PLANE (it has no area of its own the way
# sky/ground do - each instance is a small, partially-transparent shape
# that only ever covers a fraction of the sky behind it) or a surface
# DETAIL (it carries no material information at all, unlike a structure
# silhouette or a ground patch - it's a plain white asset, tinted purely
# by this color plus whichever instance's own alpha). Checking its raw
# stored RGB (0.92, 0.93, 0.94 - already near-white, same neutral
# direction the sky gradient's own retunes have been pushing toward)
# against either floor would be checking a number that was never meant to
# represent what's actually visible on screen at cloud_alpha_min/cloud_
# alpha_max - the same reasoning the blended-luminance pass just below
# already applies to horizon_haze_alpha, just not worth a third pass here
# since every cloud is a low-alpha overlay sitting over whatever sky
# color is already validated on its own, not a second opaque plane.
func _validate_background_contrast() -> void:
	var plane_colors := {
		"sky_gradient_top_color": sky_gradient_top_color,
		"sky_gradient_horizon_color": sky_gradient_horizon_color,
		"ground_base_color": ground_base_color,
		"opening_room_sand_color": OPENING_ROOM_SAND_COLOR,
		# ground_color_wet/_dry (2026-08-31 wet-to-dry pass) - the two
		# endpoints _region_ground_color() interpolates between at runtime
		# when region_gradient_enabled is true. Checking both endpoints is
		# sufficient to guarantee every interpolated value between them
		# also clears the floor - luminance is linear in RGB (see
		# _luminance()), so a linear interpolation of two colors that both
		# clear a floor can only produce values between them, never below
		# either one (same convexity argument _validate_contrast_tier()'s
		# own doc already makes for the horizon-haze blend below). No
		# separate check for the interpolated result itself is needed.
		"ground_color_wet": ground_color_wet,
		"ground_color_dry": ground_color_dry,
	}
	var detail_colors := {
		"tower_color": tower_color,
		"far_structure_color": far_structure_color,
		"mid_structure_color": mid_structure_color,
		"vegetation_color": vegetation_color,
		"ground_patch_color": ground_patch_color,
		"ground_crack_color": ground_crack_color,
		"seam_debris_color": seam_debris_color,
		"tide_band_color": tide_band_color,
		"coastal_tide_band_color": coastal_tide_band_color,
		"recession_band_color": recession_band_color,
		"horizon_edge_color": horizon_edge_color,
		"coastal_seam_debris_color": coastal_seam_debris_color,
		"coastal_vegetation_color": coastal_vegetation_color,
		"particulate_far_color": particulate_far_color,
		"particulate_near_color": particulate_near_color,
	}
	_validate_contrast_tier(plane_colors, background_plane_luminance_floor, "PLANE")
	_validate_contrast_tier(detail_colors, background_detail_luminance_floor, "DETAIL")

# Two passes per tier, same shape regardless of which floor is passed
# in: raw luminance first, then luminance blended with the horizon haze
# on top (see horizon_haze_alpha's own doc). The haze sits ON TOP of
# whatever it's over at the seam, so checking a color's raw value alone
# would either be meaninglessly strict (the haze is never fully opaque)
# or a blind spot (skipped entirely, the thing this replaces). Blending
# is a linear (convex) combination of the two colors' luminances, so a
# haze color that's ALSO at or above the floor can only pull an already-
# compliant color's blended value further from the floor, never below
# it - this passes by construction with today's sky-derived haze color;
# it exists so a future haze color that ISN'T sky-derived (or an alpha
# pushed toward opaque) still gets caught for real, instead of being
# exempted.
func _validate_contrast_tier(colors: Dictionary, luminance_floor: float, tier_name: String) -> void:
	for color_name in colors:
		var color: Color = colors[color_name]
		var luminance := _luminance(color)
		assert(luminance >= luminance_floor, "%s's luminance (%.3f) is below the %s tier's background floor (%.3f)" % [color_name, luminance, tier_name, luminance_floor])

	for color_name in colors:
		var under: Color = colors[color_name]
		var blended_luminance := _blend_luminance(under, sky_gradient_horizon_color, horizon_haze_alpha)
		assert(blended_luminance >= luminance_floor, "horizon haze over %s's blended luminance (%.3f) is below the %s tier's background floor (%.3f)" % [color_name, blended_luminance, tier_name, luminance_floor])

const BACKGROUND_TOP_Y := 40.0
# TopWall's own inner edge - no longer a coverage bound for the sky
# itself (see _populate_far_layer(), which now extends to the room's
# true top, 0, since TopWall no longer renders anything to cover the gap
# - see _apply_room_framing()), kept only as the proportion basis for
# how tall background structures grow (_sky_band_height()).
@export var background_tile_width: float = 2200.0
# Each layer's content is built once as a single background_tile_width-
# wide tile, then set to repeat forever via ParallaxLayer.motion_mirroring
# - this is what guarantees no gap ever opens at a room edge, regardless
# of the room's actual width or where the camera's own limit_left/limit_
# right clamp it to: the content simply never runs out, so there's
# nothing to size against this specific room's bounds.
#
# MUST stay >= the logical viewport width (checked in _ready(), see
# below) - this used to be a fixed 900px const, well under the game's
# actual 1920px design viewport (window/size/viewport_width in project.
# godot; the game window itself is scaled down from this, but the
# logical canvas everything renders against is still 1920 wide). At
# certain scroll phases, covering a viewport wider than the tile itself
# needs THREE tile-repeats visible at once (the tail of one, all of the
# next, and the head of a third) - motion_mirroring doesn't reliably draw
# that many, which is exactly what caused the real, confirmed-via-
# screenshot gap at the room's right edge: at that specific camera
# position, only two of the three needed repeats were drawn, leaving a
# visible strip of nothing. Raised well past 1920 (2200) fixes this by
# construction: at most two tile-repeats are EVER needed to cover any
# viewport once the tile itself is wider than the viewport, which is
# exactly the safe case motion_mirroring handles correctly - re-verified
# via screenshot at both extreme edges of the widest room in the game
# (standard_room_width) after this change, no gap either side. This is
# also the biggest lever in the density rework above: a wider repeat
# interval means more negative space between repeats, not just fewer
# shapes packed into a smaller one.

# Floor's own left edge and bottom edge - the room's true left playable
# bound (matching LeftWall's inner face, which never moves - the
# entrance side is always the fixed origin regardless of room width) and
# the bottom wall's inner face. The TOP edge of this band moves with
# RoomState.floor_line_y (see _position_floor()); the RIGHT edge moves
# with RoomState.standard_room_width (see _room_floor_right_x() below) -
# both read live rather than being baked consts, so a room's width can
# be retuned without a second number here drifting out of sync.
const ROOM_FLOOR_LEFT_X := 40.0
const ROOM_FLOOR_BOTTOM_Y := 1040.0
const WALL_THICKNESS := 40.0 # Matches ROOM_FLOOR_LEFT_X - every wall's fixed collision depth from the room's true outer edge.
const GROUND_DEBRIS_BOTTOM_MARGIN_PX := 20.0
# How far above ROOM_FLOOR_BOTTOM_Y a ground decoration's own CENTER must
# stay - the same 20px margin _apply_standard_ground_treatment()'s own
# ground_patch/ground_crack loops already used before this constant
# existed, now shared by every ground-decoration spawn site (2026-08-27,
# "stay below the field line" fix) rather than re-typed per site. Paired
# with each shape's own _shape_max_upward_reach() (see that function's
# own doc) at the TOP of the valid band - see _add_seam_debris()/_add_
# coastal_seam_debris()/_apply_standard_ground_treatment() for where
# both ends of the band actually get used.

func _room_floor_right_x() -> float:
	return RoomState.room_width() - WALL_THICKNESS

@export var floor_overscan_margin_px: float = 200.0
# The floor polygon's own visual span, DECOUPLED from RoomState.room_width() -
# 2026-08-29, single-screen COMBAT pass. This wasn't asked for as one of
# the tunables in this pass's own brief - added because "no edge ever
# visible" needs a real margin number somewhere, and every other feel
# value in this file is exported rather than a bare const; flagged as an
# addition in this pass's own report. See _floor_span_left_x()/_floor_
# span_right_x() below for what this actually feeds.
#
# THE floor's own true visual extent - RoomState.room_width() still drives every
# WALKABLE bound (walls, camera limit, exit/content placement) completely
# unchanged; only what the Floor polygon itself (and anything meant to
# match its exact span, e.g. _add_wavy_band()'s default) draws is
# affected here. Guarantees at least RoomState.viewport_width() of
# coverage plus this margin on each side, regardless of how narrow a
# room's own walkable width gets (COMBAT, post this pass) - and still
# extends past a WIDER room's own edges by the same margin (standard/
# TREASURE/etc., where the camera already couldn't reach the true edge,
# per this pass's own brief: "incidental" before, guaranteed now).
#
# The opening/arrival room is excluded (returns to the exact 0.._room_
# width() span it always had) - not because its floor would look wrong
# otherwise, but because _apply_opening_room_layout() reaches back into
# THIS polygon's own left-edge points afterward (floor_poly[0]/[3], see
# that function's own doc) to carve the ocean/void inset, and this pass
# was told explicitly not to touch the opening room in any way. Keeping
# its input span byte-for-byte identical is the safest way to guarantee
# that.
func _floor_span_left_x() -> float:
	if RunState.current_node == RunState.opening_node:
		return 0.0
	return -floor_overscan_margin_px

func _floor_span_right_x() -> float:
	if RunState.current_node == RunState.opening_node:
		return RoomState.room_width()
	return maxf(RoomState.room_width(), RoomState.viewport_width()) + floor_overscan_margin_px

# The floor polygon's own BOTTOM edge - same "decoupled from the fixed room
# geometry, guaranteed to cover the current effective view plus a margin"
# idiom _floor_span_right_x() above already uses horizontally (2026-09-06,
# field-pull-back pass). _room_height() (1080, ROOM_VERTICAL_CENTER * 2) is
# a hand-baked viewport height with the same implicit "zoom is always 1.0"
# assumption RoomState.combat_room_width()'s own doc already found once for
# width - at RoomState.field_zoom under 1.0 the effective visible world
# height (get_viewport().get_visible_rect().size.y / field_zoom) exceeds it,
# leaving the floor polygon short and exposing whatever's beneath its true
# bottom edge (the bug this pass's own investigation traced here).
#
# _room_height() ITSELF is deliberately left untouched, not widened to match
# - separately, what field_room.tscn's own baked Camera2D.limit_bottom
# (1080) already equals by construction (see _populate_occluder_layer()'s
# own note on that having zero clamping slack - untouched here, a camera-
# limits question, not a floor-geometry one). Reaching in to widen _room_
# height() itself would have moved the ocean wall along with it; adding
# this SEPARATE function for the callers that actually need a taller floor
# avoids that entirely, the same way _floor_span_right_x() already has its
# own independent value rather than reusing RoomState.room_width() directly.
#
# No longer excludes the opening/arrival room (2026-09-07, opening-room
# floor-bottom fix - REPLACES the exclusion this function used to carry,
# which _apply_coastal_opening_room_layout()'s own ocean-strip math shared
# by deriving water_half_length/water_center_y from _room_height() too, not
# this function - see that function's own doc for why moving IT onto this
# same call closes the gap instead of reopening it). That old exclusion was
# never because the opening room's floor looked right at _room_height() -
# its own doc said so directly ("not because its floor would look right
# otherwise... a real gap this leaves unfixed for that one room, not a
# claim there isn't one") - it existed only because an earlier pass's brief
# was specifically "do not move the ocean wall," and _room_height() was the
# one value the water math and this floor edge still shared for that room.
# Once the water math reads THIS function instead of _room_height()
# directly, that constraint is satisfied by construction - both move
# together - so the exclusion no longer serves its own stated purpose and
# is removed rather than left stale.
func _floor_span_bottom_y() -> float:
	var effective_view_height: float = get_viewport().get_visible_rect().size.y / RoomState.field_zoom
	return maxf(_room_height(), effective_view_height) + floor_overscan_margin_px

@onready var player: Player = $Player
@onready var player_visual: PlayerVisual = $Player/Visual

@export var player_shadow_y_offset: float = -30.012
# Overrides RoomState.entity_shadow_y_offset's own -18 default for the
# player specifically (2026-08-30, shadow-tuning pass) - DERIVED, not
# guessed. VisualBounds treats AnimatedSprite2D bounds as the sprite's
# whole nominal 256x256 cell (see visual_bounds.gd's own _texture_bounds()
# - it never reads alpha), not the character's real drawn extent, so its
# "bottom" is the bottom of the frame's own transparent margin, not her
# feet. player_visual.gd's own _sprite comment already establishes the
# real numbers this reuses: the walk-cycle's true lowest opaque pixel
# sits at local row 225.5 of 256 (not row 256, the frame's own nominal
# edge), and Sprite's offset (-97.5) was deliberately chosen so THAT row
# lands at Sprite-local y=0. Chasing the same transform chain through:
# VisualBounds' own (wrong) bottom = (128 + -97.5) * 8 * scale + 17; the
# REAL bottom = (0) * 8 * scale + 17 = 17.0 always (Sprite's own scale=8,
# Visual's own scale=RoomState.player_visual_scale, PlayerVisual's own
# position.y=17 - see player_visual.tscn) - the real bottom's local y is
# 0, so scale drops out and it never moves. The correction is therefore
# always -244 * player_visual_scale (17.0 minus the wrong-bottom formula
# above, with the +17 term cancelling).
#
# RE-DERIVED (2026-09-01, field composition pass) - player_visual_scale
# dropped 0.15 -> 0.107 (see its own doc). Wrong bottom = (128 + -97.5) *
# 8 * 0.107 + 17 = 43.108; real bottom = 17.0 as always; -26.108 is
# exactly 17.0 - 43.108, the same correction recomputed for the new
# scale. (Old value at 0.15 was -36.6, matching -244 * 0.15 exactly.)
#
# RE-DERIVED AGAIN (2026-09-01, one-tick size bump) - player_visual_scale
# raised 0.107 -> 0.123 (+15%, same lever as the field composition pass
# above, a tune not a re-derivation - see its own doc). Same formula,
# same -244 * player_visual_scale correction (the +17 term still
# cancels): -244 * 0.123 = -30.012.
# Scale is applied here at runtime, from RoomState.player_visual_scale
# (see _ready() below) - field_room.tscn's own Visual node instance no
# longer bakes a `scale` override (2026-08-30, spatial framing pass),
# so this is the one place that number actually gets set.
@onready var camera: FieldCamera = $Player/Camera2D
# Retyped from plain Camera2D (2026-08-29, single-screen COMBAT pass) -
# needed a static type that actually exposes follow_enabled (see field_
# camera.gd's own doc) to set it in _position_room_bounds() below.
@onready var content_root: Node2D = $Content
@onready var treasure_overhang_shape: Sprite2D = $Content/TreasureOverhangShape
# A Sprite2D showing treasure_overhang_texture (2026-09-01, textured-
# overhang pass - REPLACES the hand-drawn/procedural Polygon2D this same
# node used to be, see this pass's own investigation report for the prior
# mechanism). Position/scale are fully computed by _add_treasure_overhang()
# below on every TREASURE room load, same as every other generated
# background element in this file - nothing about this node's placement is
# baked into field_room.tscn any more.
@onready var treasure_foreground_rock_shape: Polygon2D = $Content/TreasureForegroundRock
# HAND-AUTHORED polygon, editable in the 2D editor's own polygon tool
# (2026-09-02, foreground-rock-editability pass - REPLACES this node's own
# prior existence as a Polygon2D.new() built entirely in code from
# _irregular_blob_shape()). The `.polygon` array baked into field_room.
# tscn is the one and only source of the shape now - _add_treasure_
# foreground_rock() below never rewrites it, only measures its bounding
# box once and applies a Node2D scale/position on top, same "preserve the
# authored shape, size it via transform" convention Sprite2D-based assets
# in this file already use (the belongings, the overhang, the
# groundsheet) - never rewrite the points to hit a target size.
@onready var exits_root: Node2D = $Exits
@onready var floor_polygon: Polygon2D = $Floor
@onready var run_hud: RunHUD = $UI/HUD
# HP/gold/room-number/room-type display - extracted (2026-08-26) into its
# own reusable scene (run_hud.tscn/.gd) so the card reward screen could
# show the same run context. Fully self-sufficient (sets its own labels
# and refreshes its own HP bar in _ready()) - field_room.gd no longer
# pushes anything into it directly, only reaches back in for the actual
# VitalsBar node below, which ShopWindow needs a live reference to.
@onready var deck_button: TextureButton = $UI/DeckButton
@onready var deck_label: Label = $UI/DeckLabel
@onready var deck_viewer: DeckViewer = $DeckViewer
@onready var shop_window: ShopWindow = $ShopWindow
@onready var map_button: TextureButton = $UI/MapButton
@onready var map_label: Label = $UI/MapLabel
@onready var map_screen: MapScreen = $MapScreen
@onready var exit_haze: TextureRect = $UI/ExitHaze
@onready var ui_layer: CanvasLayer = $UI
# The CanvasLayer itself, not just one of its children (2026-09-06,
# positional world-voice pass) - _setup_opening_room_hull_line() below
# needs a parent to add_child() its own procedural Label onto, the same
# screen-space CanvasLayer Deck/Map/ExitHaze already draw through, rather
# than a new CanvasLayer built just for one label.
@onready var dev_room_picker: OptionButton = $UI/DevRoomPicker
# DEV AFFORDANCE - matches this project's ONLY existing convention for
# dev-only tools (see dev_encounter_picker.gd's own header): a plainly-
# labeled, always-visible control, no release-build gating. Generalizes
# what used to be a single DevBossRoomButton (2026-09-01) - jumps straight
# to a freshly-generated field room of WHICHEVER RoomType.Kind is picked,
# via RoomState.load_room() - the EXACT SAME call map_screen.gd makes once
# the player picks a node on the map (see its own call site), just made
# directly with a chosen Kind instead of whatever node the player actually
# picked. One dropdown covering all seven kinds replaces the old boss-only
# button rather than sitting alongside it - a single-purpose shortcut a
# general one already covers is clutter, not a second convenience.
# Deliberately does NOT touch RunState (HP/gold/deck all carry over
# unchanged) or RunState.current_node - this is a shortcut to the ROOM,
# not a fast-forward through the run graph, so nothing downstream needs
# to reconcile a graph position that never actually moved.

@onready var weapon_pickup_window: WeaponPickupWindow = $WeaponPickupWindow
# The chest-granted-weapon path's own Equip/Leave decision (2026-08-27,
# in-field reward pass) - reused as-is from reward_screen.tscn (same
# scene, same script). field_room.gd owns this instance the same way it
# owns shop_window/deck_viewer/map_screen - a permanent sibling, opened
# by calling its public open_reward(), never reached into otherwise -
# EXCEPT for reading its own backdrop.color.a directly (see
# additional_wanderer_dim's own doc below), the one piece of state this
# file needs from it to keep the player's own extra dim proportional to
# whatever the modal's shared world-dim wash is currently tuned to.

@export_group("Reward Dimming")
@export_range(0.0, 1.0, 0.01) var additional_wanderer_dim: float = 0.35
@export_range(0.0, 1.0, 0.01) var button_dim_opacity: float = 0.35
# Field-specific companions to weapon_pickup_window.gd's own Backdrop
# alpha (2026-08-28, reward-modal legibility pass) - that modal's own
# flat Backdrop only ever darkens what it draws OVER (the whole game
# world, painted before the UI layer it sits on), it has no way to reach
# into field_room's own specific nodes to darken THEM beyond that shared
# wash. This file already owns all three targets that needed MORE than
# the shared wash (the chest via _chest_in_room below, the player, the
# Deck/Map buttons), so it's the natural place for the extra, targeted
# dimming - see _dim_field_for_reward()/_undim_field_for_reward(), wired
# to the exact same open/resolve lifecycle _on_chest_weapon_offered()/
# _on_chest_weapon_pickup_resolved() already drive.
#
# additional_wanderer_dim STACKS on top of weapon_pickup_window.backdrop.
# color.a (read directly, not mirrored here - same "direct-read consumer"
# pattern HudPalette's own consumers already use) - the
# Wanderer sits directly behind the flavor text/choice row and needs to
# fall further into shadow than the rest of the world, not just match
# it, so text never crosses a high-contrast silhouette edge.
#
# button_dim_opacity is Deck/Map's own alpha while the modal is up - a
# Control fading toward transparent reads as "temporarily inert," the
# correct language for a UI button (unlike the chest/player, which are
# WORLD sprites - see _dim_field_for_reward()'s own doc on why those get
# a modulate DARKEN instead of an alpha fade).

@export_group("Field HUD Icons")
@export var hud_icon_height_px: float = 48.0
# Deck/Map's own icon height (assets/ui/hud/Deck.png, Map.png - already
# cropped to opaque content bounds, see each file's own history). Width
# is DERIVED per-icon from its own texture's aspect ratio in _configure_
# hud_icon_button() below, not a second exported number - Deck (~1.05:1)
# and Map (~0.93:1, an upright scroll as of the 2026-09-05 asset swap)
# aren't the same shape, and hand-tuning two widths in sync with one
# height would just be two numbers that could drift.
# DOWN from 72 (2026-09-05, size/brightness retune) - 72 read too large
# against the pale field, competing with the scene rather than sitting
# quietly in its corner.
@export var hud_icon_gap_px: float = 28.0
# Horizontal gap between DeckButton's own right edge and MapButton's own
# left edge (2026-09-05, icon-spacing pass - REPLACES the old baked
# 144.5px gap the two clusters inherited from the original 200px-wide
# text buttons, which read as too far apart once both were icons).
# DeckButton keeps its own baked offset_left (33, field_room.tscn) as
# the cluster's fixed anchor; MapButton's own offset_left is computed
# from THIS plus deck_button.offset_right in _ready() below, AFTER
# deck_button's own _configure_hud_icon_button() call has set its real
# width - not a second hand-picked offset_left that could drift out of
# sync with Deck's own (aspect-ratio-dependent) width. DOWN from 75
# (2026-09-05, size/brightness retune, same pass as hud_icon_height_px
# above) - the two icons should read as one control cluster, not two
# separate objects sharing a corner.
@export var hud_icon_hover_scale: float = 1.06
# Modest growth on hover - a quiet HUD element on a still, pale screen
# per this pass's own brief, not a game button begging for a click.
@export var hud_icon_press_scale: float = 0.94
# Shrinks slightly below rest on press, same magnitude direction as
# hover's growth - reads as "give," the standard press affordance.
@export var hud_icon_scale_tween_sec: float = 0.12
# Shared duration for every hover/press scale tween below - quick enough
# to feel responsive, slow enough not to read as a snap.
@export var hud_icon_label_font_size_px: int = 12
# Deck/Map's own labels used to read run_hud.compact_value_font_size_px
# (12, 2026-09-05 icon pass) - DROPPED in favor of this independent
# export (2026-09-05, label-legibility pass): that value is tuned for
# the quiet, backdrop-free compact HUD strip, while these two labels sit
# directly over the scene's own foreground band - a shared size with an
# unrelated UI strip was never the right coupling, just the value that
# happened to already exist when these labels were first built.
@export var hud_icon_label_color: Color = Color.WHITE
# Tried Color(0.42, 0.44, 0.48) as a system-voice register fix
# (2026-09-05) - reverted the same day after seeing it live: read too
# dark/low-contrast against the sand ground in practice, whatever the
# register argument for it. Back to white pending a better-tuned muted
# value, if one ever proves out live. Exported (not a literal in
# _configure_hud_icon_button() below) so it can still be retuned without
# a second pass.

# --- Exit haze (DECIDED, 2026-08-28 - replaces field_exit.gd's own flat-
# colored Polygon2D door, see that file's own header) ---
#
# A screen-space atmospheric band at the right edge of the viewport,
# instead of a literal silhouette marking the door - the field's own
# backdrop is still placeholder (see this file's own header on the
# background layers), so this is deliberately cheap: one TextureRect, one
# small GradientTexture2D built once, no per-biome abstraction. Pulls its
# tint from SunkenWorksPalette (SKY_HORIZON, the paler/warmer of its two
# sky tones - closer to how a real hazy distance actually reads than the
# deeper overhead SKY_HIGH) rather than a hardcoded color, so this stays
# correct if the biome's own palette ever moves without anyone having to
# remember a second copy here.
#
# UI (not SkyLayer) is the right CanvasLayer for this - SkyLayer sits at
# layer -100, BEHIND the parallax background and every silhouette in it
# (see its own doc); this needs to draw OVER the game world (the "haze"
# is meant to be atmosphere near the camera, not part of the distant
# backdrop). UI's default layer (1) already draws above the plain-Node2D
# game world for free, and HUD/DeckButton/MapButton (all left-anchored,
# see their own offsets) never overlap the right-edge band this occupies -
# ExitHaze is inserted BEFORE them in field_room.tscn's own child order
# regardless, so nothing that DID overlap would be hidden by it.
@export_group("Exit Haze")
@export_range(0.0, 1.0, 0.01) var exit_haze_width_fraction: float = 0.18
# Fraction of the VIEWPORT's own width (not the room's) - anchors, not a
# fixed pixel offset, so this stays correct across resolutions (see
# _setup_exit_haze()'s own use of anchor_left instead of offset_left).
@export_range(0.0, 1.0, 0.01) var exit_haze_height_fraction: float = 1.0
# Fraction of the viewport's own height the band reaches down from the
# top, via anchor_bottom (2026-09-06, field-pull-back pass) - previously
# hardcoded to the full 0..1 anchor range (anchors_preset=15 in field_
# room.tscn, never touched by code), tuned back when the band only ever
# overlapped sky. RoomState.field_zoom widening the room means the same
# full-height band now reaches down into the ground strip too, where the
# same pale sky-tinted gradient reads as a hard-edged lighter rectangle
# rather than a soft atmospheric hint - see this pass's own investigation
# report. Default 1.0 preserves that exact prior full-height behavior;
# dial it down to keep the band clear of the ground.
@export_range(0.0, 1.0, 0.01) var exit_haze_resting_alpha: float = 0.25
@export_range(0.0, 1.0, 0.01) var exit_haze_approach_alpha: float = 0.6
@export var exit_haze_approach_distance_px: float = 600.0
# All four of the above are feel values, expected to be retuned by eye
# once there's real art to check them against - see this pass's own
# report. Deliberately not hardcoded, and deliberately not a fifth
# "smoothing speed" export: the alpha is a direct, continuous function of
# the player's CURRENT distance to the door (see _update_exit_haze()
# below), not a time-based tween toward a target - since position itself
# only ever changes smoothly (the player walks, it doesn't teleport),
# that's what already makes the brightening read as continuous rather
# than a UI element stepping on, with no separate easing needed.

# --- Room transition (DECIDED, Option B - see DESIGN.md's field movement
# redesign: navigation redesign, "continuous journey" pass) ---
#
# Neither export moves the player past the frame edge (Option A, explicitly
# rejected for this pass - no wall collision changes, no camera limit
# changes) - both just remove the two most jarring cuts: the map opening
# the instant the door is touched (player still mid-step), and a new room
# showing the player already standing still. Both drive the player through
# the real move_to()/velocity path (see player.gd's input_locked/
# scripted_speed), never a position tween, so footsteps keep playing.
@export_group("Room Transition")
@export var walk_on_offset_px: float = 200.0
# How far back (in -x) a freshly-loaded room starts the player from their
# normal spawn point, before scripting them forward to it - see
# _play_walk_on_intro(). Clamped against the left wall (see that
# function's own WALK_ON_SAFETY_CLEARANCE_PX use) so mistuning this too
# high can't spawn the player inside/behind the wall - it just clamps to
# the closest safe start point instead.
@export var walk_on_speed: float = 400.0
# Deliberately its own number, not player.gd's SPEED (750, normal keyboard
# pace) - a slower, more deliberate "walking into a new place" beat reads
# better than the player's usual brisk traversal speed. Feel value.
@export var departure_walk_distance_px: float = 60.0
# How far the player keeps walking (in +x, toward the door) after
# exit_entered fires, before the map opens - see _on_exit_entered(). Set to
# 0 for no departure beat at all (the map opens immediately, matching the
# old behavior). Clamped against the exit wall the same way walk_on_
# offset_px is clamped against the entrance wall - mistuning this past the
# actual gap to the wall just has the player walk up to it and stop
# (move_and_slide()'s own collision response), not get stuck.
const WALK_ON_SAFETY_CLEARANCE_PX := 30.0
const DEPARTURE_SAFETY_CLEARANCE_PX := 30.0
# A real, permanent HUD button now (DESIGN.md's field movement redesign:
# navigation redesign step 3) - promoted from step 2's temporary "Map
# (Dev)" dev-only entry point. Opens the map in VIEWING mode: informational
# only, dismissible (Close/Escape both work), reachable nodes shown but
# not clickable - the player can check the run's shape at any time
# without committing to travel. The door (see _spawn_exits()) is the
# OTHER, TRAVEL-mode entry point - opened only by walking into the exit,
# not dismissible without picking a node, since that's a real commitment
# to leave. Same MapScreen instance, two different open_map_for_*()
# entry points - see map_screen.gd for the mode split.
@onready var walls: Array[FieldWall] = [
	$TopWall, $BottomWall, $LeftWall, $RightWall,
]
@onready var left_wall: FieldWall = $LeftWall
# The only wall the opening room touches individually (see _apply_
# opening_room_layout()) - top/bottom/right get the standard room-width
# resize every room gets (see _position_room_bounds()) and nothing else.
@onready var top_wall: FieldWall = $TopWall
@onready var bottom_wall: FieldWall = $BottomWall
@onready var right_wall: FieldWall = $RightWall

var exits: Array[Area2D] = []

var _cloud_drift_state: Array[Dictionary] = []
# One Dictionary per scattered cloud sprite ({"sprite": Sprite2D, "speed":
# float}), populated once by _add_clouds() and consumed every frame by
# _update_cloud_drift() (see that function's own doc) - the room-wide
# _process() below already exists for exit_haze's own per-frame tracking,
# so cloud drift joins it rather than adding a second _process()
# (GDScript only allows one per script anyway).
var _cloud_drift_range_min: float = 0.0
var _cloud_drift_range_max: float = 0.0
# The shared horizontal span every cloud drifts and wraps within, cached
# once by _add_clouds() (same for every cloud, so computing it per-sprite
# in _update_cloud_drift() every frame would be pure waste) - see _add_
# clouds()'s own doc for how it's derived.

var _vegetation_sway_state: Array[Dictionary] = []
# One Dictionary per swaying clump ({"sprite": Sprite2D, "phase": float,
# "period": float}), populated by _add_vegetation_clump() and consumed
# every frame by _update_vegetation_sway() (2026-08-31, vegetation-sway
# pass) - same shape and same "joins the existing shared _process()"
# reasoning as _cloud_drift_state above, just for a different ambient-
# motion system.
var _vegetation_sway_time: float = 0.0
# A single shared elapsed-time accumulator (2026-08-31, vegetation-sway
# pass), not one per clump - every clump's own sway is sin(TAU * this /
# period + phase), so ONE running clock plus each clump's own phase/
# period is enough to give every clump an independent-looking motion;
# a per-clump elapsed timer would track the exact same quantity
# redundantly _vegetation_sway_state.size() times over.

var _npc_in_contact: Area2D = null
# The FieldNPC the player is CURRENTLY standing in the trigger zone of,
# if any - null the rest of the time (never approached one, or already
# walked away - see _on_npc_entered()/_on_npc_exited() below, which are
# the only two writers). Read by _on_npc_clicked() to decide whether a
# click on her means "accept her offer" or just "walk to her" the same
# way clicking any other interactable does (see that function's own
# note on why NPCs need a dedicated click handler at all instead of
# reusing _on_interactable_clicked()).

var _npcs_in_room: Array[Area2D] = []
# EVERY NPC spawned into this room (see _spawn_npc()), not just whichever
# one the player happens to be in contact with - _npc_in_contact above is
# null the instant she's walked away from, but her offer_label can still
# be mid-fade-out at that moment, so _dim_field_for_reward() needs a
# durable handle on her regardless of live contact state. Mirrors
# _chests_in_room's own "every one, not just the active one" shape below.

var _npc_offer_card: Card = null
# The single floating card offered near her, if any - null when nothing
# is currently offered (never approached, already accepted, or freed
# after flying to the deck - see _show_npc_offer_card()/_on_npc_offer_
# card_clicked() below, the only writers). Persists across an approach/
# walk-away/re-approach cycle rather than being destroyed and recreated
# each time - _on_npc_exited() only fades it, never frees it, so "she
# stays re-approachable, returning shows the same card again" (this
# feature's own brief) is literally true, not just visually identical.
# Always rendered at set_scale_factor(1.0) - full, correctly-proportioned
# hand-card layout - see _npc_offer_card_wrapper below for how it's
# actually made to render smaller (2026-08-27, proportions fix).

var _npc_offer_picked_card: CardData = null
# WHICH of npc_data.granted_cards she's currently offering, if any (null
# until first rolled) - 2026-08-27, offer-pool pass. Rolled ONCE, inside
# the same `if _npc_offer_card == null:` lazy-build guard _show_npc_
# offer_card() already uses to build the card node exactly once per
# visit (see that var's own doc on why this persists across a walk-away/
# return cycle rather than being destroyed and recreated) - since the
# roll happens at the exact same point the node itself is first built,
# "stable for the visit, not a reroll on return" falls out of the
# EXISTING persistence mechanism for free, rather than needing its own
# separate bookkeeping. Lives here, not on NPCData itself, because
# NPCData is the static, never-mutated DEFINITION of her whole pool (see
# its own granted_cards doc) - which single card she's already showing
# THIS visit is interaction state, the same "static Resource vs. mutable
# per-run/per-visit state" split this project draws everywhere else
# (EnemyData/EnemyCombatant, StatusEffectData/ActiveStatus). Read by
# _on_npc_offer_card_clicked() so accepting grants the SAME card that
# was actually shown, not a second, independent roll.

var _npc_offer_card_wrapper: Node2D = null
# The plain Node2D that actually makes the card render smaller, via a
# uniform transform (`scale`), rather than card.gd's own set_scale_
# factor() (2026-08-27, proportions fix - see card.gd's own set_scale_
# factor() doc for the full root cause: its re-layout breaks down below
# roughly f=0.4, since border widths are fixed constants in card.tscn
# that never scale with the factor). Deliberately a SIBLING wrapper
# around the card, not applied to Card's own `visual` child - `visual`
# is where hover/armed already tween `scale` to ABSOLUTE targets (1.0
# at rest, hover_scale/armed_scale otherwise, see card.gd's own _play_
# hover_tween()), so a baseline non-1.0 scale living on that same
# property would fight those tweens outright, snapping the card to
# native size the instant it's hovered instead of popping proportionally
# off whatever size this wrapper renders it at. Holding the transform
# one level OUTSIDE `visual` (on this wrapper, a sibling of Card's own
# root Control, not a descendant of it) lets the two scales compose
# multiplicatively instead of fighting: wrapper.scale (npc_offer_card_
# scale) times visual.scale (1.0 or hover_scale) is exactly the
# proportional pop this needed.
var _npc_offer_card_tween: Tween

var _npc_offer_card_rest_position: Vector2 = Vector2.ZERO
# The wrapper's own AT-REST position (its CENTER, per npc_offer_card_x_
# offset/_y_offset) - stored once when the wrapper is first created
# (2026-08-27, hover-expansion pass), since _on_npc_offer_card_hover_
# changed() below needs to know where the card's own NEAR edge (the one
# closest to her) sits at rest to keep it fixed while the FAR edge grows
# during hover - see that function's own doc for the full math. Reading
# _npc_offer_card_wrapper.position directly at hover time wouldn't work
# once a hover tween is already mid-flight (it would be reading an
# in-between value, not the true rest position to anchor against).

var _npc_offer_card_hover_tween: Tween
# SEPARATE from _npc_offer_card_tween above (2026-08-27, hover-expansion
# pass) - that one drives the show/hide FADE, this one drives the
# hover-triggered scale/position animation; a card can start fading in
# and be hovered in the same moment (nothing stops the player from
# moving the mouse onto it immediately), and one tween killing the
# other's own in-flight animation because they shared a single var would
# be a real, easy-to-hit bug, not a hypothetical.

var click_to_move: ClickToMove = null
# Owns ground-click movement, click-to-approach on every interactable
# registered below, and the shared ground marker - see click_to_move.gd's
# own header for why this lives in its own reusable script now instead of
# inline here (2026-08-27 refactor, no behavior change - field_interior.gd
# is the first OTHER scene to reuse it).

func _ready() -> void:
	# First, so every per-room system below (ground tint, vegetation
	# counts, landform chance, foreground band selection) reads the same
	# rolled value - see _region_gradient_value's own doc.
	_roll_region_gradient_value()
	if not use_field_backdrop:
		_validate_background_contrast()
	assert(background_tile_width >= get_viewport().get_visible_rect().size.x, "background_tile_width (%s) must be >= the logical viewport width (%s) or ParallaxLayer's motion_mirroring can leave a visible gap at extreme camera positions - see background_tile_width's own comment" % [background_tile_width, get_viewport().get_visible_rect().size.x])
	# run_hud sets its own Room/RoomType labels and refreshes its own HP
	# bar internally (see run_hud.gd's _ready()) - nothing to push into
	# it here any more, since its own _ready() already ran (children
	# ready before their parent).
	# Was a genuine one-time set, until the NPC card offer (2026-08-27)
	# made deck composition able to change mid-room after all - see
	# _on_npc_offer_card_clicked()'s own matching refresh once that
	# happens. Still set once here for the room's OWN opening value;
	# nothing else in a field room changes the deck.
	deck_label.text = "Deck (%d)" % RunState.deck.size()
	deck_button.pressed.connect(deck_viewer.open_deck)
	map_button.pressed.connect(_on_map_button_pressed)
	_configure_hud_icon_button(deck_button, deck_label)
	# MapButton's own offset_left is DERIVED from Deck's now-real offset_
	# right + hud_icon_gap_px, not a second baked number - see that
	# export's own doc. Must run after Deck's own _configure_hud_icon_
	# button() call above, which is what actually gives deck_button.
	# offset_right its real (aspect-ratio-dependent) value.
	map_button.offset_left = deck_button.offset_right + hud_icon_gap_px
	map_label.offset_left = map_button.offset_left
	_configure_hud_icon_button(map_button, map_label)
	_populate_dev_room_picker()
	# ShopWindow reuses this same DeckViewer instance for its "Remove a
	# Card" selection step - wired here since field_room.gd is where both
	# already exist as siblings.
	shop_window.deck_viewer = deck_viewer
	weapon_pickup_window.resolved.connect(_on_chest_weapon_pickup_resolved)
	_start_region_ambient_bed()
	_start_region_field_music()
	# Default fresh-entry Y for a STANDARD room - field_room.tscn only
	# bakes an X for Player's spawn (its Y is whatever RoomState.
	# floor_line_y happens to be tuned to, not a fixed scene value). The
	# opening room's own spawn (below) and a return-trip's saved position
	# (further below) both fully overwrite this afterward, so this line
	# only ever matters for the plain "fresh into a normal room" case.
	player.position.y = RoomState.floor_line_y
	# Data-driven now (2026-08-30, spatial framing pass) - REPLACES field_
	# room.tscn's own baked Visual scale override, so retuning RoomState.
	# player_visual_scale (alongside floor_line_y above) is the one place
	# the field character's size changes, no scene file to edit.
	player_visual.scale = Vector2(RoomState.player_visual_scale, RoomState.player_visual_scale)
	# Contact shadow (2026-08-30, grounding-cue pass) - after player_
	# visual's own scale above, not before: EntityShadow.attach() measures
	# player_visual's real rendered bounds THROUGH its own transform (see
	# that function's own doc), so its scale has to already be final.
	EntityShadow.attach(player, player_visual, player_shadow_y_offset)
	_position_room_bounds()
	_position_floor()
	if use_field_backdrop:
		sky_layer.visible = false
		$Background.visible = false
		$Foreground.visible = false
		var backdrop = load("res://field_backdrop.tscn").instantiate()
		add_child(backdrop)
		move_child(backdrop, player.get_index())
		backdrop.build()
	else:
		_apply_standard_ground_treatment()
		_build_background_layers()
	_apply_wall_tint()
	_apply_room_framing()
	_apply_opening_room_layout()
	# After _apply_opening_room_layout() (not gated on room type, unlike
	# _apply_standard_ground_treatment() above) - see _populate_ground_
	# line_decoration()'s own doc for why every field room gets this,
	# opening room included, and why it runs from here rather than being
	# folded into either ground-treatment path.
	if not use_field_backdrop:
		_populate_ground_line_decoration()
	# Second call (2026-09-05, coastal-decoration fix) - see _hide_painted_
	# preview_decorations()'s own doc for why the one _apply_painted_
	# preview() already does, earlier in this function via _build_
	# background_layers(), misses everything _apply_opening_room_layout()
	# (just above) adds for the opening room specifically.
	if painted_preview_enabled:
		_hide_painted_preview_decorations()
	_setup_click_to_move()
	_generate_room_contents()
	_spawn_exits()
	_setup_exit_haze()
	_setup_opening_room_hull_line()

	if RoomState.has_saved_position:
		player.global_position = RoomState.player_position
	elif RunState.current_node != RunState.opening_node:
		_play_walk_on_intro()

	# Every blob spawned above has already had its own _ready() run (see
	# field_blob.gd) and read whatever it needed from these two fields -
	# clearing them now, after all of that, resets them for next time
	# without racing anything. (add_child() runs a new child's _ready()
	# immediately, not on some later frame, so this is safe to do right
	# after _generate_room_contents() finishes.)
	RoomState.in_field_encounter = false
	RoomState.last_encountered_blob_id = ""

	_update_exit_lock()

# Arrival walk-on (DECIDED, Option B of the room-transition redesign - see
# the "Room Transition" export group's own header above). Skipped for the
# opening room (she's placed by _apply_opening_room_layout()'s own hand-
# authored beat, not a travel arrival) and for a same-room return trip
# (RoomState.has_saved_position - the player never left this room, so
# there's nothing to walk "into" - see the call site above). Rewinds the
# player from wherever the normal spawn logic already placed them (spawn_x,
# read AFTER every other positioning branch above has already run) back by
# walk_on_offset_px, then walks them forward again under scripted control -
# player.input_locked + move_to(), never a position tween (see player.gd's
# own input_locked doc: footsteps are driven off `direction` in
# _physics_process(), which only a real move_to() call keeps alive) - so
# they're visibly mid-stride the moment the fade-in finishes, not found
# already standing still.
func _play_walk_on_intro() -> void:
	var spawn_x := player.position.x
	var start_x := maxf(spawn_x - walk_on_offset_px, ROOM_FLOOR_LEFT_X + WALK_ON_SAFETY_CLEARANCE_PX)
	if start_x >= spawn_x:
		return # walk_on_offset_px tuned to 0, or clamped away entirely near the left wall - nothing to walk.
	player.position.x = start_x
	player.input_locked = true
	player.scripted_speed = walk_on_speed
	player.move_to(spawn_x)
	await player.destination_cleared
	player.scripted_speed = -1.0
	player.input_locked = false

# Instantiates whatever RoomState.room_layout describes. Doesn't decide
# anything about WHAT should be here - see room_state.gd's
# _generate_layout() for that; this just builds what it's told.
func _generate_room_contents() -> void:
	for entry in RoomState.room_layout:
		match entry["kind"]:
			"blob":
				_spawn_blob(entry["position"], entry["id"], entry.get("enemy"), entry.get("encounter"), entry.get("wander", false))
			"chest":
				_spawn_chest(entry["position"], entry["chest_id"], entry["reward_kind"], entry.get("min_gold", 0), entry.get("max_gold", 0), entry.get("weapon_chance", 0.0), entry.get("prompt_text", ""), entry.get("belonging_texture"), entry.get("belonging_scale_multiplier", 1.0), entry.get("belonging_offset", Vector2.ZERO))
			"marker":
				_spawn_marker(entry["position"])
			"structure":
				_spawn_structure(entry["position"], entry["structure_id"])
			"npc":
				_spawn_npc(entry["position"], entry["npc_data"])
			"heap":
				_spawn_heap(entry["position"])
			"curio":
				_spawn_curio(entry["position"])
			"forge":
				_spawn_forge(entry["position"], entry["forge_id"])

# A combat blob is either a single enemy_data OR an authored encounter
# (see room_state.gd's _generate_combat_layout(), which sets exactly one
# of the two "enemy"/"encounter" keys per blob entry) - entry.get()
# rather than entry[] above so reading the key this blob DOESN'T have
# just returns null instead of erroring.
func _spawn_blob(spawn_position: Vector2, blob_id: String, enemy_data: EnemyData, encounter: EncounterData = null, wander: bool = false) -> void:
	var blob: Area2D = BLOB_SCENE.instantiate()
	# Set BEFORE add_child(): _ready() (which reads blob_id and
	# enemy_data/encounter_enemies, to pick its silhouette) fires the
	# instant the node enters the tree, so all of it has to already be
	# correct by then.
	blob.blob_id = blob_id
	blob.wander_enabled = wander
	if encounter != null:
		blob.encounter_enemies = encounter.enemies
		# field_preview() (see encounter_data.gd's own doc) - Twin
		# Glasswings/Wardling Solo fall through to encounter.enemies here
		# unchanged (field_preview_enemies is empty for both); Mushroom
		# Patch is the one case where this diverges from encounter_enemies
		# above, showing one silhouette for a three-enemy fight.
		blob.field_display_enemies = encounter.field_preview()
	else:
		blob.enemy_data = enemy_data
	blob.position = spawn_position
	content_root.add_child(blob)
	# Painted-preview visibility (2026-09-05, ground-elements pass) - a
	# blob's own silhouette is exactly the "irregular flat polygon shape"
	# class of visual this preview otherwise hides everywhere else (ground
	# patches/cracks/debris, vegetation) - see _painted_preview_decoration_
	# nodes' own doc for why hiding the WHOLE node (not just its visual
	# child) is still safe here: Area2D collision/monitoring is completely
	# independent of .visible, so this doesn't touch whether the player can
	# still walk into it and start the fight - only whether it's drawn.
	_painted_preview_decoration_nodes.append(blob)

var _chests_in_room: Array[FieldChest] = []
# EVERY chest in the room now, not one (2026-08-29, three-chest treasure
# room - REPLACES the old singular _chest_in_room: Area2D). TREASURE's
# own three chests are the only reason this is ever more than 0-1 long
# today - COMBAT stopped spawning a chest at all in the 2026-08-29
# single-screen pass (see room_state.gd's own CHEST_CHANCE doc), so this
# array is empty for every OTHER room type, same as _chest_in_room being
# null always was for them. Set below by _spawn_chest(). Needed as a
# persistent reference (not just a local var within that function) so
# _dim_field_for_reward() can darken ALL of a room's chests while a
# chest-granted weapon's own pickup window is up - see additional_
# wanderer_dim's own doc - and so _on_any_chest_claimed() can foreclose
# every chest OTHER than the one just opened.

func _spawn_chest(spawn_position: Vector2, chest_id: String, reward_kind: FieldChest.RewardKind, min_gold: int, max_gold: int, weapon_chance: float, prompt_text: String, belonging_texture: Texture2D = null, belonging_scale_multiplier: float = 1.0, belonging_offset: Vector2 = Vector2.ZERO) -> void:
	var chest: FieldChest = CHEST_SCENE.instantiate()
	chest.chest_id = chest_id
	chest.reward_kind = reward_kind
	chest.min_gold = min_gold
	chest.max_gold = max_gold
	chest.weapon_drop_chance = weapon_chance
	chest.prompt_text = prompt_text
	chest.belonging_texture = belonging_texture
	chest.belonging_scale_multiplier = belonging_scale_multiplier
	chest.belonging_offset = belonging_offset
	chest.position = spawn_position
	chest.weapon_offered.connect(_on_chest_weapon_offered)
	chest.card_offered.connect(_on_chest_card_offered.bind(chest))
	chest.claimed.connect(_on_any_chest_claimed.bind(chest))
	click_to_move.register_interactable(chest)
	content_root.add_child(chest)
	_chests_in_room.append(chest)

# TREASURE's own exclusivity rule (2026-08-29) - fires the instant ANY
# chest in the room is opened (see FieldChest.claimed's own doc for why
# this reads off THAT signal, not off weapon_offered/card_offered/the
# gold grant): every OTHER chest in the room immediately, permanently
# stops being interactive (see FieldChest.close_permanently()), and the
# room's own exit unlocks (_update_exit_lock() already knows how to read
# RoomState.chest_opened for a TREASURE room - see that function's own
# TREASURE branch - this just re-runs it NOW rather than waiting for a
# reload that TREASURE never gets, since defeating a blob normally
# reloads field_room.tscn fresh, which is the ONLY other place this
# function is called from).
func _on_any_chest_claimed(opened_chest: FieldChest) -> void:
	for other in _chests_in_room:
		if other != opened_chest:
			other.close_permanently()
	_update_exit_lock()

var _pending_chest_weapon: WeaponData = null
# Which weapon a chest just offered, if any - set right before opening
# weapon_pickup_window, read (and cleared) once its own `resolved` signal
# fires. STILL room-level, not per-chest, even after the three-chest
# treasure room (2026-08-29): exactly one chest per room can ever be
# WEAPON-kind (see room_state.gd's own _generate_treasure_layout() -
# Chest C, always) by construction, so there is structurally still at
# most one weapon offer in flight at a time - the singular shape here
# was never actually violated by adding Chest A/B alongside it, only
# _chest_in_room (renamed _chests_in_room above) and RoomState.chest_
# opened (see its own doc) were.

# DECIDED (2026-08-29, prompt-first interaction pass) - the room's own
# exclusivity (the other two chests foreclosed, RoomState.chest_opened
# set, exit unlocked) has ALREADY happened by the time this ever runs -
# see field_chest.gd's own _on_take_pressed(), which fires FieldChest.
# claimed (and this signal) in that order, both before weapon_pickup_
# window ever opens. So pressing Leave INSIDE weapon_pickup_window below
# only ever decides whether the weapon gets EQUIPPED (see _on_chest_
# weapon_pickup_resolved()) - it can NOT re-open the other two chests or
# re-lock the exit. Pressing Take at Chest C's own prompt was the actual
# commitment ("opening it was the commitment," not "walking away with
# nothing equipped means it never happened") - consistent with how this
# same window already behaves everywhere else it's used (a weapon is
# always already found/granted the instant the window opens; its own
# Take/Leave has never meant "give the discovery back").
func _on_chest_weapon_offered(weapon_data: WeaponData) -> void:
	_pending_chest_weapon = weapon_data
	_dim_field_for_reward()
	weapon_pickup_window.open_reward(weapon_data, RunState.equipped_weapon)

# Mirrors reward_screen.gd's own _on_weapon_pickup_resolved() for the
# non-chest-row case (a chest's weapon here is never a reclaimable row -
# there's no loot list at all any more, see field_chest.gd's own header) -
# same "equip if taken, log either way" shape, just without anything left
# to remove from a list.
func _on_chest_weapon_pickup_resolved(equipped: bool) -> void:
	if equipped:
		RunState.equipped_weapon = _pending_chest_weapon
		AudioManager.play_sfx("weapon_equipped")
	RunLogger.log_reward_offered("Weapon", [_pending_chest_weapon.weapon_name], _pending_chest_weapon.weapon_name if equipped else "")
	_pending_chest_weapon = null
	_undim_field_for_reward()

var _chest_offer_card: Card = null
var _chest_offer_card_wrapper: Node2D = null
# Chest B's own floating card (2026-08-29, three-chest treasure room) -
# the SAME in-field presentation TECHNIQUE the Keeper's own offer card
# uses (CARD_SCENE, instantiate -> set_scale_factor(1.0) -> set_card_
# data() -> connect card_clicked, faded in via modulate:a - see _show_
# npc_offer_card()'s own doc for why that EXACT ordering matters: an
# earlier version of her own function got this wrong and crashed).
# Deliberately NOT a third caller of that function, or a shared helper
# extracted out of it: her own version carries real NPC-specific state
# this doesn't need (proximity re-show/hide across repeated approaches,
# hover-expansion-away-from-her direction math, a pick that has to
# survive a walk-away/return) - a chest opens exactly once, ever, and
# the card that appears is exactly as final as the gold number Chest A
# already grants on contact. Reaching into her already-fragile,
# already-debugged function for a marginal reuse win risked regressing
# the one interaction this room isn't supposed to touch - a smaller,
# separate function doing the same five steps is the safer trade,
# reported here rather than silently decided.
func _on_chest_card_offered(card_data: CardData, chest: FieldChest) -> void:
	var wrapper := Node2D.new()
	wrapper.scale = Vector2(treasure_card_scale, treasure_card_scale)
	wrapper.position = chest.position + treasure_card_offset
	content_root.add_child(wrapper)

	var card: Card = CARD_SCENE.instantiate()
	wrapper.add_child(card)
	card.set_scale_factor(1.0)
	card.set_card_data(card_data)
	card.position = -card.design_size / 2.0
	card.modulate.a = 0.0
	card.card_clicked.connect(_on_chest_offer_card_clicked)

	_chest_offer_card = card
	_chest_offer_card_wrapper = wrapper
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, treasure_card_fade_in_sec)

# The card's own click - REVISED (2026-08-29, prompt-first interaction
# pass): this is no longer the player's decline point. That moved to
# Chest B's own approach PROMPT (see field_chest.gd's Leave button) -
# pressing Take there is what actually commits (fires FieldChest.claimed,
# forecloses the other two, unlocks the exit - see _on_any_chest_
# claimed()), all BEFORE this card ever appears. By the time this card is
# on screen, taking it is the only outcome left; clicking it is the same
# accept GESTURE the Keeper's own card uses, not a second chance to back
# out - "once the overlay opens the card is taken," per this pass's own
# brief. mouse_filter = IGNORE immediately, before the fade-out even
# starts, same double-click guard _on_npc_offer_card_clicked() uses and
# for the same reason - belt-and-suspenders alongside the _chest_offer_
# card == null check above, which is what actually stops a second click
# from re-granting the card.
func _on_chest_offer_card_clicked(card_data: CardData) -> void:
	if _chest_offer_card == null:
		return
	RunState.add_card_to_deck(card_data)
	# Same "add_card" cue the Keeper's own card handover plays (see
	# _on_npc_offer_card_clicked() below) - a card genuinely entering the
	# deck reads the same regardless of which field feature granted it.
	# The Keeper's OWN call stays completely separate (a distinct sound is
	# planned for her specifically later - see audio_manager.gd's own
	# add_card doc) - this is a second, independent call, not a shared
	# helper the two of them funnel through.
	AudioManager.play_sfx("add_card")
	deck_label.text = "Deck (%d)" % RunState.deck.size()
	var wrapper: Node2D = _chest_offer_card_wrapper
	var card: Card = _chest_offer_card
	_chest_offer_card = null
	_chest_offer_card_wrapper = null
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 0.0, treasure_card_fade_in_sec)
	tween.tween_callback(wrapper.queue_free)

# See additional_wanderer_dim/button_dim_opacity's own doc for why these
# three targets need field_room.gd's own targeted dimming on top of
# weapon_pickup_window.gd's shared world wash. Chest and player are
# darkened via modulate (same R/G/B, alpha left at 1) rather than alpha -
# a WORLD sprite fading toward transparent would let the background show
# through it, reading as vanishing rather than receding into shadow (the
# same "darken, don't fade" reasoning field_chest.gd's own opened_color
# is built around, just applied here as a multiply instead of a second
# baked color). Deck/Map are real UI Controls, where an alpha fade IS the
# correct, standard "temporarily inert" language - see button_dim_
# opacity's own doc. .disabled is set too, defensive rather than load-
# bearing: weapon_pickup_window's own get_tree().paused = true (see its
# open_reward()) already stops these buttons' input from reaching them,
# the same way MapScreen's own class doc explains pause already blocks
# field movement - this just guarantees it rather than relying on that
# alone.
#
# Chest OfferPrompt / NPC offer_label hidden outright now too (2026-08-31,
# two-live-decisions fix), not just dimmed - a weapon reward is a real
# modal decision (get_tree().paused = true), and a chest's own Take/Leave
# prompt sitting there fully readable underneath it read as a second,
# still-live decision, not scenery. Toggling `.visible` directly rather
# than going through hide_offer()/_fade_prompt_to() is deliberate: those
# drive the SAME `modulate:a` an in-flight approach/leave/take fade might
# already be mid-tween on, and fighting that tween from here would either
# get overwritten by it or leave it visibly restarting once undimmed.
# `.visible` is orthogonal to modulate - flipping it off freezes whatever
# fade is already running (or not running) exactly where it is, and
# flipping it back on later resumes that same state with nothing to
# reconcile. Every chest/NPC in the room, not just whichever one granted
# this reward - same "all of them, not just the active one" breadth the
# modulate dimming above already uses, for the same reason (a sibling
# chest's own prompt could in principle still be showing too).
func _dim_field_for_reward() -> void:
	var wanderer_dim: float = 1.0 - (weapon_pickup_window.backdrop.color.a + additional_wanderer_dim)
	player.modulate = Color(wanderer_dim, wanderer_dim, wanderer_dim, 1.0)
	var chest_dim: float = 1.0 - weapon_pickup_window.backdrop.color.a
	for chest in _chests_in_room:
		chest.modulate = Color(chest_dim, chest_dim, chest_dim, 1.0)
		chest.offer_prompt.visible = false
	for npc in _npcs_in_room:
		npc.offer_label.visible = false
	deck_button.modulate.a = button_dim_opacity
	map_button.modulate.a = button_dim_opacity
	deck_label.modulate.a = button_dim_opacity
	map_label.modulate.a = button_dim_opacity
	deck_button.disabled = true
	map_button.disabled = true

func _undim_field_for_reward() -> void:
	player.modulate = Color.WHITE
	for chest in _chests_in_room:
		chest.modulate = Color.WHITE
		chest.offer_prompt.visible = true
	for npc in _npcs_in_room:
		npc.offer_label.visible = true
	deck_button.modulate.a = 1.0
	map_button.modulate.a = 1.0
	deck_label.modulate.a = 1.0
	map_label.modulate.a = 1.0
	deck_button.disabled = false
	map_button.disabled = false

# --- Field HUD icon buttons (2026-09-05, Deck/Map icon pass - REPLACES
# the old plain-text DeckButton/MapButton Buttons with TextureButton +
# Label pairs; see field_room.tscn's own DeckButton/DeckLabel/MapButton/
# MapLabel nodes) ---
#
# Sizes the button to hud_icon_height_px while preserving the SOURCE
# texture's own aspect ratio (Deck.png and Map.png are cropped to their
# opaque content bounds already - see each file's own history - so their
# aspect ratios are meaningful, not arbitrary), positions the label
# directly beneath it at a fixed slot (independent of hud_icon_height_px,
# so retuning icon size never fights the label's own position), and
# applies this project's system-voice register (default sans, no Spectral
# override - see run_hud.gd's own two-register doc) at hud_icon_label_
# font_size_px's own independent size (2026-09-05, label-legibility pass
# - see its own doc for why this stopped reading run_hud.compact_value_
# font_size_px), colored via hud_icon_label_color (2026-09-05, plain-
# white pass - REPLACES HudPalette.SYSTEM_TEXT + OverlayStyle's outline;
# see that export's own doc for why).
#
# Caller sets button.offset_left/label.offset_left BEFORE calling this
# (see _ready() below) - this function reads them as given rather than
# owning left-edge placement itself, since MapButton's own offset_left is
# derived from DeckButton's own already-configured offset_right (see
# hud_icon_gap_px's own doc), which only exists once Deck's OWN call to
# this same function has already run.
func _configure_hud_icon_button(button: TextureButton, label: Label) -> void:
	var tex_size: Vector2 = button.texture_normal.get_size()
	var width_px: float = hud_icon_height_px * (tex_size.x / tex_size.y)
	# The icon's own offset_bottom stays exactly as baked in field_room.
	# tscn - only the height (hud_icon_height_px, tunable) and the width
	# it implies (this texture's own aspect ratio, not a second exported
	# number - see hud_icon_height_px's own doc) ever need recomputing
	# here. The icon grows/shrinks UPWARD from its fixed bottom edge, so
	# the label's own position underneath it never has to move.
	button.offset_right = button.offset_left + width_px
	button.offset_top = button.offset_bottom - hud_icon_height_px
	label.offset_right = label.offset_left + width_px
	label.add_theme_font_size_override("font_size", hud_icon_label_font_size_px)
	label.add_theme_color_override("font_color", hud_icon_label_color)
	button.pivot_offset = Vector2(width_px, hud_icon_height_px) / 2.0
	button.mouse_entered.connect(_on_hud_icon_mouse_entered.bind(button))
	button.mouse_exited.connect(_on_hud_icon_mouse_exited.bind(button))
	button.button_down.connect(_on_hud_icon_button_down.bind(button))
	button.button_up.connect(_on_hud_icon_button_up.bind(button))

func _on_hud_icon_mouse_entered(button: TextureButton) -> void:
	if button.disabled:
		return
	_tween_hud_icon_scale(button, hud_icon_hover_scale)

func _on_hud_icon_mouse_exited(button: TextureButton) -> void:
	if button.disabled:
		return
	_tween_hud_icon_scale(button, 1.0)

func _on_hud_icon_button_down(button: TextureButton) -> void:
	_tween_hud_icon_scale(button, hud_icon_press_scale)

func _on_hud_icon_button_up(button: TextureButton) -> void:
	var hovered: bool = button.get_global_rect().has_point(button.get_global_mouse_position())
	_tween_hud_icon_scale(button, hud_icon_hover_scale if hovered else 1.0)

func _tween_hud_icon_scale(button: TextureButton, target_scale: float) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(target_scale, target_scale), hud_icon_scale_tween_sec)

# Which exterior .tscn to instantiate for a given structure_id - the
# structure's own instance already carries its structure_id/interior_
# scene (see field_structure.gd), so this only has to pick the right
# scene, not configure anything else. Unknown structure_id -> nothing
# spawned rather than an error, same defensive stance _spawn_blob()'s own
# entry.get() calls take elsewhere in this function.
func _spawn_structure(spawn_position: Vector2, structure_id: String) -> void:
	var scene: PackedScene
	match structure_id:
		"pay_house":
			scene = PAY_HOUSE_SCENE
		_:
			return
	var structure: Area2D = scene.instantiate()
	structure.position = spawn_position
	click_to_move.register_interactable(structure)
	content_root.add_child(structure)

func _spawn_marker(spawn_position: Vector2) -> void:
	var marker: Area2D = MARKER_SCENE.instantiate()
	marker.marker_room_type = RoomState.current_room_type
	marker.position = spawn_position
	marker.shop_entered.connect(shop_window.open_shop)
	click_to_move.register_interactable(marker)
	content_root.add_child(marker)

# Same shape as _spawn_marker() above, plus the NPC-specific wiring this
# feature's own brief asks for: npc_entered/npc_exited decide whether her
# offer text shows (see _on_npc_entered()/_on_npc_exited() below), and
# clicks route through the DEDICATED _on_npc_clicked() rather than
# click_to_move.register_interactable() (see that function's own note on
# why) - she's the one interactable that doesn't walk-and-fire onto her
# own exact position.
func _spawn_npc(spawn_position: Vector2, npc_data: NPCData) -> void:
	var npc: Area2D = NPC_SCENE.instantiate()
	npc.npc_data = npc_data
	npc.position = spawn_position
	npc.npc_entered.connect(_on_npc_entered.bind(npc))
	npc.npc_exited.connect(_on_npc_exited.bind(npc))
	npc.input_event.connect(_on_npc_clicked.bind(npc))
	content_root.add_child(npc)
	_npcs_in_room.append(npc)

# Offer her line AND her card on contact, UNLESS RunState.npc_interacted
# already has her (accepted earlier this run) - in which case she shows
# a SEPARATE post-interaction line instead (2026-08-27; "show nothing"
# was this project's own original choice here, superseded by this pass's
# own brief) and no card, every time she's re-approached, not just once.
# _npc_in_contact is left null in that branch on purpose - there's
# nothing left to accept, so a click on her should just walk to her like
# any other interactable (see _on_npc_clicked()'s own walk-vs-stop
# branch), not be gated by contact tracking that no longer means
# anything once she's resolved.
func _on_npc_entered(npc: Area2D) -> void:
	if RunState.npc_interacted.get(npc.npc_data.npc_id, false):
		npc.show_offer(npc.npc_data.post_interaction_text)
		return
	_npc_in_contact = npc
	npc.show_offer(npc.npc_data.dialogue_text)
	_show_npc_offer_card(npc)

# Walking away without accepting leaves her available - clearing _npc_in_
# contact (only if SHE was the one being tracked; harmless no-op
# otherwise) is what makes her re-offer on the next approach, since
# _on_npc_entered() above runs fresh every time body_entered fires again.
# Both hide_offer() and _hide_npc_offer_card() run unconditionally,
# regardless of which line (or none) was showing: hide_offer() correctly
# fades out whichever text is CURRENTLY on screen - the pre- or post-
# interaction line, it doesn't need to know which - and _hide_npc_offer_
# card() is a genuine no-op once she's resolved (no card ever shows in
# that case - see _on_npc_entered()'s own already-interacted branch), not
# worth a separate check to skip.
func _on_npc_exited(npc: Area2D) -> void:
	if _npc_in_contact == npc:
		_npc_in_contact = null
	npc.hide_offer()
	_hide_npc_offer_card(npc)

# Lazily builds the ONE card instance the first time she has something to
# offer, then just re-fades it on every later approach - see _npc_offer_
# card's own doc for why this persists instead of destroy-and-recreate.
# Follows this feature's own investigation report's reuse pattern
# exactly (instantiate() -> set_scale_factor() -> set_card_data() ->
# connect card_clicked) - card.gd itself needed no changes, the same
# self-contained Control reward_screen.gd/shop_window.gd/deck_viewer.gd
# already reuse outside battle. Hover feedback is left fully enabled
# (mouse_filter untouched, unlike shop/reward's own static previews) -
# this one is clickable, and the reward-screen-style hover lift is the
# right affordance for "this is the thing you take," per the brief.
#
# set_scale_factor(1.0) ALWAYS - never npc_offer_card_scale (2026-08-27,
# proportions fix). The card is laid out at full, correctly-proportioned
# hand-card size every time; npc_offer_card_scale instead drives _npc_
# offer_card_wrapper's own uniform `scale` (see that var's own doc for
# why it has to live one level outside the card, not on set_scale_
# factor() or on `visual`). Card.position is set ONCE, to -design_size/2
# (half its own UNSCALED size) - centering the card's rendered origin on
# the wrapper's own local (0,0), so scaling the wrapper scales symmetric
# around the card's visual CENTER rather than its top-left corner.
#
# The wrapper itself is positioned as a child of content_root (a SIBLING
# of the NPC, not nested inside her own scene - see this feature's own
# brief), its own CENTER at (npc_offer_card_x_offset, npc_offer_card_
# y_offset) from her own Area2D origin - offset in BOTH axes (the
# original version only offset Y, implicitly centering X on her, which
# is exactly what put the card on top of her). content_root has no
# scale/rotation of its own and the field camera runs at zoom 1.0
# (confirmed in this feature's own investigation report), so this
# composes to the exact same on-screen envelope the old direct-on-Card
# positioning produced at the same scale value - only what renders
# INSIDE that envelope changed. RoomState.field_zoom (2026-09-06,
# field-pull-back pass) breaks that "zoom 1.0" assumption - at any other
# zoom this card renders smaller/larger than tuned. Left as-is on
# purpose for this pass; see this pass's own report.
func _show_npc_offer_card(npc: Area2D) -> void:
	if _npc_offer_card == null:
		# Wrapper enters the tree FIRST, then the card is added as ITS
		# child, before set_scale_factor()/set_card_data() ever touch it
		# - card.gd's own @onready vars (visual, frame, zones, name_
		# label, ...) only become valid once a Card is actually inside
		# the SceneTree (Godot runs _ready() the instant add_child()
		# puts a node in a live tree, not at instantiate() time).
		# Calling set_scale_factor()/set_card_data() BEFORE that point -
		# the original, broken order of this block - hits every one of
		# those onready vars as null, and a null-crash partway through
		# _update_display()/_apply_layout() means later lines in the
		# SAME call (the name/cost text, rarity border, art texture)
		# never run at all and are never retried - _ready()'s own later
		# _apply_layout() call fixes layout/fonts on its own, but never
		# re-invokes set_card_data(), so a card built in the wrong order
		# would silently keep showing card.tscn's own placeholder name/
		# cost forever. Confirmed via a real script-error crash while
		# verifying this fix, not caught by inspection alone.
		_npc_offer_card_rest_position = npc.position + Vector2(npc_offer_card_x_offset, npc_offer_card_y_offset)
		_npc_offer_card_wrapper = Node2D.new()
		_npc_offer_card_wrapper.scale = Vector2(npc_offer_card_scale, npc_offer_card_scale)
		_npc_offer_card_wrapper.position = _npc_offer_card_rest_position
		content_root.add_child(_npc_offer_card_wrapper)

		# Rolled here, not before - this is the exact moment the card
		# node itself is first built for this visit, so the pick and the
		# node's own lifetime start and persist together (see _npc_offer_
		# picked_card's own doc for why that's what makes the pick stable
		# across a walk-away/return without any separate tracking).
		_npc_offer_picked_card = npc.npc_data.granted_cards.pick_random()

		_npc_offer_card = CARD_SCENE.instantiate()
		_npc_offer_card_wrapper.add_child(_npc_offer_card)
		_npc_offer_card.set_scale_factor(1.0)
		_npc_offer_card.set_card_data(_npc_offer_picked_card)
		_npc_offer_card.card_clicked.connect(_on_npc_offer_card_clicked.bind(npc))
		_npc_offer_card.position = -_npc_offer_card.design_size / 2.0
		_npc_offer_card.modulate.a = 0.0
		# mouse_entered/mouse_exited are Control's own built-in signals -
		# the exact same ones card.gd's own _on_mouse_entered()/_on_mouse_
		# exited() already listen to internally for `visual`'s own hover
		# pop (2026-08-27, hover-expansion pass). Observing them here too
		# adds the wrapper's own expansion on the SAME trigger, without
		# touching card.gd or needing any new signal/public API on it.
		_npc_offer_card.mouse_entered.connect(_on_npc_offer_card_hover_changed.bind(true))
		_npc_offer_card.mouse_exited.connect(_on_npc_offer_card_hover_changed.bind(false))
	if _npc_offer_card_tween:
		_npc_offer_card_tween.kill()
	_npc_offer_card_tween = create_tween()
	# The delay is what makes the text read as "first," not a race
	# between two things fading in at once - per this feature's own
	# brief. The fade-in DURATION itself reuses npc.offer_fade_in_sec
	# (field_npc.gd) rather than a second export - "reuse the existing
	# fade timing approach," taken literally. Still fades the CARD's own
	# modulate, not the wrapper's - modulate is a plain color/alpha
	# multiply, unaffected by the wrapper's transform either way.
	_npc_offer_card_tween.tween_interval(npc_offer_card_delay_sec)
	_npc_offer_card_tween.tween_property(_npc_offer_card, "modulate:a", 1.0, npc.offer_fade_in_sec)

func _hide_npc_offer_card(npc: Area2D) -> void:
	if _npc_offer_card == null:
		return
	if _npc_offer_card_tween:
		_npc_offer_card_tween.kill()
	_npc_offer_card_tween = create_tween()
	_npc_offer_card_tween.tween_property(_npc_offer_card, "modulate:a", 0.0, npc.offer_fade_out_sec)
	# Snap the wrapper's own scale/position back to rest, regardless of
	# hover state (2026-08-27, hover-expansion pass) - walking away while
	# the mouse happens to still be over the card's own screen rect is a
	# real, reachable case (camera panning usually slides the card out
	# from under a stationary cursor on its own, naturally firing mouse_
	# exited, but that's incidental, not guaranteed for every way a
	# player can leave). Without this, a card faded out mid-hover would
	# silently re-appear at the wrong scale/position on the next
	# approach, since _show_npc_offer_card() only re-fades modulate, it
	# doesn't reset the wrapper's own transform.
	if _npc_offer_card_hover_tween:
		_npc_offer_card_hover_tween.kill()
	_npc_offer_card_wrapper.scale = Vector2(npc_offer_card_scale, npc_offer_card_scale)
	_npc_offer_card_wrapper.position = _npc_offer_card_rest_position

# Expands the wrapper toward npc_offer_card_hover_multiplier on hover,
# back to rest on un-hover (2026-08-27, hover-expansion pass) - smooth,
# not a snap, via the SAME tween-based approach card.gd's own hover
# already uses, reusing its exact hover_duration (not a new export -
# "reuse the existing hover tween timing," per this pass's own brief).
#
# Grows AWAY from her, not into her sprite, per this pass's own brief:
# the card's NEAR edge (whichever side faces her - see the direction
# math below) stays FIXED at its rest position; only the FAR edge (and
# therefore the wrapper's own center) moves as the scale grows. Y stays
# centered on the rest position - nothing adjacent above or below her
# figure band needs the same treatment.
#
# The near/far side isn't hardcoded - signf(npc_offer_card_x_offset)
# reads which side of her the card was placed on (negative: card left
# of her, near edge = her-facing RIGHT edge; positive: card right of
# her, near edge = LEFT edge), the same "the direction lives in the
# offset value, not the code" principle that export's own doc already
# establishes. Deriving the near edge from _npc_offer_card_rest_
# position (not the wrapper's CURRENT position, which may be mid-tween)
# is what keeps repeated hover/un-hover cycles from drifting - each one
# recomputes from the same fixed rest anchor rather than compounding
# off wherever the last animation left off.
func _on_npc_offer_card_hover_changed(is_hovered: bool) -> void:
	if _npc_offer_card_wrapper == null:
		return
	var target_scale: float = npc_offer_card_scale * npc_offer_card_hover_multiplier if is_hovered else npc_offer_card_scale
	var direction: float = signf(npc_offer_card_x_offset)
	if direction == 0.0:
		direction = -1.0
	var half_width: float = _npc_offer_card.design_size.x / 2.0
	var near_edge_x: float = _npc_offer_card_rest_position.x - direction * half_width * npc_offer_card_scale
	var target_center_x: float = near_edge_x + direction * half_width * target_scale
	var target_position := Vector2(target_center_x, _npc_offer_card_rest_position.y)

	if _npc_offer_card_hover_tween:
		_npc_offer_card_hover_tween.kill()
	_npc_offer_card_hover_tween = create_tween()
	_npc_offer_card_hover_tween.set_parallel(true)
	_npc_offer_card_hover_tween.tween_property(_npc_offer_card_wrapper, "scale", Vector2(target_scale, target_scale), _npc_offer_card.hover_duration)
	_npc_offer_card_hover_tween.tween_property(_npc_offer_card_wrapper, "position", target_position, _npc_offer_card.hover_duration)

# NPCs get their own click handler instead of the shared _on_interactable_
# clicked() above: every other interactable's click ALWAYS means "walk to
# it" (the interaction itself fires from arrival, via body_entered), but
# a click on her - while she's already approached - shouldn't walk the
# player anywhere (they're already there), and no longer accepts either
# (see _on_npc_offer_card_clicked() below - accepting is the CARD's own
# click now, not hers). This keeps the walk-to behavior _on_interactable_
# clicked() already establishes fully intact for the "not yet in
# contact" case, rather than bolting a card-shaped concern onto the
# shared function every OTHER interactable would then have to be provably
# unaffected by.
#
# The "not in contact" branch stops SHORT of her (2026-08-27, "don't
# stand on top of her" fix) - every other interactable walks to its own
# exact position because there's nothing wrong with standing on a chest
# or a door, but landing dead-center on an NPC put both figures in the
# same space, the same problem the widened trigger (see field_npc.gd's
# own trigger_width_px) fixes for a KEYBOARD approach. approach_stop_
# distance_px is read straight off the clicked npc (her own per-NPC
# tunable, not a field_room.gd constant) and applied on whichever side
# of her the player already happens to be standing, so a click from
# either direction stops at a mirrored, equally-clear distance rather
# than always overshooting to one fixed side.
func _on_npc_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, npc: Area2D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if npc != _npc_in_contact:
		var approach_direction: float = signf(player.global_position.x - npc.global_position.x)
		if approach_direction == 0.0:
			approach_direction = 1.0
		var stop_x: float = npc.global_position.x + approach_direction * npc.approach_stop_distance_px
		player.move_to(clampf(stop_x, ROOM_FLOOR_LEFT_X, _room_floor_right_x()))
	get_viewport().set_input_as_handled()

# The card's own click - this IS the accept now, not a click on her (see
# _on_npc_clicked() above). Fires through Card's own _gui_input(), the
# same Control-level click path reward_screen.gd/deck_viewer.gd already
# connect card_clicked through - confirmed (this feature's own
# investigation report) to never reach _unhandled_input()'s ground-click-
# to-move or the NPC's own Area2D input_event, so no "is this a walk
# click or a card click" disambiguation was needed here at all.
#
# mouse_filter is set to IGNORE immediately, before the fly-away even
# starts, specifically so a second click mid-flight can't fire this a
# second time and double-grant the card - belt-and-suspenders alongside
# the npc_interacted check below (which guards the same thing for any
# OTHER path that could theoretically reach this twice).
#
# No confirmation step - granting the card and marking her resolved IS
# the whole accept, matching this feature's own brief. Clearing _npc_in_
# contact and fading her text out immediately gives instant feedback
# (the offer visibly resolves the moment it's taken) rather than waiting
# for the player to walk off before it updates. deck_button's own label
# is refreshed here too - _ready()'s own comment on it being "a one-time
# set" stopped being true the moment deck composition could change
# mid-room, which this feature is the first thing to do.
func _on_npc_offer_card_clicked(_card_data: CardData, npc: Area2D) -> void:
	if RunState.npc_interacted.get(npc.npc_data.npc_id, false):
		return
	RunState.add_card_to_deck(_npc_offer_picked_card)
	RunState.npc_interacted[npc.npc_data.npc_id] = true
	AudioManager.play_sfx("add_card")
	deck_label.text = "Deck (%d)" % RunState.deck.size()
	if _npc_in_contact == npc:
		_npc_in_contact = null
	npc.hide_offer()

	var card: Card = _npc_offer_card
	var wrapper: Node2D = _npc_offer_card_wrapper
	_npc_offer_card = null
	_npc_offer_card_wrapper = null
	_npc_offer_picked_card = null
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _npc_offer_card_tween:
		_npc_offer_card_tween.kill()
	if _npc_offer_card_hover_tween:
		# Clicked mid-hover (the common case - reading the card is what
		# hovering it was for) would otherwise leave the hover-expansion
		# tween still running, fighting the fly-away tween below over the
		# exact same wrapper.scale/position properties.
		_npc_offer_card_hover_tween.kill()
	# "Toward the bottom of the screen where the deck lives" (this
	# feature's own brief) - deck_button lives in the UI CanvasLayer,
	# whose children render in raw viewport pixels regardless of camera
	# position (a CanvasLayer's own transform is independent of the main
	# Camera2D). The card itself is still world-space content_root
	# content (via the wrapper), so its target is computed ONCE by
	# mapping deck_button's own screen position back through the INVERSE
	# of the active camera's canvas transform - the one-shot conversion
	# that lets the wrapper's own `position` tween stay in its native
	# world space rather than needing to be reparented into the UI layer
	# for this one animation.
	#
	# Animates the WRAPPER now, not the card directly (2026-08-27,
	# proportions fix) - the card's own `position`/`scale` are local to
	# the wrapper's already-scaled space, so tweening them here would
	# move/shrink the card by a fraction of what's intended (npc_offer_
	# card_scale's own factor compounding into the animation). Shrinking
	# the wrapper's OWN scale further (to 15% of whatever it currently
	# is, preserving the exact same "shrink to 15%" intent the original
	# single-node version had) and moving its OWN position both stay in
	# world space, where world_target above actually lives.
	var world_target: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * deck_button.get_global_transform_with_canvas().origin
	var fly_tween := create_tween()
	fly_tween.set_parallel(true)
	fly_tween.tween_property(wrapper, "position", world_target, npc_offer_card_accept_duration_sec)
	fly_tween.tween_property(wrapper, "scale", wrapper.scale * 0.15, npc_offer_card_accept_duration_sec)
	fly_tween.tween_property(card, "modulate:a", 0.0, npc_offer_card_accept_duration_sec)
	fly_tween.chain().tween_callback(wrapper.queue_free)

# --- Wreckage heap (2026-08-28, wreckage-heap room v1; choice-not-
# contact pass, same day) ---
#
# Same contact-trigger/click-dispatch split as the NPC block above (reused
# directly, per this feature's own brief - not refactored into a shared
# abstraction this commit): body_entered/exited show/hide her world-voice
# prompt, and a click on the PILE ITSELF routes through a dedicated
# handler. UNLIKE the NPC (and unlike this heap's own first version),
# a click while already in contact is now a no-op here, not a resolved
# interaction - Sift/Leave are real Buttons living inside field_heap.gd's
# own OfferPrompt now (see that file's own header for why its single-
# Label pattern resisted a two-option choice), each handling its own
# click directly. This handler's only remaining job is "walk toward it if
# not yet in contact" - _heap_in_contact still needs tracking for that
# one check, even though it no longer gates a pull.
var _heap_in_contact: Area2D = null

@export var heap_min_wall_clearance_px: float = 150.0
# X-position safety clamp (2026-08-28, large-pile pass) - RoomState's own
# _generate_heap_layout() picks a position through the SAME _place_
# content_positions() every other content type uses, which reasons about
# a POINT, never an item's own visual/trigger EXTENT (see its own doc:
# "one flat min_separation_px... not per-type math"). That was never a
# problem for a chest/blob/NPC, all far smaller than the room's own
# entrance/exit clearance margins - but the heap's OWN valid placement
# zone (about 1296px wide at the standard room width) was narrower than
# its own visual footprint AT THE SIZE this clamp was originally written
# against (1320px, 6x the original - since corrected down to 660px, 3x -
# see field_heap.gd's own heap_trigger_width_px doc, renamed from heap_
# width_px in the 2026-09-01 staged-dune pass), so the raw position
# RoomState handed back could legally sit close enough to either wall
# that the pile's own trigger zone clipped past it entirely (confirmed
# headlessly at the time). Rather than teach the general placement
# system about per-item extents for one outsized content type, this
# clamps the heap's own rendered position here, in the one place that
# already knows both the room's true walls (ROOM_FLOOR_LEFT_X/_room_
# floor_right_x()) and the heap's own footprint (heap_trigger_width_px/
# trigger_width_px, read directly off the instance, so this clamp adapts
# automatically to whatever size the pile is currently tuned to) - see
# _spawn_heap() below. heap_min_wall_clearance_px is real walkable margin
# left on the clamped side, not just "stop short of literally overlapping
# the wall" (a zero-margin clamp would still leave no room to walk past).
# Re-verified headlessly at the current 660px size - still appropriate,
# and the clamp itself now almost never needs to engage at all (see this
# pass's own report for the exact numbers).
func _spawn_heap(spawn_position: Vector2) -> void:
	var heap: Area2D = HEAP_SCENE.instantiate()
	heap.sift_outcome_table = HEAP_SIFT_OUTCOME_TABLE
	# Same cross-reference shape shop_window.gd's own deck_viewer already
	# gets from THIS function's own sibling setup (2026-09-04, weighted-
	# grant pass) - the heap's own GRANT_CARD offer flies a taken
	# card toward this exact button on accept (see field_heap.gd's own
	# _play_grant_card_reveal()), the same "toward the bottom of the screen
	# where the deck lives" destination the Keeper's own offer card already
	# flies to.
	heap.deck_button = deck_button
	heap.deck_label = deck_label
	# heap_trigger_width_px/trigger_width_multiplier (renamed from heap_
	# width_px 2026-09-01, staged-dune pass - see that export's own doc)
	# are both already-set exports, valid immediately after instantiate()
	# - reading them here (rather than waiting for _ready() to compute
	# heap.trigger_width_px) avoids reordering this function's existing
	# "configure fully, then add_child()" convention just for this one
	# clamp.
	var half_footprint: float = heap.heap_trigger_width_px * maxf(1.0, heap.trigger_width_multiplier) / 2.0
	spawn_position.x = clampf(
		spawn_position.x,
		ROOM_FLOOR_LEFT_X + half_footprint + heap_min_wall_clearance_px,
		_room_floor_right_x() - half_footprint - heap_min_wall_clearance_px
	)
	heap.position = spawn_position
	heap.body_entered.connect(_on_heap_body_entered.bind(heap))
	heap.body_exited.connect(_on_heap_body_exited.bind(heap))
	heap.input_event.connect(_on_heap_clicked.bind(heap))
	content_root.add_child(heap)

func _on_heap_body_entered(body: Node2D, heap: Area2D) -> void:
	if body is Player:
		_heap_in_contact = heap

func _on_heap_body_exited(body: Node2D, heap: Area2D) -> void:
	if body is Player and _heap_in_contact == heap:
		_heap_in_contact = null

# field_heap.gd's own body_entered/body_exited already drive its offer
# prompt directly (see its _on_body_entered()/_on_body_exited()) - this
# room-level pair only needs to track WHICH heap the player is currently
# standing in, for _on_heap_clicked() below to check. Clicking the pile
# while already in contact is deliberately a no-op now (2026-08-28,
# choice-not-contact pass) - the actual choice lives on field_heap.gd's
# own Sift/Leave Buttons, which handle their own clicks directly and
# never route through this Area2D-level handler at all.
func _on_heap_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, heap: Area2D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if heap != _heap_in_contact:
		var approach_direction: float = signf(player.global_position.x - heap.global_position.x)
		if approach_direction == 0.0:
			approach_direction = 1.0
		var stop_x: float = heap.global_position.x + approach_direction * heap.approach_stop_distance_px
		player.move_to(clampf(stop_x, ROOM_FLOOR_LEFT_X, _room_floor_right_x()))
	get_viewport().set_input_as_handled()

# --- Field curio (2026-08-28, second-event pass) ---
#
# Same contact-trigger/click-dispatch split as the heap block above -
# reused directly, not refactored into a shared abstraction with it
# (this project's own repeated "duplicate a proven shape" convention).
# A click on the curio itself only ever means "walk toward it" - the
# actual choice lives on field_curio.gd's own Investigate/Leave Buttons.
var _curio_in_contact: Area2D = null

func _spawn_curio(spawn_position: Vector2) -> void:
	var curio: Area2D = CURIO_SCENE.instantiate()
	curio.outcome_table = CURIO_OUTCOME_TABLE
	curio.position = spawn_position
	curio.body_entered.connect(_on_curio_body_entered.bind(curio))
	curio.body_exited.connect(_on_curio_body_exited.bind(curio))
	curio.input_event.connect(_on_curio_clicked.bind(curio))
	content_root.add_child(curio)

func _on_curio_body_entered(body: Node2D, curio: Area2D) -> void:
	if body is Player:
		_curio_in_contact = curio

func _on_curio_body_exited(body: Node2D, curio: Area2D) -> void:
	if body is Player and _curio_in_contact == curio:
		_curio_in_contact = null

func _on_curio_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, curio: Area2D) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if curio != _curio_in_contact:
		var approach_direction: float = signf(player.global_position.x - curio.global_position.x)
		if approach_direction == 0.0:
			approach_direction = 1.0
		var stop_x: float = curio.global_position.x + approach_direction * curio.approach_stop_distance_px
		player.move_to(clampf(stop_x, ROOM_FLOOR_LEFT_X, _room_floor_right_x()))
	get_viewport().set_input_as_handled()

# Same shape as _spawn_heap()'s own one-line instantiate-configure-add
# (2026-09-02, forge pass) - simpler still, since field_forge.gd owns its
# own contact/prompt/upgrade flow entirely (see its own class doc for why
# nothing here needs to listen to `upgraded` the way _spawn_chest() has
# to wire weapon_offered/card_offered/claimed for field_room.gd to react
# to).
func _spawn_forge(spawn_position: Vector2, forge_id: String) -> void:
	var forge: Area2D = FORGE_SCENE.instantiate()
	forge.forge_id = forge_id
	forge.position = spawn_position
	content_root.add_child(forge)

# Exactly one door, always - see the "ONE door only" note above for why
# this no longer tracks RunState.current_node.connections.size(). Step 1
# had this door temporarily pick the FIRST forward edge on its own;
# step 3 (DESIGN.md's field movement redesign: navigation redesign)
# replaces that placeholder for real - the door itself no longer decides
# anything, it just reports the player walked in (see _on_exit_entered()
# below, which plays the departure beat before opening the map in TRAVEL
# mode - see map_screen.gd's open_map_for_travel()), and picking a node
# there is what actually chooses the edge and loads the next room.
# A boss node has ZERO forward edges (the graph's terminal node) - still
# spawns nothing: there's no exit to take once the boss is beaten.
func _spawn_exits() -> void:
	var connections: Array[RunNode] = RunState.current_node.connections
	if connections.is_empty():
		return
	var door: Area2D = EXIT_SCENE.instantiate()
	door.position = Vector2(_exit_x(), RoomState.floor_line_y)
	door.exit_entered.connect(_on_exit_entered)
	click_to_move.register_interactable(door)
	exits_root.add_child(door)
	exits.append(door)

# Routes exit_entered through a departure beat instead of wiring it
# straight to open_map_for_travel() (2026-08-27, room-transition pass -
# see the "Room Transition" export group's own header). _leaving_room
# guards against a second call: the player's own body is what's inside the
# door's Area2D, and the scripted walk below moves them FURTHER INTO it
# (see departure_walk_distance_px's own doc) - without this guard, that
# could re-enter the trigger and fire exit_entered a second time mid-
# sequence. Never reset back to false: travel mode's own MapScreen offers
# no way to cancel once open (see map_screen.gd's own class doc), so this
# room's exit is only ever used once regardless.
var _leaving_room: bool = false

func _on_exit_entered() -> void:
	if _leaving_room:
		return
	_leaving_room = true
	player.input_locked = true
	if departure_walk_distance_px > 0.0:
		var target_x: float = minf(player.position.x + departure_walk_distance_px, _room_floor_right_x() - DEPARTURE_SAFETY_CLEARANCE_PX)
		if target_x > player.position.x:
			player.move_to(target_x)
			await player.destination_cleared
	_clear_opening_room_hull_line()
	map_screen.open_map_for_travel()

# Wraps map_screen.open_map_for_viewing() directly (2026-09-06, map-
# overlay fix - REPLACES the direct map_button.pressed.connect(map_
# screen.open_map_for_viewing) this used to be) so the hull line clears
# BEFORE the map opens and pauses the tree, same as the travel-map path
# in _on_exit_entered() above - see _clear_opening_room_hull_line()'s own
# doc for why this can't just be polled from _process() instead.
func _on_map_button_pressed() -> void:
	_clear_opening_room_hull_line()
	map_screen.open_map_for_viewing()

# DevRoomPicker's own setup (see that control's own onready doc above) -
# one item per RoomType.Kind, labeled with both the raw enum name (what a
# dev testing a specific room TYPE actually wants to read) and the
# player-facing flavor name from RoomType.display_name() (so it's still
# obvious which map-screen label each one corresponds to). Kind stored as
# each item's metadata rather than assumed to equal its index - Kind.
# values() already happens to enumerate 0..6 in declaration order today,
# but reading metadata back doesn't depend on that staying true.
# select(-1) leaves nothing chosen at all (no auto-jump on room load) -
# item_selected only fires on an actual user pick, never from add_item()
# or select() itself, so this is safe either way, but starting genuinely
# unselected reads more clearly as "pick one" than defaulting to whatever
# Kind.values()[0] happens to be.
func _populate_dev_room_picker() -> void:
	for kind in RoomType.Kind.values():
		dev_room_picker.add_item("%s (%s)" % [RoomType.Kind.keys()[kind], RoomType.display_name(kind)])
		dev_room_picker.set_item_metadata(dev_room_picker.item_count - 1, kind)
	dev_room_picker.select(-1)
	dev_room_picker.item_selected.connect(_on_dev_room_picker_item_selected)

# RoomState.load_room() is the exact same call map_screen.gd makes for a
# real map pick, arrived at here directly, skipping the map screen
# entirely - the same shortcut dev_encounter_picker.gd already takes to
# reach a battle directly instead of walking a real field first.
func _on_dev_room_picker_item_selected(index: int) -> void:
	var kind: RoomType.Kind = dev_room_picker.get_item_metadata(index)
	RoomState.load_room(kind)

# Called once, right after _spawn_exits() (needs `exits` already decided -
# see exit_haze_width_fraction's own doc for why this whole feature
# exists). A boss room (or any room with zero forward edges) spawns no
# door at all - exit_haze just stays hidden for that case, same "nothing
# to reach for, nothing shown" shape every other optional element here
# follows, rather than showing a haze band with nothing behind it to
# explain what it's for.
func _setup_exit_haze() -> void:
	exit_haze.visible = not exits.is_empty()
	if exits.is_empty():
		return
	exit_haze.anchor_left = 1.0 - exit_haze_width_fraction
	exit_haze.anchor_bottom = exit_haze_height_fraction
	var gradient := Gradient.new()
	var sky := SunkenWorksPalette.SKY_HORIZON
	gradient.set_color(0, Color(sky.r, sky.g, sky.b, 0.0))
	gradient.set_color(1, Color(sky.r, sky.g, sky.b, 1.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	exit_haze.texture = texture
	exit_haze.modulate.a = exit_haze_resting_alpha

# Opening room only (2026-09-06, positional world-voice pass) - a plain
# procedural Label, not a scene-authored node, since this is a one-off,
# single-room feature with no interaction to wire up (no buttons, no
# Area2D - see opening_room_hull_line_threshold_x's own doc for why this
# isn't the usual heap-shape contact prompt). Parented to ui_layer (the
# SAME screen-space CanvasLayer Deck/Map/ExitHaze already draw through),
# anchored full-width with centered text so it reads correctly regardless
# of how long opening_room_hull_line_text ends up being, at a FIXED
# fraction of viewport height (opening_room_hull_line_screen_y_fraction) -
# not following the player or any hull, since this line is an observation
# about the group of boats, not something tied to one position in the
# room. Starts fully transparent - _play_opening_room_hull_line() is what
# ever makes it visible, and only once, ever, this run (see _update_
# opening_room_hull_line()'s own guard).
func _setup_opening_room_hull_line() -> void:
	if RunState.current_node != RunState.opening_node:
		return
	var label := Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = opening_room_hull_line_screen_y_fraction
	label.anchor_bottom = opening_room_hull_line_screen_y_fraction
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", OPENING_ROOM_HULL_LINE_FONT)
	label.add_theme_font_size_override("font_size", opening_room_hull_line_font_size)
	label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	OverlayStyle.apply_to_label(label, true)
	label.modulate.a = 0.0
	ui_layer.add_child(label)
	_opening_room_hull_line_label = label

# Five unrelated per-frame concerns share this one _process() (GDScript
# allows only one per script) - cloud drift, then vegetation sway, then
# the opening room's own hull-line threshold check (2026-09-06 addition -
# see _update_opening_room_hull_line()'s own doc for why it runs here,
# unconditionally, ahead of the exit_haze early-return below), then the
# opening room's own tide breath (2026-09-07 addition - see _update_
# opening_room_sea()'s own doc), then exit_haze tracking (see each
# function's own doc).
#
# Distance-driven, every frame, rather than triggered off any discrete
# event (a turn ending, a room state change) - the player can walk toward
# or away from the door freely at any time on the field, so this has to
# track continuously the same way, e.g., BlockBadge's fill-edge tracking
# in vitals_bar.gd's own _process() does for an analogous "always follow
# the current live value" reason. No-op immediately if this room has no
# door (exit_haze hidden - see _setup_exit_haze()) - cheap even then,
# just one bool check, not a real per-frame cost for a room without one.
func _process(delta: float) -> void:
	_update_cloud_drift(delta)
	_update_painted_preview_cloud_drift(delta)
	_update_vegetation_sway(delta)
	_update_opening_room_hull_line()
	_update_opening_room_sea(delta)
	if not exit_haze.visible:
		return
	var door: Area2D = exits[0]
	var distance := absf(player.position.x - door.position.x)
	var proximity := clampf(1.0 - distance / maxf(exit_haze_approach_distance_px, 1.0), 0.0, 1.0)
	exit_haze.modulate.a = lerpf(exit_haze_resting_alpha, exit_haze_approach_alpha, proximity)

# Called every frame from _process() above, unconditionally (2026-09-06,
# positional world-voice pass) - _opening_room_hull_line_label's own null
# check (set only for the opening room - see _setup_opening_room_hull_
# line()) is what makes this a cheap no-op in every other room, without
# re-checking RunState.current_node == RunState.opening_node here too.
# RunState.opening_room_hull_line_shown is set THE MOMENT the threshold is
# crossed, before _play_opening_room_hull_line() below even starts its own
# fade - not after it finishes - so this same per-frame check can never
# fire twice while the player's x stays past the threshold for the rest of
# the room, and a save/reload or same-room revisit (RoomState.has_saved_
# position) reads the same already-true flag and stays silent too.
func _update_opening_room_hull_line() -> void:
	if _opening_room_hull_line_label == null:
		return
	if RunState.opening_room_hull_line_shown:
		return
	if player.position.x < opening_room_hull_line_threshold_x:
		return
	RunState.opening_room_hull_line_shown = true
	_play_opening_room_hull_line()

# Fade in, hold, fade out on a plain timer - NOT proximity-driven the way
# every "heap-shape" prompt's own fade-out is (their body_exited): this
# line isn't tied to a contact zone at all (see opening_room_hull_line_
# threshold_x's own doc), so there is no exit event to fade on. Called
# fire-and-forget from _update_opening_room_hull_line() above - nothing
# needs to block on this, and the guard that prevents a second call
# already lives in that function, not here.
#
# ONE chained Tween (2026-09-06, map-overlay fix - REPLACES the original
# separate fade-in Tween + SceneTreeTimer + fade-out Tween, each awaited
# in sequence) - tween_interval() covers the hold in the same chain as
# both fades, rather than a separate timer, specifically so the WHOLE
# sequence is a single object _clear_opening_room_hull_line() can kill
# outright at any point (mid-fade-in, mid-hold, mid-fade-out) with one
# call, regardless of which stage it's in. Sequencing behavior is
# unchanged - fade in, then hold, then fade out, in order, same durations
# as before.
func _play_opening_room_hull_line() -> void:
	_opening_room_hull_line_label.text = opening_room_hull_line_text
	_opening_room_hull_line_tween = create_tween()
	_opening_room_hull_line_tween.tween_property(_opening_room_hull_line_label, "modulate:a", 1.0, opening_room_hull_line_fade_in_sec)
	_opening_room_hull_line_tween.tween_interval(opening_room_hull_line_hold_sec)
	_opening_room_hull_line_tween.tween_property(_opening_room_hull_line_label, "modulate:a", 0.0, opening_room_hull_line_fade_out_sec)

# Cuts the line immediately when the map screen opens (2026-09-06, map-
# overlay fix) - the map's own CanvasLayer and this line's ui_layer are
# both layer 10 (see field_room.tscn), and MapScreen is an EARLIER
# sibling there, so ties resolve in ui_layer's favor - this line draws
# OVER the map panel otherwise. Fired from the two actual places the map
# opens (_on_map_button_pressed()/_on_exit_entered() above) rather than polled
# from _process(), because get_tree().paused (set the instant either one
# opens - see map_screen.gd's own open_map_for_viewing()/open_map_for_
# travel()) stops this node's own _process() from running at all until
# the map closes again - a per-frame check here would never fire while
# the map is actually open. No pause/resume: killing the tween leaves the
# label wherever its alpha happened to land, then this snaps it the rest
# of the way to fully transparent - if the player opened the map, they
# were not reading it, and a resumed fade raises its own question (from
# what remaining duration?) this sidesteps entirely. RunState.opening_
# room_hull_line_shown is NOT touched here - it was already set the
# moment the threshold was crossed (see _update_opening_room_hull_line()),
# so the line correctly stays silent for the rest of this run regardless
# of whether the map ever opens.
func _clear_opening_room_hull_line() -> void:
	if _opening_room_hull_line_label == null:
		return
	if _opening_room_hull_line_tween != null:
		_opening_room_hull_line_tween.kill()
		_opening_room_hull_line_tween = null
	_opening_room_hull_line_label.modulate.a = 0.0

# --- Click-to-move (field movement redesign: mouse parity) ---
#
# Everything below is a thin wrapper; the real behavior (ground clicks,
# click-to-approach on a registered interactable, the shared ground
# marker) lives in click_to_move.gd now (2026-08-27 refactor, no behavior
# change - see that file's own header for why this moved out of here:
# field_interior.gd is the first other scene that needs the exact same
# handling, which an inline implementation here couldn't give it).
#
# Instantiated and configured BEFORE _generate_room_contents()/
# _spawn_exits() run (see the reordered call in _ready() above) - every
# interactable spawned there registers itself with click_to_move as it's
# created, so click_to_move has to already exist by then. Blobs
# deliberately never register at all (see the class-level "how a click
# resolves" note near _npc_in_contact above), so a click on one still
# falls through to click_to_move's own plain-ground-click handling.
func _setup_click_to_move() -> void:
	click_to_move = ClickToMove.new()
	add_child(click_to_move)
	click_to_move.setup(player, content_root, RoomState.floor_line_y)
	click_to_move.set_bounds(ROOM_FLOOR_LEFT_X, _room_floor_right_x())

# Rebuilds Floor's polygon (see field_room.tscn) from RoomState.
# floor_line_y each time a room loads, rather than trusting whatever the
# .tscn happens to have baked in - keeps the ground band in sync with the
# single exported source of truth even if floor_line_y gets retuned
# without anyone hand-editing the scene file to match. Must run BEFORE
# _apply_opening_room_layout() - the coastal variant insets only the
# LEFT edge's X (floor_poly[0]/[3], see its own comments), so it needs
# this polygon's Y already correct before it touches it.
# Resizes the room's actual boundary - TopWall/BottomWall's own run
# length, RightWall's position, and the camera's own right-hand clamp -
# from RoomState.standard_room_width, every time a room loads. LeftWall
# never moves (the entrance/left edge is always the fixed origin,
# regardless of width - see ROOM_FLOOR_LEFT_X's own comment), so it's
# untouched here. Preserves each wall's own collision_half_thickness/
# wall_thickness_px/void_margin_px (reads them back off the node rather
# than hardcoding fresh values) - only half_length actually needs to
# change, via the same configure() API the opening room's ocean/void
# walls already use to resize themselves. Must run before _position_
# floor() - the floor's own right edge depends on this same width.
func _position_room_bounds() -> void:
	var half_width := RoomState.room_width() / 2.0
	top_wall.configure(half_width, top_wall.collision_half_thickness, top_wall.wall_thickness_px, top_wall.void_margin_px)
	top_wall.position.x = half_width
	bottom_wall.configure(half_width, bottom_wall.collision_half_thickness, bottom_wall.wall_thickness_px, bottom_wall.void_margin_px)
	bottom_wall.position.x = half_width
	right_wall.position.x = RoomState.room_width() - WALL_THICKNESS / 2.0
	camera.limit_right = RoomState.room_width()
	# Static single-screen camera (2026-08-29, single-screen pass; TREASURE
	# joined COMBAT here 2026-08-31 - see field_camera.gd's own follow_
	# enabled doc for why this is an explicit mode rather than left to
	# limit-clamping). Explicitly zeroing `position` here too, not just
	# disabling follow_enabled - this runs before that camera's very first
	# _process() tick, so this is what actually guarantees "centered, not
	# whatever the .tscn happened to bake" for every room, not just an
	# assumption about a value never set.
	camera.follow_enabled = not _is_single_screen_room()
	if not camera.follow_enabled:
		camera.position = Vector2.ZERO

# Extends all the way to the room's TRUE outer edges (0 to RoomState.room_width()),
# not just ROOM_FLOOR_LEFT_X/_room_floor_right_x() (the walls' own INNER
# collision face, 40px further in on each side) - now that LeftWall/
# RightWall no longer render a visible slab (see _apply_room_framing()),
# nothing else would cover that 40px sliver on either side, which read
# as clipped/unrendered content right at the boundary (props and the
# ground band alike) before this changed. The player's actual reachable
# extent is UNCHANGED (still bounded by collision at the walls' true
# footprint, unaffected by how far the floor's own visual reaches) -
# this only means the ground now visibly continues a little past where
# the player can actually stand, which reads as "the room continues
# beyond what's walkable" rather than "the world stops exactly at your
# feet." ROOM_FLOOR_LEFT_X/_room_floor_right_x()/ROOM_FLOOR_BOTTOM_Y stay
# exactly what they were for every OTHER caller (the exit door position,
# ground decoration placement bounds, the opening room's water/void
# bottom edge) - those still want to stay comfortably inside the
# walkable area, not right at the visual edge. Same reasoning applies to
# the BOTTOM edge now too (see _room_height()'s own note) - TopWall/
# BottomWall no longer render either (see _apply_room_framing()), so the
# ground's own bottom edge extends all the way to the room's true bottom
# (_room_height(), or _floor_span_bottom_y()'s own taller value at a wider
# RoomState.field_zoom - see that function's own doc) instead of stopping
# short at ROOM_FLOOR_BOTTOM_Y.
#
# X span further decoupled from RoomState.room_width() entirely now
# (2026-08-29, single-screen COMBAT pass), and Y span likewise decoupled
# from _room_height() (2026-09-06, field-pull-back pass) - see _floor_
# span_left_x()/_floor_span_right_x()/_floor_span_bottom_y()'s own docs for
# why (a narrower COMBAT room must still cover the full viewport, a wider
# standard room or taller effective view should never rely on the camera
# merely never reaching the true edge). Every OTHER caller in this file
# (walls, camera limits, exit/content placement) still reads RoomState.
# room_width()/_room_height() directly and is completely unaffected by
# this.
func _position_floor() -> void:
	var left_x := _floor_span_left_x()
	var right_x := _floor_span_right_x()
	var bottom_y := _floor_span_bottom_y()
	floor_polygon.polygon = PackedVector2Array([
		Vector2(left_x, RoomState.floor_line_y), Vector2(right_x, RoomState.floor_line_y),
		Vector2(right_x, bottom_y), Vector2(left_x, bottom_y),
	])
	# Explicit UVs (2026-09-07, wet-ground-strip pass) - one entry per
	# vertex, same order as the polygon array just above, each just that
	# vertex minus the polygon's own top-left corner (left_x, floor_line_y).
	# Without this, Polygon2D auto-generates UVs from the vertex positions
	# THEMSELVES (in this node's local space, i.e. world space - Floor has
	# no transform of its own), so texture row 0 lands wherever world y=0
	# happens to fall in the tiled/repeating texture, not at floor_line_y -
	# effectively an arbitrary offset that only ever changes if floor_
	# line_y or the texture's own height changes to shift the wrap
	# alignment by coincidence. Subtracting the top-left corner here pins
	# UV (0,0) - texture row 0, column 0 - exactly to the polygon's own top
	# edge instead, regardless of world position. Confirmed against Polygon2D's
	# own draw-time code (scene/2d/polygon_2d.cpp): explicit uv values are
	# NOT used raw - they still go through the same texmat.xform(uv[i]) /
	# tex_size transform (texmat built from texture_rotation/texture_offset/
	# texture_scale) as auto-generated UVs would, so ground_texture_scale
	# keeps working exactly as before - this only replaces WHERE the
	# untransformed input coordinate comes from, not what happens to it
	# afterward. texture_offset/texture_rotation are both still their
	# untouched defaults (zero) for this node.
	var uv_origin := Vector2(left_x, RoomState.floor_line_y)
	floor_polygon.uv = PackedVector2Array([
		Vector2(left_x, RoomState.floor_line_y) - uv_origin, Vector2(right_x, RoomState.floor_line_y) - uv_origin,
		Vector2(right_x, bottom_y) - uv_origin, Vector2(left_x, bottom_y) - uv_origin,
	])
	# Set unconditionally here, not inside _apply_standard_ground_
	# treatment() (which early-returns for the opening room) - this is
	# what makes the texture reach BOTH the standard ground and the
	# coastal sand floor (see the "Ground texture" export group's own
	# doc). texture_repeat has no project-wide default in this project
	# (checked - see this pass's own Phase 1 report), so it's set
	# explicitly per-node rather than relied on.
	if ground_texture_enabled and ground_texture != null:
		floor_polygon.texture = ground_texture
		floor_polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		floor_polygon.texture_scale = Vector2(ground_texture_scale, ground_texture_scale)
	else:
		floor_polygon.texture = null

# Depth cue for the ground TEXTURE (2026-08-30 ground-texture pass) -
# distinct from _depth_tinted_color() below, which tints ground
# DECORATION (patches/seam debris) per-instance; this one tints floor_
# polygon itself via vertex_colors rather than a single per-instance
# color, since a Polygon2D only exposes ONE flat `color` property but
# can vary color per vertex. Called with whichever color the calling
# room already assigns floor_polygon.color to (ground_base_color for
# standard rooms, OPENING_ROOM_SAND_COLOR for the coastal room - see
# each call site) so neither is hardcoded here.
#
# Vertex order/count is fixed by _position_floor() above and never
# changes afterward - _apply_coastal_opening_room_layout() no longer
# touches floor_polygon.polygon/.uv at all (2026-09-07, sea-polygons pass
# - REMOVES the shore-inset x-shift this comment used to describe; the
# ground now runs to its natural left edge under the translucent sea
# instead) - so indices 0/1 are always the far edge (at floor_line_y) and
# 2/3 are always the near edge (at _floor_span_bottom_y(), the same value
# for every room type, opening room included since 2026-09-07's earlier
# opening-room floor-bottom fix - see that function's own doc), matching
# _position_floor()'s own PackedVector2Array literal exactly.
#
# vertex_colors, once set, take over from the flat `color` property
# entirely (Polygon2D uses one or the other, not a blend of both) - so
# when the texture is off, this clears vertex_colors back to empty
# rather than leaving a residual gradient the "flat color fill, no
# texture" fallback (see ground_texture_enabled's own doc) promised.
func _apply_floor_depth_tint(base_color: Color) -> void:
	if not ground_texture_enabled or ground_texture == null:
		floor_polygon.vertex_colors = PackedColorArray()
		return
	var far_color := base_color.lerp(sky_gradient_horizon_color, ground_texture_depth_tint)
	floor_polygon.vertex_colors = PackedColorArray([far_color, far_color, base_color, base_color])

# --- Background layering (see the @export group above for why these
# numbers are what they are) ---
#
# STRUCTURE vs CONTENT stays split: this function (layer setup -
# motion_scale, mirroring) is independent of whatever fills the layers -
# only _populate_far_layer()/_populate_mid_layer() (the actual shapes/
# colors) decide that. A future region's own content would swap in its
# own pair of populate functions here and touch nothing else - the
# 2026-08-30 strip pass, which emptied those two functions' shape pools
# down to nothing, made zero changes to this one.
func _build_background_layers() -> void:
	_build_sky_gradient()
	_add_sky_light_gradient()
	_add_tower_silhouette()
	# Empty skyline for the opening room (2026-08-27) - same "check the
	# opening room, return/branch before the shared treatment applies"
	# shape _apply_standard_ground_treatment() already established for
	# ground clutter, just a mutation instead of an early return (this
	# function has shared setup below - sky gradient, particulates,
	# occluders - that the opening room still wants). Mutates the shared
	# exports ONCE, before _populate_far_layer()/_populate_mid_layer()
	# ever read them below, same "mutate the shared export once, before
	# anything reads it" pattern enemy.gd's own set_enemy_data() already
	# uses for silhouette_scale - safe here for the same reason: a fresh
	# field_room.tscn instance per room load, never read twice.
	if RunState.current_node == RunState.opening_node:
		far_structure_count = opening_room_far_structure_count
		mid_structure_count = opening_room_mid_structure_count
	# TREASURE's own overhang (2026-08-31, treasure-overhang pass) - the
	# SECOND room-aware branch in this function (the opening-node one
	# above is the first), and deliberately still a single `if` against a
	# specific room type/node rather than a general per-room-type dispatch
	# (a match statement, a Dictionary of callables) - there is exactly
	# one room type with its own background treatment beyond the opening
	# room's, so building general dispatch machinery for it would be
	# solving a problem this codebase doesn't have yet, the same "wait for
	# a second real case before generalizing" instinct SunkenWorksPalette
	# and RunState.SUNKEN_WORKS_ROOM_NAMES (now removed) both already
	# followed. Mutates foreground_occluders_enabled the same "shared
	# export, set once, read later in this same function" way the opening-
	# node branch above already does - see _add_treasure_overhang()'s own
	# doc for why a top-and-bottom dark mass together would crush the
	# playable strip, and foreground_occluders_enabled's own doc (read
	# near the bottom of this function) for what it actually gates.
	# Set unconditionally, every room build, regardless of type (2026-09-01
	# bugfix) - NOT left to only the TREASURE branch below. Once the shape
	# got a real hand-drawn polygon (see treasure_overhang_shape's own
	# @onready doc), field_room.tscn's saved `visible` (true, the Polygon2D
	# default - the property isn't even written to the .tscn) started
	# rendering in every room type, since _add_treasure_overhang() below
	# - the only other place this node's visibility is touched - never
	# runs outside TREASURE. This line is what actually wins on every load
	# regardless of what's baked into the scene, so an editor resave can't
	# reintroduce the bug.
	treasure_overhang_shape.visible = RoomState.current_room_type == RoomType.Kind.TREASURE and treasure_overhang_enabled
	# Same unconditional-every-load fix, same reason, applied pre-emptively
	# (2026-09-02) - treasure_foreground_rock_shape became a REAL field_
	# room.tscn child in the same pass that made it hand-editable (see its
	# own @onready doc), which reintroduces exactly the bug treasure_
	# overhang_shape's own line above already learned this the hard way
	# for: a baked scene default (Polygon2D.visible = true) would render
	# in every room type if left to only the TREASURE branch below, since
	# _add_treasure_foreground_rock() never runs outside it.
	treasure_foreground_rock_shape.visible = RoomState.current_room_type == RoomType.Kind.TREASURE and treasure_foreground_rock_enabled
	if RoomState.current_room_type == RoomType.Kind.TREASURE:
		if treasure_overhang_enabled:
			foreground_occluders_enabled = false
		_add_treasure_overhang()
		_add_treasure_ground_shade()
		_add_treasure_groundsheet()
		_add_treasure_foreground_rock()
	# Region gradient (2026-08-31 wet-to-dry pass) - same mutate-the-
	# shared-export-once pattern as the opening-room override just above,
	# but UNCONDITIONAL (every room gets a gradient value, not just the
	# opening one) and gated on region_gradient_enabled instead of a room
	# check. Runs for the opening room too without needing its own
	# exclusion: _region_gradient_value is already 0.0 there (RoomState.
	# region_progress is 0.0 by construction - see that field's own doc),
	# so this lands exactly on each constant's WET endpoint, and mid_
	# structure_count is already forced to 0 by the override just above
	# regardless of what landform_mid_chance ends up as - never read
	# there. See VEGETATION_MIN_CLUMPS_WET/_DRY etc.'s own doc for why
	# these three ranges specifically.
	if region_gradient_enabled:
		vegetation_min_clumps = roundi(lerpf(VEGETATION_MIN_CLUMPS_WET, VEGETATION_MIN_CLUMPS_DRY, _region_gradient_value))
		vegetation_cluster_count = roundi(lerpf(VEGETATION_CLUSTER_COUNT_WET, VEGETATION_CLUSTER_COUNT_DRY, _region_gradient_value))
		landform_mid_chance = lerpf(LANDFORM_MID_CHANCE_WET, LANDFORM_MID_CHANCE_DRY, _region_gradient_value)
	background_far.motion_scale = Vector2(far_layer_motion_scale, 1.0)
	background_mid.motion_scale = Vector2(mid_layer_motion_scale, 1.0)
	background_far.motion_mirroring = Vector2(background_tile_width, 0.0)
	background_mid.motion_mirroring = Vector2(background_tile_width, 0.0)
	# Mid sits visually CLOSER than far (taller shapes, reaching further
	# down toward the ground line) as well as moving faster - both cues
	# reinforce the same depth read, not just the scroll speed alone.
	# Freshly randomized every call (every room _ready()), which is what
	# gives rooms modest, same-vocabulary variation for free (DESIGN.md's
	# Sunken Works: "vary composition between rooms") without any extra
	# per-room plumbing - see _populate_far_layer()/_populate_mid_layer().
	_populate_far_layer(background_far)
	_populate_mid_layer(background_mid)

	particulate_far_layer.motion_scale = Vector2(particulate_far_motion_scale, 1.0)
	particulate_near_layer.motion_scale = Vector2(particulate_near_motion_scale, 1.0)
	particulate_far_layer.motion_mirroring = Vector2(background_tile_width, 0.0)
	particulate_near_layer.motion_mirroring = Vector2(background_tile_width, 0.0)
	_populate_particulate_layer(particulate_far_layer, particulate_far_count, particulate_far_color, particulate_far_drift_speed_px_sec)
	_populate_particulate_layer(particulate_near_layer, particulate_near_count, particulate_near_color, particulate_near_drift_speed_px_sec)

	# Foreground occluders (see foreground_occluders_enabled's own doc) -
	# a SEPARATE ParallaxBackground (Foreground, positioned after Player
	# in field_room.tscn), not a child of Background above, so it draws
	# in front of the play plane regardless of what Background's own
	# children do. visible is set every room load (not just left at
	# whatever the .tscn happened to bake in) so toggling the export
	# takes effect immediately on the NEXT room without needing a scene
	# edit - same "read the export fresh each _ready()" shape every other
	# per-room-randomized layer here already follows. Left completely
	# unpopulated (no children added at all) when disabled, not just
	# hidden - nothing to evaluate for combat readability if it never ran.
	occluder_background.visible = foreground_occluders_enabled
	if foreground_occluders_enabled:
		occluder_layer.motion_scale = Vector2(occluder_layer_motion_scale, 1.0)
		occluder_layer.motion_mirroring = Vector2(background_tile_width, 0.0)
		_populate_occluder_layer(occluder_layer, foreground_band_height, foreground_band_overshoot, 0.0, occluder_color)
		# Second, further-back instance of the same band (2026-08-30
		# foreground-depth pass) - see foreground_band_far_enabled's own
		# doc. A separate ParallaxLayer (occluder_far_layer) carries its
		# own slower motion_scale; declared before occluder_layer in
		# field_room.tscn so it draws behind it via ordinary sibling
		# order, while both stay in front of Player via Foreground's own
		# CanvasLayer.layer=1.
		if foreground_band_far_enabled:
			occluder_far_layer.motion_scale = Vector2(foreground_band_far_motion_scale, 1.0)
			occluder_far_layer.motion_mirroring = Vector2(background_tile_width, 0.0)
			var far_tint := occluder_color.lerp(sky_gradient_horizon_color, foreground_band_far_fade)
			far_tint.a = occluder_color.a
			_populate_occluder_layer(occluder_far_layer, foreground_band_far_height, foreground_band_far_overshoot, foreground_band_far_offset_x, far_tint)

	# painted_mid_layer starts hidden every room load, same "set every
	# room, not left at whatever the .tscn baked in" shape occluder_
	# background.visible above already follows - only _apply_painted_
	# preview() (below) ever populates it, and only when both flags are
	# true, so there's nothing to show otherwise.
	painted_mid_layer.visible = painted_preview_enabled and painted_preview_mid_enabled

	# THROWAWAY preview path (see painted_preview_enabled's own doc) -
	# called last, after every procedural layer above has already built
	# and populated itself normally, so nothing above needs to know this
	# exists. Purely additive/hiding from here on; false is a no-op.
	if painted_preview_enabled:
		_apply_painted_preview()

# See painted_preview_enabled's own doc. Hides every procedural
# background/foreground layer built above and drops the three painted
# plates in their place, reusing the same anchors (RoomState.floor_line_y,
# camera.get_screen_center_position()) the procedural layers already read
# so the painted plates line up with the play plane instead of needing
# their own independent tuning pass.
#
# occluder_background (the Foreground ParallaxBackground/CanvasLayer) is
# deliberately NOT hidden wholesale the way sky_layer/background_far/
# background_mid are, even though it's the parent of the procedural
# occluder bands this replaces - CanvasLayer.visible hides EVERY
# descendant regardless of that descendant's own visible flag, and the
# painted foreground band below has to live inside occluder_layer (a real
# ParallaxLayer) to inherit its motion_scale/motion_mirroring correctly.
# Hiding occluder_background would take the new band down with it. The
# procedural bands are hidden individually instead - occluder_layer's own
# existing children (the near band _populate_occluder_layer() already
# added above) and occluder_far_layer wholesale (nothing new goes there).
# Hides every node _painted_preview_decoration_nodes has tracked SO FAR
# (2026-09-05, coastal-decoration fix) - pulled out of _apply_painted_
# preview() into its own function so it can be called a second time,
# later in _ready(), after _apply_opening_room_layout() has had its
# chance to add the opening room's own coastal seam debris/vegetation/
# tide bands (_apply_coastal_opening_room_layout() runs AFTER _build_
# background_layers(), so those specific nodes don't exist yet the first
# time this runs from inside _apply_painted_preview() below - they were
# reaching content_root visible, painted preview or not, until this
# second call started catching them too). Harmless to call twice, or on
# an empty/already-hidden list - setting visible=false on a node that's
# already false is a no-op, same reasoning this list's own doc already
# gives for occluder_layer's children.
func _hide_painted_preview_decorations() -> void:
	for decoration_node in _painted_preview_decoration_nodes:
		decoration_node.visible = false

func _apply_painted_preview() -> void:
	sky_layer.visible = false
	background_far.visible = false
	background_mid.visible = false
	particulate_far_layer.visible = false
	particulate_near_layer.visible = false
	for existing_child in occluder_layer.get_children():
		existing_child.visible = false
	occluder_far_layer.visible = false
	# The opening room's own left_wall is a real collision object (see
	# field_wall.gd) whose VISUAL gets repurposed as the ocean by
	# _apply_coastal_opening_room_layout() (set_visual_enabled(true) +
	# set_wall_color(OPENING_ROOM_OCEAN_COLOR)) - a procedural background
	# element that lives entirely outside the Background/MidLayer/FarLayer
	# system every other hide-line above accounts for, so it was rendering
	# right over the painted plate on the room's left edge, unhidden.
	# set_visual_enabled(false) is the same public method field_room.gd's
	# own _apply_room_framing() already uses to turn wall visuals off by
	# default elsewhere - it only touches wall_body/depth_shade.visible,
	# never collision_shape (see its own doc), so the player's own bounds
	# are completely untouched. Harmless to call on every room, coastal or
	# not - a non-coastal room's left_wall visual is already off.
	left_wall.set_visual_enabled(false)
	# Every purely-decorative node _add_floor_decoration()/_add_wavy_band()/
	# _add_vegetation_clump() have EVER created this room, hidden the same
	# way - see _painted_preview_decoration_nodes' own doc for why a tracked
	# list, not a parent-container toggle, is what actually reaches these:
	# every one of those three helpers parents its own output to whatever
	# `content_root`-or-other node its caller passes it (content_root by
	# default for _add_wavy_band(), always content_root for _add_floor_
	# decoration()), and content_root ALSO holds real interactive content
	# (chests, NPCs, structures, the heap/curio/forge) that must stay
	# visible and clickable - so content_root itself can never be the thing
	# painted-preview hides wholesale.
	#
	# Only catches what's in the list AS OF RIGHT NOW, though - see this
	# call's own second invocation, added below in _ready(), for the
	# opening room's coastal decoration (seam debris/vegetation/tide
	# bands), which doesn't exist yet at this point in the room's build.
	_hide_painted_preview_decorations()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# --- Background plate: its own CanvasLayer, behind EVERYTHING else in
	# the room - see painted_preview_bg_canvas_layer's own doc (2026-09-06,
	# CanvasLayer-ordering fix) for why -101, one step below Background's
	# own runtime layer of -100, not the -99 this used to be (that sat
	# ABOVE Background and covered its entire stack - FarLayer, MidLayer,
	# both particulate layers, PaintedMidLayer - regardless of what any of
	# them held). Also below SkyLayer (layer -100, same value as
	# Background) now, not one step above it as before - harmless, since
	# SkyLayer is already hidden wholesale during the preview anyway (see
	# this function's own hide-list at the top). Scaled to FILL the room's
	# height exactly (viewport height, since the camera never scrolls
	# vertically - see
	# _populate_occluder_layer()'s own note on limit_top/limit_bottom
	# having zero clamping slack), aspect ratio preserved, so its width
	# overflows the viewport - expected, and harmless: this layer never
	# scrolls at all (no motion_mirroring, no parallax), which is "near-
	# zero motion" taken to its own limit.
	#
	# position.y is PINNED TO 0.0 (2026-09-05, letterboxing fix) - REPLACES
	# a computed `RoomState.floor_line_y - bg_horizon_offset_y`, which
	# shifted the whole (already exactly viewport-height-tall) sprite up or
	# down to land its painted horizon on floor_line_y, reintroducing
	# exactly the gap the height-fill scale above was supposed to
	# eliminate: since bg_scale already forces the sprite's rendered height
	# to equal viewport_size.y precisely, ANY position.y other than 0.0
	# leaves a gap at the top (if positive) and/or bottom (if the sprite's
	# own bottom edge then falls short of viewport_size.y) - there is no
	# position that both fills the frame AND satisfies an independent
	# horizon target, because a viewport-height sprite has exactly ONE
	# gap-free position. Filling the frame wins per this pass's own brief.
	#
	# This does NOT strand horizon alignment as unsolvable, though - it
	# just moves control of it entirely onto painted_preview_bg_horizon_
	# fraction, which this function no longer uses to compute a position
	# offset, only (implicitly) to decide where within the now length-
	# fixed image the horizon happens to sit on screen: with position.y
	# pinned to 0, the horizon's own screen Y becomes exactly
	# `viewport_size.y * painted_preview_bg_horizon_fraction` (bg_native_
	# size.y cancels out of that product entirely - see this pass's own
	# report for the derivation). So the fraction that lands the horizon
	# EXACTLY on RoomState.floor_line_y, with zero remaining gap, is simply
	# `RoomState.floor_line_y / viewport_size.y` - report this to whoever
	# next tunes painted_preview_bg_horizon_fraction rather than hardcoding
	# it here, since that export is documented as a by-eye Inspector nudge,
	# not a computed value, and floor_line_y is not guaranteed identical
	# across every room this preview might ever be checked against.
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = painted_preview_bg_canvas_layer
	add_child(bg_layer)
	var bg_sprite := Sprite2D.new()
	bg_sprite.texture = PAINTED_PREVIEW_BACKGROUND_TEXTURE
	bg_sprite.centered = false
	var bg_native_size: Vector2 = bg_sprite.texture.get_size()
	var bg_scale: float = viewport_size.y / bg_native_size.y
	bg_sprite.scale = Vector2(bg_scale, bg_scale)
	var bg_displayed_width := bg_native_size.x * bg_scale
	bg_sprite.position = Vector2((viewport_size.x - bg_displayed_width) / 2.0, 0.0)
	bg_layer.add_child(bg_sprite)

	# --- Clouds (2026-09-05, cloud-reenable pass): re-enables JUST
	# _add_clouds()'s own sprites, pulled out of background_far (which
	# stays hidden above, taking landform/recession-bands/haze down with
	# it - see _painted_preview_cloud_nodes' own doc) and reparented onto
	# THIS SAME bg_layer, added here - a LATER sibling than bg_sprite, so
	# it draws on top of the plate, and BEFORE the bloom block below, so
	# the bloom (added after this) still draws on top of clouds too.
	#
	# Reported before implementing, per this pass's own instructions: real
	# ParallaxLayer.motion_scale requires a ParallaxBackground as the
	# DIRECT parent, which bg_layer (a plain CanvasLayer) isn't, and the
	# only way to sit between two fixed siblings on one CanvasLayer is to
	# BE on that same CanvasLayer - the two requirements (this draw
	# position, real camera parallax) couldn't both hold. Resolved (by
	# explicit direction) in favor of draw order - painted_preview_cloud_
	# motion_scale is declared but not wired to anything; see its own doc.
	#
	# Position is reset fresh in VIEWPORT space, not carried over from
	# FarLayer's tile space (background_tile_width-sized X ranges that
	# would place most clouds off-screen or in nonsensical spots once
	# there's no ParallaxLayer transform translating them any more). Y
	# reuses cloud_band_top_y/_bottom_y directly, unconverted - safe
	# because this room's camera never scrolls vertically (confirmed
	# elsewhere in this file: floor_line_y/room height/viewport height
	# leave zero vertical clamping slack), so world Y and screen Y are
	# already identical here.
	if painted_preview_cloud_enabled:
		var cloud_margin: float = 0.0
		for texture in cloud_textures:
			cloud_margin = maxf(cloud_margin, texture.get_size().x)
		cloud_margin *= cloud_scale_max
		_painted_preview_cloud_drift_min = -cloud_margin
		_painted_preview_cloud_drift_max = viewport_size.x + cloud_margin
		for cloud_sprite in _painted_preview_cloud_nodes:
			background_far.remove_child(cloud_sprite)
			bg_layer.add_child(cloud_sprite)
			cloud_sprite.position = Vector2(
				randf_range(_painted_preview_cloud_drift_min, _painted_preview_cloud_drift_max),
				randf_range(cloud_band_top_y, cloud_band_bottom_y),
			)
			cloud_sprite.modulate = Color(painted_preview_cloud_tint.r, painted_preview_cloud_tint.g, painted_preview_cloud_tint.b, painted_preview_cloud_alpha)
			if cloud_drift_enabled:
				_painted_preview_cloud_drift_state.append({"sprite": cloud_sprite, "speed": randf_range(cloud_drift_speed_min, cloud_drift_speed_max)})

	# --- Sky bloom (2026-09-05, sky-bloom pass): a soft, diffuse cool
	# brightening patch - NOT a light source, NOT god rays - added as a
	# LATER sibling of bg_sprite inside the SAME bg_layer CanvasLayer, so
	# it composites directly on top of the plate (later siblings on one
	# CanvasLayer draw over earlier ones, same ordinary sibling-order rule
	# every other layer in this file already relies on) while staying
	# behind everything else - Background/Foreground/Player/UI all sit on
	# their own separate CanvasLayers at higher layer values than bg_
	# layer's painted_preview_bg_canvas_layer (-101 by default), so nothing
	# above the plate can ever be affected by this, structurally, without
	# this needing its own visibility checks against any of them.
	#
	# Gated on painted_preview_bloom_enabled specifically, not just the
	# outer painted_preview_enabled this whole function already requires -
	# lets the bloom be turned off on its own while still checking
	# everything else this function does.
	if painted_preview_bloom_enabled:
		var bloom_sprite := Sprite2D.new()
		bloom_sprite.texture = PAINTED_PREVIEW_BLOOM_TEXTURE
		bloom_sprite.centered = false
		# Uniform scale from viewport WIDTH (painted_preview_bloom_scale's
		# own doc) - the source texture is square (1024x1024), so scaling
		# both axes by the same factor keeps the rendered patch circular
		# rather than stretching it into an ellipse. Never derived from the
		# texture's own native pixel size beyond reading it once here for
		# the ratio - the viewport is the actual size reference, per this
		# pass's own brief ("holds if the viewport changes").
		var bloom_native_size: Vector2 = bloom_sprite.texture.get_size()
		var bloom_target_width := viewport_size.x * painted_preview_bloom_scale
		var bloom_scale_factor := bloom_target_width / bloom_native_size.x
		bloom_sprite.scale = Vector2(bloom_scale_factor, bloom_scale_factor)
		bloom_sprite.position = Vector2(viewport_size.x * painted_preview_bloom_pos.x, viewport_size.y * painted_preview_bloom_pos.y)
		bloom_sprite.modulate = Color(painted_preview_bloom_color.r, painted_preview_bloom_color.g, painted_preview_bloom_color.b, painted_preview_bloom_strength)
		# ADDITIVE compositing (2026-09-05, sky-bloom pass) - straightforward
		# in this setup: one CanvasItemMaterial, one property. Chosen over
		# plain alpha blending because it's what actually makes this read as
		# LIGHT adding onto the plate underneath (a "brightening") rather
		# than a soft grey-white patch painted over it - see painted_
		# preview_bloom_strength's own doc for why 0.35 is tuned for THIS
		# blend mode specifically, not a value that would look the same
		# under plain alpha blending.
		var bloom_material := CanvasItemMaterial.new()
		bloom_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		bloom_sprite.material = bloom_material
		bg_layer.add_child(bloom_sprite)

	# --- Mid-distance parallax plates (2026-09-05, mid-layer pass): fills
	# the gap between the painted plate above (bg_layer, CanvasLayer -101
	# by default, NO parallax at all) and the ground strip/foreground band
	# below (occluder_layer, motion_scale 1.12) - nothing sat at an
	# intermediate motion_scale before this.
	#
	# A REAL ParallaxLayer this time, unlike the clouds section above
	# (which had to give up real motion_scale because it was pinned
	# between two FIXED bg_layer siblings). These plates have no such
	# constraint, so they're just a third child of Background - the SAME
	# ParallaxBackground/CanvasLayer FarLayer/MidLayer already live under
	# - and inherit real camera-tied parallax the ordinary way.
	#
	# Draw order comes from tree position: painted_mid_layer is authored
	# in field_room.tscn as Background's LAST child, after FarLayer/
	# MidLayer/ParticulateFarLayer/ParticulateNearLayer - all of which are
	# ALREADY behind Floor/Player/content_root/Foreground in every normal
	# (non-preview) room today - this inherits that exact same
	# relationship for free, rather than needing its own new reasoning
	# about it.
	#
	# painted_mid_layer is SCENE-AUTHORED (2026-09-05, mid-layer scene-node
	# fix) - matches every other working ParallaxLayer in this room
	# (FarLayer/MidLayer/ParticulateFarLayer/ParticulateNearLayer), all
	# authored directly in field_room.tscn rather than created at runtime.
	#
	# load() at RUNTIME (2026-09-05) - NOT a preload const like PAINTED_
	# PREVIEW_BACKGROUND_TEXTURE and friends above. Those preload() consts
	# already broke a teammate's checkout once: preload resolves at PARSE
	# time and takes the whole script down if the file's ever missing.
	# load() only touches disk when this line actually runs - gated behind
	# painted_preview_enabled/painted_preview_mid_enabled both being true,
	# same as everything else in this function - and returns null instead
	# of crashing if a file's missing (see the `if texture == null:
	# continue` below). The existing PAINTED_PREVIEW_* consts are left
	# exactly as they are - a separate, not-this-pass fix.
	if painted_preview_mid_enabled:
		var mid_layer := painted_mid_layer
		# Clears whatever sprites a PRIOR call left behind (2026-09-05,
		# mid-layer scene-node fix) - painted_mid_layer is now a real,
		# persistent scene node rather than a fresh ParallaxLayer.new()
		# every call, so re-entering/rebuilding a room without this would
		# stack a second, third, etc. copy of all three plates on top of
		# the first. queue_free(), not free() - same deferred-removal
		# idiom gold_display.gd's own _build_coin() already uses for the
		# identical "safely re-callable, clear old children first" shape.
		for existing_mid_child in mid_layer.get_children():
			existing_mid_child.queue_free()
		# background_tile_width (2200 default, already guaranteed >=
		# viewport width by this room's own _ready() assert) - the SAME
		# repeat width background_far/background_mid already mirror on
		# just above. One value serves all three plates fine despite
		# their different native widths: motion_mirroring repeats the
		# LAYER as a whole (this three-plate arrangement), not each
		# sprite individually, so sprite width has no bearing on this
		# decision - there's no real per-sprite conflict to resolve here.
		# Set unconditionally now (2026-09-06, opening-room hull pass) -
		# both branches below need it, and painted_mid_layer is never
		# skipped wholesale for any room any more (see painted_preview_
		# mid_opening_room_hulls_enabled's own doc, RENAMED from painted_
		# preview_mid_skip_opening_room - that flag used to hide this
		# entire layer for the opening room; now it only gates whether
		# THAT room's own hull line appears, since the opening room has
		# real content here instead of none).
		mid_layer.motion_scale = Vector2(painted_preview_mid_motion_scale, 1.0)
		mid_layer.motion_mirroring = Vector2(background_tile_width, 0.0)
		if RunState.current_node == RunState.opening_node:
			# Authored, not seeded-random (2026-09-06, opening-room hull
			# pass) - the dune/bank/grass block in the else branch below
			# still places LAND seaward of the shoreline, still wrong here
			# since this room's whole left side is ocean (unchanged
			# reasoning, see _apply_coastal_opening_room_layout()), so
			# three hand-placed boat hulls read as a composed line here
			# instead. mid_rng below is seeded from RunState.current_node.
			# id, which for RunState.opening_node (RunNode.new(-1, 0)) is
			# the SAME id on every run - so its presence-roll/jitter/
			# random-X machinery would resolve to one fixed, hidden-behind-
			# a-roll outcome forever, not "occasionally different." This
			# branch skips that machinery entirely instead of seeding it
			# differently, and places all three hulls unconditionally.
			if painted_preview_mid_opening_room_hulls_enabled:
				var opening_hull_specs: Array[Dictionary] = [
					{
						"path": "res://assets/regions/beach/OpeningRoom/Boats/hull_a_long.png",
						"height_frac": painted_preview_mid_hull_a_height_frac,
						"x_frac": painted_preview_mid_hull_a_x_frac,
						"y_offset": painted_preview_mid_hull_a_y_offset,
						"modulate": painted_preview_mid_hull_a_modulate,
					},
					{
						"path": "res://assets/regions/beach/OpeningRoom/Boats/hull_b_listing.png",
						"height_frac": painted_preview_mid_hull_b_height_frac,
						"x_frac": painted_preview_mid_hull_b_x_frac,
						"y_offset": painted_preview_mid_hull_b_y_offset,
						"modulate": painted_preview_mid_hull_b_modulate,
					},
					{
						"path": "res://assets/regions/beach/OpeningRoom/Boats/hull_c_upright.png",
						"height_frac": painted_preview_mid_hull_c_height_frac,
						"x_frac": painted_preview_mid_hull_c_x_frac,
						"y_offset": painted_preview_mid_hull_c_y_offset,
						"modulate": painted_preview_mid_hull_c_modulate,
					},
				]
				# x_frac values above are hand-constrained to the landward
				# side of this room's fixed shoreline (see those exports'
				# own doc) - unlike mid_plate_specs below, there is no
				# collision/gap check here: three authored positions either
				# clear each other by design or don't, nothing resamples.
				for spec in opening_hull_specs:
					var hull_texture: Texture2D = load(spec["path"])
					if hull_texture == null:
						continue
					var hull_native_size: Vector2 = hull_texture.get_size()
					# No jitter factor, unlike mid_plate_specs below - see
					# painted_preview_mid_hull_a_height_frac's own doc for
					# why an authored line doesn't want a fixed-seed roll
					# standing in for a hand-set value.
					var hull_target_height: float = viewport_size.y * spec["height_frac"]
					var hull_scale_factor: float = hull_target_height / hull_native_size.y
					var hull_sprite := Sprite2D.new()
					hull_sprite.texture = hull_texture
					hull_sprite.centered = false
					hull_sprite.scale = Vector2(hull_scale_factor, hull_scale_factor)
					# MULTIPLIES the shared painted_preview_mid_modulate by
					# this hull's own modulate (white by default, the
					# identity multiplier) - see painted_preview_mid_hull_a_
					# modulate's own doc for why this is a multiply, not a
					# replacement.
					hull_sprite.modulate = painted_preview_mid_modulate * spec["modulate"]
					# Same bottom-anchored Y convention as mid_plate_specs
					# below (position is this sprite's TOP-LEFT corner, so
					# subtracting its own rendered height anchors its
					# BOTTOM edge at floor_line_y), plus this entry's OWN
					# y_offset on top of the shared painted_preview_mid_
					# y_offset - small and negative, so the hull sits
					# slightly above floor_line_y rather than flush with it.
					hull_sprite.position = Vector2(
						spec["x_frac"] * viewport_size.x,
						RoomState.floor_line_y - hull_target_height + painted_preview_mid_y_offset + spec["y_offset"],
					)
					mid_layer.add_child(hull_sprite)
		else:
			if painted_preview_mid_plates_enabled:

				# Seeded from RunState.current_node.id (2026-09-06, per-room
				# variation pass) - the closest thing to an existing per-room
				# seed anywhere in this file: no OTHER generated content here
				# (landform, vegetation, clouds, particulates) is seeded at
				# all - every one of them reads the shared global randf()/
				# randi() RNG, so there was no literal existing "room seed" to
				# reuse. current_node.id (e.g. "L1_0") is stable for this
				# room's entire lifetime in the run - re-entering reads the
				# SAME RunNode object - so hashing it reproduces the same
				# presence/position/scale/gap outcome on re-entry, without
				# touching the shared global RNG every other procedural
				# system in this file still draws from.
				var mid_rng := RandomNumberGenerator.new()
				mid_rng.seed = RunState.current_node.id.hash()

				var mid_plate_specs: Array[Dictionary] = [
					{
						"path": "res://assets/regions/beach/PaintedBackgrounds/mid_dune_mass.png",
						"height_frac": painted_preview_mid_dune_height_frac,
					},
					{
						"path": "res://assets/regions/beach/PaintedBackgrounds/mid_bank_long.png",
						"height_frac": painted_preview_mid_bank_height_frac,
					},
					{
						"path": "res://assets/regions/beach/PaintedBackgrounds/mid_grass_clumps.png",
						"height_frac": painted_preview_mid_grass_height_frac,
					},
				]
				# [left, right] screen-space span of every plate placed so far
				# this room - checked against painted_preview_mid_min_gap_frac
				# below. Logical/viewport-fraction space, the same space
				# positions are sampled in - not the mirrored/repeated copies
				# motion_mirroring draws beyond this one arrangement.
				var mid_placed_spans: Array[Vector2] = []
				# Resample cap (2026-09-06, per-room variation pass) - a
				# plate that still can't find a gap-respecting spot after this
				# many tries is DROPPED, not retried forever (this section's
				# own brief). 10 chosen as a small, clearly-bounded number
				# that still gives the random placement a fair number of
				# chances against the two plates ahead of it in the array
				# before giving up.
				var mid_placement_retry_limit := 10
				for spec in mid_plate_specs:
					# Presence roll first, before spending a load() on a plate
					# that may not even appear this room.
					if mid_rng.randf() >= painted_preview_mid_spawn_chance:
						continue
					var mid_texture: Texture2D = load(spec["path"])
					if mid_texture == null:
						continue
					var mid_native_size: Vector2 = mid_texture.get_size()
					# Height from viewport, never a hardcoded pixel value (this
					# pass's own brief) - width follows automatically via uniform
					# scale, same aspect-ratio-preserving convention bg_sprite/
					# bloom_sprite already use above. Further multiplied by a
					# seeded jitter factor (2026-09-06) for internal depth
					# within the mid distance itself, rather than one flat
					# plane every room repeats identically.
					var mid_jitter_factor: float = mid_rng.randf_range(1.0 - painted_preview_mid_scale_jitter, 1.0 + painted_preview_mid_scale_jitter)
					var mid_target_height: float = viewport_size.y * spec["height_frac"] * mid_jitter_factor
					var mid_scale_factor: float = mid_target_height / mid_native_size.y
					var mid_rendered_width: float = mid_native_size.x * mid_scale_factor
					var mid_min_gap_px: float = painted_preview_mid_min_gap_frac * viewport_size.x
					# X is a FRACTION OF VIEWPORT WIDTH (this pass's own brief),
					# not floor_line_y-style world/tile-space placement - an
					# explicit, deliberate deviation from how FarLayer/MidLayer's
					# OWN procedural content otherwise positions itself along
					# background_tile_width. Sampled per-plate (2026-09-06)
					# across painted_preview_mid_x_min_frac/_max_frac instead of
					# a fixed per-plate fraction, then checked against every
					# already-placed plate's own span, expanded by the min-gap
					# margin on both sides - a direction-agnostic interval-
					# overlap test, since which plate ends up left/right of
					# which isn't known ahead of the roll.
					var mid_placed_x := 0.0
					var mid_placement_found := false
					for mid_attempt in mid_placement_retry_limit:
						var mid_candidate_x: float = mid_rng.randf_range(painted_preview_mid_x_min_frac, painted_preview_mid_x_max_frac) * viewport_size.x
						var mid_candidate_right := mid_candidate_x + mid_rendered_width
						var mid_conflict := false
						for mid_placed_span in mid_placed_spans:
							if mid_candidate_x < mid_placed_span.y + mid_min_gap_px and mid_placed_span.x < mid_candidate_right + mid_min_gap_px:
								mid_conflict = true
								break
						if not mid_conflict:
							mid_placed_x = mid_candidate_x
							mid_placement_found = true
							break
					if not mid_placement_found:
						continue
					mid_placed_spans.append(Vector2(mid_placed_x, mid_placed_x + mid_rendered_width))
					var mid_sprite := Sprite2D.new()
					mid_sprite.texture = mid_texture
					mid_sprite.centered = false
					mid_sprite.scale = Vector2(mid_scale_factor, mid_scale_factor)
					mid_sprite.modulate = painted_preview_mid_modulate
					# Y uses RoomState.floor_line_y directly (world-space,
					# exactly like every other FarLayer/MidLayer piece) -
					# centered=false means position is this sprite's TOP-LEFT
					# corner, so subtracting its own rendered height anchors
					# its BOTTOM edge at floor_line_y, nudged by
					# painted_preview_mid_y_offset same as painted_preview_
					# fg_y_offset already nudges the foreground band.
					mid_sprite.position = Vector2(
						mid_placed_x,
						RoomState.floor_line_y - mid_target_height + painted_preview_mid_y_offset,
					)
					mid_layer.add_child(mid_sprite)

	# --- Ground strip: no new node - swapped directly into the Floor
	# polygon's existing texture slot (same texture_repeat/texture_scale
	# _position_floor() already set up for ground_texture, since
	# ground_texture_enabled stays true and that call already ran before
	# _build_background_layers()). Its top edge is floor_polygon's own top
	# edge, which is already pinned to RoomState.floor_line_y.
	#
	# vertex_colors cleared and color reset to WHITE (2026-09-06, ground-
	# tint fix) - BOTH of floor_polygon's own tint paths, cleared here so
	# the painted asset renders as authored instead of getting multiplied
	# by whichever one was left active: _apply_floor_depth_tint() (called
	# from _apply_standard_ground_treatment(), every room except the
	# opening one) sets vertex_colors to a top-to-bottom gradient toward
	# ~(0.79, 0.77, 0.75), and vertex_colors - once set - overrides the
	# flat .color property entirely, so clearing it alone would have been
	# enough there; the opening room never populates vertex_colors at all
	# (_apply_coastal_opening_room_layout() calls neither
	# _apply_standard_ground_treatment() nor _apply_floor_depth_tint()),
	# so for THAT room the flat OPENING_ROOM_SAND_COLOR in .color is what
	# actually applies - which is why .color also needs resetting here,
	# to cover both rooms with one pair of assignments instead of a room-
	# type branch. Neither _apply_floor_depth_tint() nor
	# OPENING_ROOM_SAND_COLOR is touched - both still run/apply exactly as
	# before when painted_preview_enabled is false; this only clears what
	# they left behind, and only inside this function.
	floor_polygon.vertex_colors = PackedColorArray()
	floor_polygon.color = Color.WHITE
	floor_polygon.texture = PAINTED_PREVIEW_GROUND_TEXTURE
	floor_polygon.modulate = painted_preview_ground_modulate

	# --- Foreground band: one or more Sprite2D children inside occluder_
	# layer itself (not a sibling layer), so they inherit that ParallaxLayer's
	# own occluder_layer_motion_scale (1.12) exactly, already set above. Same
	# camera-anchored bottom edge _populate_occluder_layer() uses for the
	# procedural band it replaces.
	#
	# No region_enabled/region_rect any more (2026-09-05, foreground-seam
	# fix) - PAINTED_PREVIEW_FOREGROUND_TEXTURE is foreground_band_
	# tileable.png, a true seamless tile at exactly 1920x290 (see its own
	# doc), so there's no narrower-than-viewport/off-by-a-transparent-sliver
	# content to crop down to an even width the way the old asset needed.
	#
	# TILED as repeated whole copies of the sprite, not stretched and not a
	# single sprite relying on motion_mirroring to repeat it (2026-09-06,
	# field-pull-back pass - REPLACES the single fg_sprite this used to be,
	# unscaled at exactly 1920 world units with motion_mirroring hardcoded
	# to match). That was correct ONLY because RoomState.room_width() used
	# to always equal 1920 (viewport_width() at the implicit zoom of 1.0) -
	# once RoomState.field_zoom could widen room_width() past that, nothing
	# ever filled world x past 1920: motion_mirroring only repeats a
	# ParallaxLayer's content as the CAMERA SCROLLS past a tile boundary,
	# and a single-screen room's camera (COMBAT/TREASURE - see follow_
	# enabled's own doc) never scrolls at all, so the second tile motion_
	# mirroring would eventually have drawn never got a chance to fire -
	# leaving a real gap in the band from room_width() 1920 onward, exactly
	# the bug this pass's own investigation traced to this line.
	#
	# Placing enough WHOLE tiles up front to cover the room's actual width
	# sidesteps that: every tile is a full, uncropped copy of a texture
	# that's authored to be seamless edge-to-edge, so there's no fractional-
	# tile cut anywhere for a join to look wrong at - the only "waste" is
	# the last tile's own right edge overhanging past room_width() into
	# space the wall/camera limit already keeps out of view, the same
	# harmless-overshoot idiom floor_overscan_margin_px/background_tile_
	# width already use elsewhere in this file. motion_mirroring is set to
	# RoomState.room_width() too, for a standard (scrolling) room - though
	# since these tiles already cover the room's full width up front, the
	# camera can never scroll far enough to need an actual repeat beyond
	# them; this only keeps the value itself honest rather than a stale
	# literal, not because anything still depends on it firing.
	#
	# Not cleaned up between repeated calls on the same instance (matches
	# the single-fg_sprite version this replaces, which had the same gap -
	# see painted_mid_layer's own doc for the one place in this function
	# that DOES guard against that, for a node re-populated on a dev-picker
	# room switch rather than a fresh scene load).
	#
	# fg_native_size.y is 290 - read fresh off the actual texture (never
	# hardcoded here), so the bottom-anchor math below needs no separate
	# adjustment if that ever changes: fg_visible_bottom_y - fg_native_
	# size.y lands the image's TOP 290px above the camera-anchored bottom
	# edge, so the image's own BOTTOM row (its full content, no transparent
	# margin above it on this asset) ends up flush with that bottom edge.
	var fg_native_size: Vector2 = PAINTED_PREVIEW_FOREGROUND_TEXTURE.get_size()
	occluder_layer.motion_mirroring = Vector2(RoomState.room_width(), 0.0)
	var fg_visible_bottom_y := camera.get_screen_center_position().y + viewport_size.y / 2.0
	var fg_y := fg_visible_bottom_y - fg_native_size.y + painted_preview_fg_y_offset
	var fg_tile_count := ceili(RoomState.room_width() / fg_native_size.x)
	for i in fg_tile_count:
		var fg_sprite := Sprite2D.new()
		fg_sprite.texture = PAINTED_PREVIEW_FOREGROUND_TEXTURE
		fg_sprite.centered = false
		fg_sprite.modulate = painted_preview_fg_color
		fg_sprite.position = Vector2(i * fg_native_size.x, fg_y)
		occluder_layer.add_child(fg_sprite)

	# --- Foreground masses (Track A, 2026-09-06 pass): discrete driftwood/
	# wrack/grass pieces scattered along occluder_layer, added AFTER the
	# base band tiles above as LATER siblings of that same layer - later
	# siblings draw on top, the same ordinary sibling-order rule every
	# other layer in this file already relies on - so these sit in front
	# of the flat repeated band rather than under it. These are the
	# "existing masses... sliced out... into discrete pieces" this pass's
	# own investigation report asked for, not a new shape of their own.
	#
	# load(), not preload() - same reasoning the mid-plate loop's own
	# plate textures already use (see that block's own doc): gated behind
	# painted_preview_enabled, only touches disk when this branch actually
	# runs, and null-checked rather than crashing the whole script if one
	# of the three is ever missing.
	var fg_mass_textures: Array[Texture2D] = []
	for fg_mass_path in [
		"res://assets/regions/beach/Foreground/fg_mass_wrack_mound_a.png",
		"res://assets/regions/beach/Foreground/fg_mass_driftwood_a.png",
		"res://assets/regions/beach/Foreground/fg_mass_grass_a.png",
	]:
		var fg_mass_texture: Texture2D = load(fg_mass_path)
		if fg_mass_texture != null:
			fg_mass_textures.append(fg_mass_texture)
	if not fg_mass_textures.is_empty():
		# Its own seed, distinct from the mid-plate loop's mid_rng (same
		# RunState.current_node.id source, different hash input) so a
		# room's foreground-mass roll and its mid-distance-plate roll
		# don't move in lockstep with each other.
		var fg_mass_rng := RandomNumberGenerator.new()
		fg_mass_rng.seed = hash(str(RunState.current_node.id) + ":fg_mass")
		# fg_y is the base band sprite's own TOP-LEFT corner - a
		# transparent margin, per this pass's own investigation report on
		# the raw asset (its solid body starts partway down, at a measured
		# MEDIAN 56px into the 290px-tall texture). Pieces are planted
		# relative to where the band's own mass actually starts, not its
		# transparent top, then sunk further by painted_preview_fg_mass_
		# overlap_px so their own base roots into that mass instead of
		# floating just above it.
		var band_body_top := fg_y + 56.0
		var fg_mass_bottom_y := band_body_top + painted_preview_fg_mass_overlap_px
		var fg_mass_count := ceili(RoomState.room_width() / 1920.0 * painted_preview_fg_mass_per_screen)
		var fg_mass_placed_centers: Array[float] = []
		for fg_mass_i in fg_mass_count:
			var fg_mass_texture: Texture2D = fg_mass_textures[fg_mass_rng.randi() % fg_mass_textures.size()]
			var fg_mass_scale: float = fg_mass_rng.randf_range(painted_preview_fg_mass_scale_min, painted_preview_fg_mass_scale_max)
			var fg_mass_rendered_size: Vector2 = fg_mass_texture.get_size() * fg_mass_scale
			var fg_mass_center_x := 0.0
			var fg_mass_found := false
			for fg_mass_attempt in 20:
				var fg_mass_candidate: float = fg_mass_rng.randf_range(0.0, RoomState.room_width())
				var fg_mass_conflict := false
				for placed_center in fg_mass_placed_centers:
					if absf(fg_mass_candidate - placed_center) < painted_preview_fg_mass_min_gap_px:
						fg_mass_conflict = true
						break
				if not fg_mass_conflict:
					fg_mass_center_x = fg_mass_candidate
					fg_mass_found = true
					break
			if not fg_mass_found:
				continue
			fg_mass_placed_centers.append(fg_mass_center_x)
			var fg_mass_sprite := Sprite2D.new()
			fg_mass_sprite.texture = fg_mass_texture
			fg_mass_sprite.centered = false
			fg_mass_sprite.flip_h = fg_mass_rng.randf() < 0.5
			fg_mass_sprite.scale = Vector2(fg_mass_scale, fg_mass_scale)
			fg_mass_sprite.modulate = painted_preview_fg_color
			fg_mass_sprite.position = Vector2(
				fg_mass_center_x - fg_mass_rendered_size.x / 2.0,
				fg_mass_bottom_y - fg_mass_rendered_size.y,
			)
			occluder_layer.add_child(fg_mass_sprite)

func _sky_band_height() -> float:
	return RoomState.floor_line_y - BACKGROUND_TOP_Y

# The horizon haze band (the shape pool below is empty as of the
# 2026-08-30 strip pass - see this function's own pool) - NO sky fill of
# its own any more (2026-08-24): the sky gradient moved to SkyLayer, a viewport-
# anchored CanvasLayer behind everything (see _build_sky_gradient()),
# since a true non-parallaxing full-viewport fill needs to NOT live
# inside a ParallaxLayer at all (a motion_scale of exactly zero doesn't
# reliably guarantee gap-free coverage as the camera pans the same way
# this layer's own tiling does at a nonzero scale - a CanvasLayer sidesteps
# that entirely). FarLayer now has NO fill of its own, same "no base rect,
# let what's behind show through the gaps" shape MidLayer already
# established (see _populate_mid_layer()'s own note on why that's what
# makes real depth read, not a hidden duplicate) - just extended one
# layer further back.
func _populate_far_layer(layer: ParallaxLayer) -> void:
	var floor_line_y := RoomState.floor_line_y

	# Clouds first (2026-08-30, cloud pass; still first after the
	# 2026-08-31 scattered-cloud rewrite - see _add_clouds()'s own doc for
	# the current technique) - drawn before EVERYTHING else this function
	# adds, landform included, so they sit behind the whole layer rather
	# than just behind the recession bands/haze that were this pass's own
	# explicit ask - the landform is a solid silhouette that belongs in
	# front of a formless atmospheric layer, not behind it, and "behind
	# everything else in that layer" was this pass's own broader framing.
	_add_clouds(layer)

	var band := _sky_band_height()
	var s := structure_scale
	# A single roll, not the old pool loop (2026-08-30 landform-variety
	# pass, REPLACING the previous "one guaranteed element per tile")
	# - far_structure_count is now just an on/off GATE (see landform_far_
	# chance's own doc): 0 in the opening room keeps it permanently
	# absent there exactly as before, >0 everywhere else lets the roll
	# happen at all. The pool/Array[Callable] indirection this used to
	# need (for choosing among several interchangeable Sunken Works
	# props) goes with it - there's been only one occupant since the
	# landform pass, so a direct conditional call is what that
	# indirection was always heading toward. cx formula UNCHANGED - off-
	# center in the tile, never centered, same as every landform pass
	# before this one required.
	#
	# Placed BEFORE the recession bands/haze below (2026-08-30 far-
	# landform-occlusion fix) - the landform used to be added last
	# specifically so it would draw on top of this layer's own bands, but
	# that only ever helped within FarLayer: it did nothing against
	# MidLayer, which draws its ENTIRE content over FarLayer's regardless
	# of internal ordering here (same CanvasLayer, MidLayer is the later
	# sibling - see field_room.tscn). Landform-behind-bands is also the
	# physically correct order regardless: the bands are the receding
	# ground plane, and ground in front of distant terrain should cover
	# its base as it recedes, not the other way around. See
	# _recession_mid_band_count()'s own doc for the other half of that
	# fix - fewer of those bands landing in MidLayer at all.
	if far_structure_count > 0 and randf() < landform_far_chance:
		var cx: float = background_tile_width * 0.25 + randf_range(-60.0, 60.0)
		_add_far_landform(layer, Vector2(cx, floor_line_y), band)

	# Bands still added BEFORE the haze (unchanged relative order) so the
	# haze (already in this layer) draws on top of whichever far-layer
	# band it overlaps - see recession_band_count's own doc.
	_add_far_recession_bands()
	_add_horizon_haze(layer, floor_line_y)

# Nearer structure silhouettes (2026-08-30 strip pass: the shape pool
# below is now empty - see this function's own pool - so nothing places
# here beyond the vegetation scattered independently at the end of this
# function). No base rect of its own - see _populate_far_layer()'s own
# note on why that's what actually makes FarLayer's sky and distant
# shapes visible through the space between these.
func _populate_mid_layer(layer: ParallaxLayer) -> void:
	var floor_line_y := RoomState.floor_line_y
	_add_mid_recession_bands()
	_add_horizon_edge()
	var band := _sky_band_height()
	var s := structure_scale
	# Crane/Gantry retuned down (2026-08-24 correction) - Crane's old
	# band*0.72*s resolved to ~774px tall against an ~860px sky band, so
	# a room that happened to roll it (each pool entry has ONE fixed
	# size, only WHICH shape gets picked is random - see this function's
	# own doc) spanned nearly the whole frame, reading as the subject
	# instead of background. Platform (band*0.34*s, ~365px) was always
	# the correctly-scaled reference - "the small plank" - Crane/Gantry
	# now land close to it instead of roughly double it. Pipe's thickness
	# also trimmed (0.05 -> 0.035 * band) for the same "reads as a beam,
	# not a slab" reason.
	#
	# A single roll, not the old pool loop (2026-08-30 landform-variety
	# pass) - see _populate_far_layer()'s own note for the full reasoning:
	# mid_structure_count is now an on/off gate rather than a literal
	# count, the pool/Array[Callable] indirection is gone since there's
	# only ever been one occupant, and the cx formula is UNCHANGED - off-
	# center in the tile, never centered.
	if mid_structure_count > 0 and randf() < landform_mid_chance:
		var cx: float = background_tile_width * 0.3 + randf_range(-80.0, 80.0)
		_add_mid_landform(layer, Vector2(cx, floor_line_y), band)

	# Scattered independently of structure placement now (structure pool
	# is empty - see this function's own pool above), and CLUSTERED rather
	# than evenly spaced (2026-08-30, clustering pass - Art Direction
	# Bible §14: grouped masses, not objects planted at intervals) -
	# REPLACES the old "evenly spaced across the tile width with per-clump
	# jitter" scheme, which is exactly what read as planted at intervals.
	# Same [0.1, 0.9] * tile-width span the even-spacing formula used to
	# keep clumps off the tile's own seams - only WHERE each clump lands
	# within that span changed, via _vegetation_cluster_x_positions() (see
	# its own doc for the full algorithm, shared with _add_seam_
	# vegetation()). vegetation_min_clumps floors the count (see its own
	# doc) - this room never gets fewer than that many even if vegetation_
	# per_structure is configured lower (it defaults to 1, well under it).
	var clump_count: int = maxi(vegetation_per_structure, vegetation_min_clumps)
	var veg_min_x: float = background_tile_width * 0.1
	var veg_max_x: float = background_tile_width * 0.9
	# Fixed Y (floor_line_y, no per-clump vertical range in this layer) -
	# so depth tint is a single fixed fade at t=0 (the far end), not a
	# gradient - see vegetation_depth_fade's own doc.
	var color := _depth_tinted_color(vegetation_color, 0.0, vegetation_depth_fade)
	for cx in _vegetation_cluster_x_positions(veg_min_x, veg_max_x, clump_count):
		_add_vegetation_clump(layer, Vector2(cx, floor_line_y), color)

# --- Landform (2026-08-30 landform pass; asset-based since the same day's
# landform-asset pass, REPLACING _landform_shape() - a hand-tuned
# multiplier table reads as a row of triangles, not the rounded/eroded
# terrain a generated asset can be) ---
#
# TERRAIN, not structures - headlands, low rises, rock outcrops (Bible
# §9: scale doesn't require complexity, one enormous memorable silhouette
# beats dozens of small objects; §14: mountains become silhouettes).
# Region 1 holds built structures near zero but says nothing about
# landform - these two functions are what actually fills the far/mid
# pools _populate_far_layer()/_populate_mid_layer() call into, replacing
# the industrial Sunken Works props (crane/gantry/platform/pipe) the
# 2026-08-30 strip pass removed. far_structure_color/mid_structure_color
# and far_structure_count/mid_structure_count are UNCHANGED exports,
# simply given real content again - see each color's own doc for why
# their contrast-floor headroom was already confirmed safe.
#
# Base-anchored at floor_line_y, the SAME contract _add_vegetation_
# clump() already uses for its own textures: centered = false, position
# = base minus the rendered size (X halved to stay centered on base.x,
# matching the procedural shape's own symmetric-around-base build; Y in
# full, so the rendered rect's bottom edge - not its top-left origin -
# lands exactly on the walk line). The assets' own bottom row is meant to
# be fully opaque so that landing is exact - spot-checked by direct pixel
# sampling for this pass: both have ~1 row of fully transparent padding
# at the absolute bottom edge before opacity picks up, a sub-pixel
# discrepancy at any scale these fractions actually produce, not a real
# gap.
#
# Sized via NON-UNIFORM Sprite2D.scale, one axis at a time from target_
# width/target_height - both landform_*_width_fraction and landform_*_
# height_fraction are honored EXACTLY, at the cost of not preserving
# either asset's own native aspect ratio (2163:221 far, 2166:510 mid).
# This matches the procedural shape it replaces, which took width/height
# as fully independent parameters with no aspect constraint of its own -
# reusing these exports was about keeping their EFFECT the same, not
# introducing a new aspect-locked constraint they never had.
#
# Random flip_h per instance (this pass's own brief - the same asset
# should not always present the same profile), no rotation - unrelated
# to the base-anchor math above since flip_h mirrors sampling within the
# same rendered rect, it doesn't change the rect's own bounds.
#
# base_y = floor_line_y for the MID landform (see _add_mid_landform()
# below) - it keeps planting exactly on the walk line, same as every
# other pool occupant this file has ever had there, and it's still drawn
# AFTER mid's own recession bands/edge (see _populate_mid_layer()'s own
# call order), so it draws IN FRONT of the value-steps behind it -
# correct, not incidental: the bands represent the receding ground
# plane, and a landmass sits on/above that plane, closer to the camera
# than the plane's own far reaches.
#
# The FAR landform is the one exception to "base_y = floor_line_y"
# (2026-08-30 far-base-lift pass): its base sits landform_far_base_lift
# px ABOVE floor_line_y instead - see that export's own doc for why (real
# terrain further away has its base higher in frame, because the ground
# itself recedes toward the horizon between the viewer and it - planting
# both landforms on the identical line read as a flat cut-out stack, not
# depth). It's also drawn BEFORE far's own recession bands/haze now (see
# _populate_far_layer()'s own call order and _recession_mid_band_count()'s
# doc, a SEPARATE fix for a SEPARATE problem - MidLayer erasing it from a
# different layer entirely) - so unlike the mid landform, the far one
# draws BEHIND the value-steps in front of it, which is what makes a
# raised, partially-obscured base read as receding rather than floating.

# See silhouette_vertical_shade's own @export_group doc above for the
# full rationale - this is the one place that doc's "modulate reduced to
# alpha-only, color moved into the shader" rule is actually enforced, so
# every caller (both landform functions, both foreground band instances,
# and now the treasure overhang) gets it applied identically instead of
# five separate copies of the same lighten/darken math.
#
# `invert` (2026-09-01, textured-overhang pass) - every existing caller
# wants the standard read (lighter top, darker bottom: Bible-consistent
# "light falls from above"), so this defaults to false and every one of
# them is unchanged. The treasure overhang is the first caller that wants
# the OPPOSITE: darker at top (the main mass, in shadow) and lighter at
# the bottom (the underside, catching ambient bounce light) - see its own
# treasure_overhang_shade doc for why. A parameter here rather than a
# second shader or a second sprite, per this pass's own brief - the
# lighten/darken MATH is identical either way, only which end gets which
# result changes.
func _apply_vertical_shade(sprite: Sprite2D, base_color: Color, shade: float, invert: bool = false, content_uv_top: float = 0.0, content_uv_bottom: float = 1.0) -> void:
	sprite.modulate = Color(1.0, 1.0, 1.0, base_color.a)
	var material := ShaderMaterial.new()
	material.shader = SILHOUETTE_VERTICAL_SHADE_SHADER
	if silhouette_shading_enabled:
		var lighter := base_color.lightened(shade)
		var darker := base_color.darkened(shade)
		material.set_shader_parameter("top_color", darker if invert else lighter)
		material.set_shader_parameter("bottom_color", lighter if invert else darker)
	else:
		material.set_shader_parameter("top_color", base_color)
		material.set_shader_parameter("bottom_color", base_color)
	# Defaults (0.0/1.0) match the shader's own uniform defaults, so every
	# existing caller that doesn't pass these keeps the original full-
	# texture ramp unchanged - see the shader's own doc for why a caller
	# WOULD pass non-default bounds (treasure_overhang.png's transparent
	# padding, via _add_treasure_overhang() below).
	material.set_shader_parameter("content_uv_top", content_uv_top)
	material.set_shader_parameter("content_uv_bottom", content_uv_bottom)
	sprite.material = material

func _add_far_landform(layer: ParallaxLayer, base: Vector2, band: float) -> void:
	if landform_far_texture == null:
		return
	# Width and height each rolled INDEPENDENTLY within +/-landform_size_
	# variation of their own fraction (2026-08-30 landform-variety pass) -
	# see that export's own doc for why independently, not together: two
	# separate randf_range() calls is what lets one instance land wide-
	# and-low while another lands narrower-and-taller, varying the
	# silhouette's own proportion instead of uniformly rescaling the same
	# shape bigger or smaller.
	var width_fraction := landform_far_width_fraction * randf_range(1.0 - landform_size_variation, 1.0 + landform_size_variation)
	var height_fraction := landform_far_height_fraction * randf_range(1.0 - landform_size_variation, 1.0 + landform_size_variation)
	var target_width := background_tile_width * width_fraction
	var target_height := band * height_fraction
	var native_size := landform_far_texture.get_size()
	var landform := Sprite2D.new()
	landform.texture = landform_far_texture
	landform.centered = false
	landform.flip_h = randf() < 0.5
	landform.scale = Vector2(target_width / native_size.x, target_height / native_size.y)
	_apply_vertical_shade(landform, far_structure_color, landform_vertical_shade)
	var rendered_size := native_size * landform.scale
	var base_y := base.y - landform_far_base_lift
	landform.position = Vector2(base.x - rendered_size.x / 2.0, base_y - rendered_size.y)
	layer.add_child(landform)

func _add_mid_landform(layer: ParallaxLayer, base: Vector2, band: float) -> void:
	if landform_mid_textures.is_empty():
		return
	# One random silhouette per instance (2026-08-31 landform-variety pass) -
	# same pick-by-index pattern as _add_vegetation_clump()'s own texture
	# pick below. Combined with flip_h just below, four variants give eight
	# distinct presentations per room roll.
	var texture: Texture2D = landform_mid_textures[randi() % landform_mid_textures.size()]
	# Same independent width/height roll as _add_far_landform() above -
	# see landform_size_variation's own doc, one shared knob for both
	# layers.
	var width_fraction := landform_mid_width_fraction * randf_range(1.0 - landform_size_variation, 1.0 + landform_size_variation)
	var height_fraction := landform_mid_height_fraction * randf_range(1.0 - landform_size_variation, 1.0 + landform_size_variation)
	var target_width := background_tile_width * width_fraction
	var target_height := band * height_fraction
	var native_size := texture.get_size()
	var landform := Sprite2D.new()
	landform.texture = texture
	landform.centered = false
	landform.flip_h = randf() < 0.5
	landform.scale = Vector2(target_width / native_size.x, target_height / native_size.y)
	_apply_vertical_shade(landform, mid_structure_color, landform_vertical_shade)
	var rendered_size := native_size * landform.scale
	landform.position = Vector2(base.x - rendered_size.x / 2.0, base.y - rendered_size.y)
	layer.add_child(landform)

# --- Ground recession bands (2026-08-30, ground recession pass) ---
#
# Band i's height is recession_band_top_y_offset / recession_band_count
# (the span divided evenly); its center sits band_height * (i + 0.5)
# above floor_line_y, so band 0 sits directly on the walk line and each
# later band stacks immediately above the last with no gap. t walks 0
# (band 0) toward 1 (one past the last band, never reached) as i climbs,
# same "i/count, not i/(count-1)" shape tide_band_contrast's own fade
# already uses - color lerps toward sky_gradient_horizon_color and alpha
# falls toward (but never hits) zero, so the topmost band stays a hair
# visible rather than vanishing outright.
# How many of the stack's bands (the LOWEST-i ones, closest to floor_
# line_y) go to MidLayer - the rest go to FarLayer. Was a flat half
# (recession_band_count / 2) until the 2026-08-30 far-landform-occlusion
# fix: with 6 bands that put 3 MidLayer bands (i=0,1,2, alpha 0.67-1.0)
# directly over the far landform's own Y range, and since MidLayer draws
# its ENTIRE content on top of FarLayer's (same CanvasLayer, MidLayer is
# the later sibling - see field_room.tscn), those 3 opaque-ish bands plus
# horizon_edge (always MidLayer, outside this split entirely) covered
# essentially the landform's whole height, erasing it regardless of its
# own correct color/position/draw-order within FarLayer. Only band 0 (the
# one literally on the walk line) stays in MidLayer now - the rest move
# to FarLayer, where the far-landform reorder below means they draw
# BEHIND it instead of erasing it from a different layer entirely. Still
# preserves the "near bands = mid's faster parallax, far bands = far's
# slower parallax" principle _add_far_recession_bands()'s own doc
# describes - this only moves where the near/far boundary sits within
# the stack, it doesn't remove the split. A single shared function
# instead of the split computed independently in three places (as it
# used to be) - three copies of the same formula is exactly how a future
# retune could change it in one place and not the other two.
func _recession_mid_band_count() -> int:
	return maxi(1, recession_band_count / 4)

func _add_recession_band(i: int) -> void:
	var band_height := recession_band_top_y_offset / float(recession_band_count)
	var t: float = float(i) / float(recession_band_count)
	var color := recession_band_color.lerp(sky_gradient_horizon_color, t)
	color.a = 1.0 - t
	var y_center := RoomState.floor_line_y - band_height * (i + 0.5)
	var parent: Node2D = background_mid if i < _recession_mid_band_count() else background_far
	_add_wavy_band(y_center, band_height, color, recession_band_wave_amplitude, 0.0, background_tile_width, parent)

# The nearer share of the stack (lowest i, closest to floor_line_y - see
# _recession_mid_band_count() for exactly how many bands that is) moves
# with the mid layer's faster parallax; the rest, closer to the true
# horizon, move with the far layer's slower one - parallax speed carries
# the "closer things move more" depth cue that a static value stack alone
# can't. Two entry points, not one shared loop, so each populate function
# can place its own share at the point in its own draw order it needs
# (see _populate_far_layer()'s call site for why its share now lands
# AFTER the landform instead of before - drawing the receding ground
# plane over the landform's own base, not the landform over the plane).
func _add_far_recession_bands() -> void:
	if not recession_bands_enabled:
		return
	for i in range(_recession_mid_band_count(), recession_band_count):
		_add_recession_band(i)

func _add_mid_recession_bands() -> void:
	if not recession_bands_enabled:
		return
	for i in _recession_mid_band_count():
		_add_recession_band(i)

# See horizon_edge_height's own doc for why the band is centered above
# floor_line_y (not on it) and why wave_amplitude is bounded by half of
# horizon_edge_height - both are load-bearing for reading as a clean
# edge instead of a self-crossing sliver of noise.
func _add_horizon_edge() -> void:
	if not horizon_edge_enabled:
		return
	assert(horizon_edge_wave_amplitude <= horizon_edge_height / 2.0, "horizon_edge_wave_amplitude (%s) must not exceed horizon_edge_height / 2.0 (%s) - see horizon_edge_height's own doc: past that point each segment's top/bottom jitter ranges overlap enough that the polygon can self-cross instead of just wobbling." % [horizon_edge_wave_amplitude, horizon_edge_height / 2.0])
	var y_center := RoomState.floor_line_y - horizon_edge_height / 2.0
	_add_wavy_band(y_center, horizon_edge_height, horizon_edge_color, horizon_edge_wave_amplitude, 0.0, background_tile_width, background_mid)

# --- Sky gradient (see sky_gradient_top_color/sky_gradient_horizon_color's
# own doc for why this lives in SkyLayer, not a ParallaxLayer) ---
#
# Built fresh every room load, same as every other background element
# here - a Gradient wrapped in a GradientTexture2D, assigned directly to
# sky_rect.texture. THREE stops, not two (2026-08-24, second correction -
# see sky_warm_band_fraction's own doc for why a plain 2-stop gradient
# wasn't enough): top_color at 0.0, top_color AGAIN at (1 - sky_warm_
# band_fraction) - a flat run with no color change in between, since
# interpolating between two identical colors is a no-op - then horizon_
# color at 1.0. Still just the two exported colors, no third color to
# tune - the middle point reuses sky_gradient_top_color verbatim, it
# only exists to PIN where the warm interpolation starts.
#
# fill_to.y is RoomState.floor_line_y's own fraction of the viewport
# height, NOT a bare 1.0 (2026-08-24 fix) - SkyRect fills the WHOLE
# viewport (see field_room.tscn), but the true horizon sits at floor_
# line_y, well short of the viewport's bottom edge (900 of 1080 here).
# A bare 1.0 meant the gradient only reached ~83% of the way to sky_
# gradient_horizon_color by the time it actually reached the seam - the
# last stretch was wasted below floor_line_y, entirely hidden under
# Floor. This is what makes the seam actually MEET
# sky_gradient_horizon_color exactly at the line horizon_haze's own
# color is drawn from, instead of some slightly-short intermediate
# blend. Safe to key off the viewport's CURRENT size (not a hardcoded
# 1080) since this rebuilds fresh every room load, same as everything
# else background-related here.
func _build_sky_gradient() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, sky_gradient_top_color)
	gradient.set_color(1, sky_gradient_horizon_color)
	var warm_band_start: float = clampf(1.0 - sky_warm_band_fraction, 0.0, 1.0)
	gradient.add_point(warm_band_start, sky_gradient_top_color)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var horizon_fraction: float = RoomState.floor_line_y / maxf(viewport_height, 1.0)
	texture.fill_to = Vector2(0.5, horizon_fraction)
	sky_rect.texture = texture

# A signed brightness shift - positive lightens toward white, negative
# darkens toward black, via the same symmetric pair of named Godot
# operations (Color.lightened()/darkened()) rather than two separate
# ad-hoc formulas. Needed because sky_light_direction is genuinely
# bidirectional (which side of the horizon reads bright vs dim depends
# on its own sign) - routing both directions through one function
# guarantees they're exact mirrors of each other, not two independently-
# tuned constants that could drift apart.
func _signed_shade(base: Color, amount: float) -> Color:
	if amount > 0.0:
		return base.lightened(amount)
	elif amount < 0.0:
		return base.darkened(-amount)
	return base

# The horizontal counterpart to the vertical sky gradient above (2026-
# 08-30 light-direction pass) - Bible §6 ("the atmosphere itself may
# sometimes appear faintly luminous without an obvious directional
# source") as a faint left-right asymmetry in the horizon color, not a
# light source of any kind (no sun, no rays - see sky_light_direction's
# own doc). GradientTexture2D can only fill along ONE line (sky_rect's
# own gradient above is purely vertical), so this is a SEPARATE overlay
# rather than a change to that texture - one 4-vertex Polygon2D whose
# vertex_colors carry BOTH axes at once: horizontally, the left/right
# vertex pairs get the shifted bright/dim colors; vertically, the TOP
# edge is fully transparent and the BOTTOM edge (floor_line_y) is fully
# opaque, so the effect fades in smoothly rather than starting at a hard
# line - reaching full strength exactly where the base gradient's own
# horizon_color stop does (top_y below is that SAME warm_band_start
# point, in world Y, _build_sky_gradient() already computes
# independently - reused here rather than a second hand-picked
# threshold, so "apply to the horizon stop only" is enforced by sharing
# the real boundary, not by guessing a similar-looking one).
#
# Added to sky_layer AFTER sky_rect (draws on top of it), but BEFORE the
# tower (see _build_background_layers()'s own call order) - the tower is
# added after this and lives at the same CanvasLayer, so it draws on top
# and is never tinted by it.
func _add_sky_light_gradient() -> void:
	if not sky_light_enabled or sky_light_direction == 0.0:
		return
	var left_color := _signed_shade(sky_gradient_horizon_color, -sky_light_direction * sky_light_strength)
	var right_color := _signed_shade(sky_gradient_horizon_color, sky_light_direction * sky_light_strength)
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var horizon_fraction: float = RoomState.floor_line_y / maxf(viewport_height, 1.0)
	var warm_band_start: float = clampf(1.0 - sky_warm_band_fraction, 0.0, 1.0)
	var top_y := warm_band_start * horizon_fraction * viewport_height
	var bottom_y := RoomState.floor_line_y
	var rect := Polygon2D.new()
	rect.color = Color(1.0, 1.0, 1.0, 1.0)
	rect.polygon = PackedVector2Array([
		Vector2(0.0, top_y), Vector2(viewport_width, top_y),
		Vector2(viewport_width, bottom_y), Vector2(0.0, bottom_y),
	])
	var left_transparent := Color(left_color.r, left_color.g, left_color.b, 0.0)
	var right_transparent := Color(right_color.r, right_color.g, right_color.b, 0.0)
	rect.vertex_colors = PackedColorArray([left_transparent, right_transparent, right_color, left_color])
	sky_layer.add_child(rect)

# A single fixed silhouette, not part of any shape pool - see tower_
# enabled's own doc (above sky_layer's own @onready declaration) for why
# this lives in SkyLayer rather than FarLayer. Deterministic, not
# randomized: every other silhouette in this file is re-rolled per room
# load, but a landmark that's supposed to read as the SAME landmark every
# time it's seen can't be.
#
# Drawn on top of the sky gradient (added as a later child of sky_layer,
# after sky_rect - draw order within one CanvasLayer follows child
# order), but BEHIND the horizon haze and everything else in the room:
# SkyLayer is a CanvasLayer with layer = -100 (see field_room.tscn),
# while Background/FarLayer (where the haze lives, _add_horizon_haze())
# has no CanvasLayer of its own and so renders at the implicit default
# layer 0 - CanvasLayers composite in ascending `layer` order, so -100
# draws before (behind) 0. The haze's own vertex_colors fade to
# horizon_haze_alpha (0.35, not fully opaque) at floor_line_y, so this
# softens the tower's base rather than erasing it - confirmed by the
# layer values above, not assumed.
#
# Seven points (within the 6-8 budget), tapering base-to-top by tower_
# taper, with a handful of fixed asymmetric multipliers (0.6, 0.68, 0.9,
# 0.92, 1.15, etc. below) on top of that taper so the outline reads as
# an irregular mass rather than a symmetric triangle/trapezoid (Bible
# §1 - shape before detail, still no actual ornament added). Hand-picked
# constants, not exported - this is placeholder geometry meant to
# establish placement/proportion/value (this pass's own brief), not a
# tunable shape language of its own.
func _add_tower_silhouette() -> void:
	if not tower_enabled:
		return
	# See tower_height_fraction_start/_end's own doc for why this is an
	# interpolation rather than a flat fraction, and why the range it
	# interpolates across is deliberately narrow. RoomState.region_progress
	# is already 0.0 for the opening room (see that field's own doc), so
	# this needs no separate opening-room branch of its own.
	var height_fraction := lerpf(tower_height_fraction_start, tower_height_fraction_end, RoomState.region_progress)
	var height := height_fraction * _sky_band_height()
	var base_half_width := tower_width_fraction * height / 2.0
	var top_half_width := base_half_width * tower_taper
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	var cx := tower_screen_x_fraction * viewport_width
	var base_y := RoomState.floor_line_y
	var top_y := base_y - height

	var tower := Polygon2D.new()
	tower.color = tower_color
	tower.polygon = PackedVector2Array([
		Vector2(cx - base_half_width, base_y),
		Vector2(cx + base_half_width * 0.92, base_y),
		Vector2(cx + base_half_width * 0.6, base_y - height * 0.42),
		Vector2(cx + top_half_width * 1.15, base_y - height * 0.82),
		Vector2(cx + top_half_width * 0.15, top_y),
		Vector2(cx - top_half_width * 0.9, base_y - height * 0.8),
		Vector2(cx - base_half_width * 0.68, base_y - height * 0.4),
	])
	sky_layer.add_child(tower)

# TREASURE's own overhang (2026-08-31, treasure-overhang pass; textured
# 2026-09-01) - a dark mass hanging from the top of the frame, so a static
# single-screen TREASURE room (see field_room.gd's own _is_single_screen_
# room()) reads as a sheltered spot rather than open ground with chests on
# it. Called ONLY from _build_background_layers()'s own single TREASURE
# branch - see that function's own doc for why this is the one place a
# room-type check exists there at all.
#
# A single Sprite2D showing treasure_overhang_texture, uniformly scaled
# from treasure_overhang_content_height_px (2026-09-01, textured-overhang
# pass - REPLACES the procedural _irregular_blob_shape() mass and the
# hand-drawn-polygon override that briefly replaced it, both removed -
# see this pass's own investigation report for what either looked like;
# content_height_px itself renamed from treasure_overhang_height_px in a
# later overhang-contrast pass - see its own doc for why).
#
# STILL ANCHORED to content_root (motion scale 1.0, no parallax) rather
# than any background ParallaxLayer, unchanged from the original pass's
# own explicit brief - the interactables it shelters live there too (see
# room_state.gd's own _generate_treasure_layout()), so both move at the
# exact same rate relative to the (now-static) camera; a parallaxed
# version would drift out of alignment with the very thing it's supposed
# to be sheltering. content_root is declared before Player in field_room.
# tscn, so this STILL draws behind the player by ordinary sibling order -
# no z_index needed, unchanged.
#
# centered = false (see field_room.tscn) - `position` is the texture's own
# top-left corner, same convention _populate_occluder_layer()'s own band
# already uses. Vertical: the texture's own top edge lands at BACKGROUND_
# TOP_Y + treasure_overhang_y_offset_px (offset added in the overhang-
# contrast pass, default 0.0 so this is BACKGROUND_TOP_Y directly unless
# retuned) - the asset's own opaque content already starts almost
# immediately below its own y=0 (y~16 of 941, a small margin), so unlike
# the old radially-symmetric procedural blob (which needed to straddle
# that line, half above/half below), this asset needs no such split.
# Horizontal: centers the TEXTURE's own span (not the asymmetric opaque
# content's own visual center) on treasure_overhang_center_ratio * _room_
# width() - a plain mechanical anchor, not a derived one; see that
# export's own doc for why deriving "correct" alignment automatically is
# explicitly not wanted here.
func _add_treasure_overhang() -> void:
	treasure_overhang_shape.visible = treasure_overhang_enabled
	if not treasure_overhang_enabled or treasure_overhang_texture == null:
		return
	treasure_overhang_shape.texture = treasure_overhang_texture
	_apply_vertical_shade(treasure_overhang_shape, treasure_overhang_color, treasure_overhang_shade, true, treasure_overhang_content_uv_top, treasure_overhang_content_uv_bottom)
	var native_size := treasure_overhang_texture.get_size()
	var content_native_height := (treasure_overhang_content_uv_bottom - treasure_overhang_content_uv_top) * native_size.y
	var scale_factor := treasure_overhang_content_height_px / content_native_height
	treasure_overhang_shape.scale = Vector2(scale_factor, scale_factor)
	var center_x := RoomState.room_width() * treasure_overhang_center_ratio
	treasure_overhang_shape.position = Vector2(center_x - (native_size.x * scale_factor) / 2.0, BACKGROUND_TOP_Y + treasure_overhang_y_offset_px)

# Soft ground darkening under the overhang (2026-09-02, ground-shade pass) -
# the overhang blocks diffuse sky light, so the sand beneath it reads
# darker; broad and soft, NOT a hard-edged cast shadow. Called right after
# _add_treasure_overhang() above, in the same TREASURE branch of _build_
# background_layers() - relies on treasure_overhang_shape's position/scale
# already being final for this room build, so it can never run first.
#
# A free-standing Sprite2D using EntityShadow.SHADOW_TEXTURE directly
# (contact_shadow.png, the same 512x192 soft white ellipse every contact
# shadow in the game already uses) - deliberately NOT EntityShadow.attach():
# that API measures an attached entity's own real rendered bounds via
# VisualBounds, and there is no entity here, just the overhang's already-
# known extent. Positioned/scaled directly instead.
#
# Width/center-x are derived from the overhang's own OPAQUE content x
# extent, not its full padded texture - same 430/1671 native-x bounds
# _add_treasure_overhang()'s own texture doc already establishes (measured
# directly against the asset), reapplied here against treasure_overhang_
# shape's CURRENT position/scale rather than hardcoded as fixed pixels, so
# this patch keeps tracking the overhang if its own placement/size is ever
# retuned.
#
# Scaled NON-uniformly (width and height independently) to hit width_px/
# height_px exactly - unlike the belongings' own shared-uniform-scale rule
# (which exists to preserve THEIR painted aspect ratio), this asset is a
# soft radial falloff with no painted detail to distort, so squashing it
# flat to read as a broad, near-edge-on ground patch is the correct,
# intended use of the same texture, not a mistake repeating the belongings'
# own constraint.
#
# modulate-only tint (treasure_ground_shade_color, alpha included) - the
# source texture is white specifically so modulate can only ever darken
# it, never brighten past white, same reasoning EntityShadow's own SHADOW_
# TEXTURE doc already states for the identical asset. No shader, no
# palette read - see that export's own doc for why it's deliberately
# exempt from _validate_background_contrast()'s registers.
#
# move_child(0) after adding, not left at whatever index add_child() gives
# it (2026-09-02) - content_root already holds TreasureOverhangShape (a
# fixed scene child) and, by this point in _ready(), every floor patch/
# crack/tide-band/seam-debris/vegetation piece _apply_standard_ground_
# treatment() already spawned (that function runs BEFORE _build_
# background_layers() - see _ready()'s own call order) - a plain append
# would draw this ON TOP of all of that, the opposite of the brief. index
# 0 forces it behind every sibling regardless of add order, the exact same
# technique EntityShadow.attach()'s own use_sibling_index_zero already
# uses elsewhere - not a z_index (none introduced), pure sibling order.
# The belongings (_generate_room_contents(), later still in _ready()) are
# unaffected either way - they don't exist yet when this runs, so they can
# only ever land AFTER this patch regardless of index.
func _add_treasure_ground_shade() -> void:
	if not treasure_overhang_enabled or treasure_overhang_texture == null:
		return
	var opaque_left_x := treasure_overhang_shape.position.x + 430.0 * treasure_overhang_shape.scale.x
	var opaque_right_x := treasure_overhang_shape.position.x + 1671.0 * treasure_overhang_shape.scale.x
	var overhang_center_x := (opaque_left_x + opaque_right_x) / 2.0
	var width_px := (opaque_right_x - opaque_left_x) * treasure_ground_shade_spread

	var shade := Sprite2D.new()
	shade.texture = EntityShadow.SHADOW_TEXTURE
	shade.modulate = treasure_ground_shade_color
	var native_size := EntityShadow.SHADOW_TEXTURE.get_size()
	shade.scale = Vector2(width_px / native_size.x, treasure_ground_shade_height_px / native_size.y)
	shade.position = Vector2(
		overhang_center_x + treasure_ground_shade_center_x_offset,
		RoomState.floor_line_y + treasure_ground_shade_center_y_offset,
	)
	content_root.add_child(shade)
	content_root.move_child(shade, 0)

# A non-interactive prop: cloth laid flat on the sand, the three
# belongings resting on it (2026-09-02, groundsheet pass). Called right
# after _add_treasure_ground_shade() above, in the same TREASURE branch of
# _build_background_layers() - so it lands in content_root BEFORE the
# three belongings (_generate_room_contents(), later still in _ready() -
# see that function's own call order), same reasoning _add_treasure_
# ground_shade()'s own doc already gives, but no move_child(0) forcing
# here: nothing says it needs to draw beneath the shade patch or the
# floor decoration _apply_standard_ground_treatment() already added, only
# beneath the belongings, which plain append order already guarantees on
# its own.
#
# A plain Sprite2D, not a FieldChest - no Area2D, no collider, no prompt,
# no reward, no interaction of any kind, per this pass's own brief. No
# modulate override either - the source PNG is a painted plate with baked
# color and value, same bare-sprite treatment (_build_belonging_sprite())
# the three belongings already get, deliberately never routed through
# silhouette_vertical_shade.gdshader or any palette tint.
#
# Horizontal center is the midpoint of the three belongings' own REAL x
# positions - chest position.x + belonging_offset.x each, not the bare
# chest/Area2D origins - read straight from RoomState.room_layout, which
# is already fully populated by the time this runs (RoomState.load_room()
# computes it BEFORE the scene transition that loads this scene at all -
# see that function's own doc). Has to read it this way rather than
# measuring live belonging sprites the way the prompt anchor does
# (VisualBounds.compute_bottom_slice()): the belongings don't exist yet at
# this point in _ready() (_generate_room_contents() runs later) - this
# function runs BEFORE them, not after.
#
# Scaled UNIFORMLY (both axes from one width, unlike the ground shade
# patch's deliberate non-uniform stretch) - this is a painted asset with
# real proportions to preserve, the same "one shared scale factor, aspect
# intact" rule the belongings themselves already follow, not a soft
# radial mask where distortion is harmless.
#
# centered = false, position = the sprite's own top-left corner (same
# convention every other texture asset in this file already uses) -
# bottom edge placed at floor_line_y + treasure_groundsheet_bottom_y_
# offset (see that export's own doc for why it's the NEAR edge, not a
# contact point), so position.y is that bottom minus the sprite's own
# rendered height.
#
# No contact shadow - EntityShadow models an object resting ON the
# ground; this asset IS the ground (a flat surface seen near-edge-on), so
# a shadow drawn beneath it would read as a second, wrong surface under a
# surface, per this pass's own brief.
func _add_treasure_groundsheet() -> void:
	if treasure_groundsheet_texture == null:
		return
	var min_x := INF
	var max_x := -INF
	for entry in RoomState.room_layout:
		if entry.get("kind") != "chest":
			continue
		var belonging_offset: Vector2 = entry.get("belonging_offset", Vector2.ZERO)
		var belonging_x: float = entry["position"].x + belonging_offset.x
		min_x = minf(min_x, belonging_x)
		max_x = maxf(max_x, belonging_x)
	var center_x := treasure_groundsheet_center_x_offset
	if min_x != INF:
		center_x += (min_x + max_x) / 2.0

	var sheet := Sprite2D.new()
	sheet.texture = treasure_groundsheet_texture
	sheet.centered = false
	# No modulate override here - painted plate, baked color/value, same
	# treatment as the belongings' own bare Sprite2D (see this function's
	# own doc above).
	var native_size := treasure_groundsheet_texture.get_size()
	var scale_factor := treasure_groundsheet_width_px / native_size.x
	sheet.scale = Vector2(scale_factor, scale_factor)
	var rendered_height := native_size.y * scale_factor
	var bottom_y := RoomState.floor_line_y + treasure_groundsheet_bottom_y_offset
	sheet.position = Vector2(center_x - (native_size.x * scale_factor) / 2.0, bottom_y - rendered_height)
	content_root.add_child(sheet)

# Composition-test placeholder - a foreground framing mass at the room's
# left edge (2026-09-02, foreground-rock pass; made hand-editable same
# day, foreground-rock-editability pass - REPLACES this function's own
# prior _irregular_blob_shape()-generated polygon with a fixed, hand-
# authored one, see treasure_foreground_rock_shape's own @onready doc for
# why). Shape quality still doesn't matter yet, only placement/coverage/
# value, per this pass's own original brief - this function only ever
# positions/scales the node now, it never touches `.polygon`.
#
# treasure_foreground_rock_shape's own authored bounding box is measured
# ONCE here, then fit to target_width x target_height via a non-uniform
# Node2D.scale (not a polygon-point rewrite) - the exact same "measure
# the authored asset's own extent, then scale/position to hit a target"
# shape every Sprite2D-based element in this file already uses (the
# belongings, the overhang, the groundsheet), just applied to a Polygon2D
# instead of a texture. Whatever the artist draws in the 2D editor keeps
# its own proportions; this only ever stretches/positions the WHOLE shape
# to fit the box, never distorts individual points differently from each
# other beyond that one shared scale.
#
# Anchored to the LEFT edge of the actual VIEWPORT (via the camera's own
# screen_center_position, the same "derive the true visible edge from the
# camera" technique _populate_occluder_layer() already uses for the
# bottom edge - see that function's own doc) - the bbox's own horizontal
# center lands EXACTLY on that edge, so half the shape's own bounding box
# sits off-frame to the left (the "running off it" the brief asks for)
# and half is visible. Bottom of the bbox lands on the same camera-
# derived visible-bottom edge, rising up from there.
#
# z_index = 1 on this ONE node, nothing else (2026-09-02) - the only way
# to actually satisfy "insert into content_root... after the player's
# draw position... so it occludes them": content_root (Content, sibling
# index 12 in field_room.tscn) is an EARLIER sibling than Player (index
# 13) at the ROOT level, so no amount of reordering WITHIN content_root's
# own children can ever draw this over the player through sibling order
# alone - Content as a whole always draws before Player regardless. A
# local z_index override on just this node is what actually wins the
# player (z_index 0, the project-wide default) without touching content_
# root's own z_index (which would reorder every OTHER child - belongings,
# overhang, groundsheet, ground shade, floor decoration - against Player
# too, far outside this pass's own scope). Lives under Content in field_
# room.tscn (a fixed child, not appended at runtime any more), still
# earlier than the belongings in that list (_generate_room_contents()
# runs later in _ready() - see that function's own call site) regardless
# of this doc's own "after the belongings" placement brief; z_index is
# what makes it draw over them instead, the same mechanism that gets it
# over the player.
#
# Flat fill only - no shader, no _apply_vertical_shade() ramp, no
# texture, per this pass's own explicit brief. No collision either - a
# placeholder for composition, not a solid the player should be blocked
# by; it should read as something the player walks BEHIND, which needs no
# collider at all, only the draw-order/z_index work above.
func _add_treasure_foreground_rock() -> void:
	treasure_foreground_rock_shape.visible = treasure_foreground_rock_enabled
	if not treasure_foreground_rock_enabled:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target_width := viewport_size.x * treasure_foreground_rock_width_fraction
	var target_height := viewport_size.y * treasure_foreground_rock_height_fraction
	var screen_center := camera.get_screen_center_position()
	var left_edge_x := screen_center.x - viewport_size.x / 2.0
	var bottom_edge_y := screen_center.y + viewport_size.y / 2.0

	var raw_points: PackedVector2Array = treasure_foreground_rock_shape.polygon
	var raw_min := Vector2(INF, INF)
	var raw_max := Vector2(-INF, -INF)
	for p in raw_points:
		raw_min.x = minf(raw_min.x, p.x)
		raw_min.y = minf(raw_min.y, p.y)
		raw_max.x = maxf(raw_max.x, p.x)
		raw_max.y = maxf(raw_max.y, p.y)
	var raw_size := raw_max - raw_min
	var fit_scale := Vector2(target_width / raw_size.x, target_height / raw_size.y)

	treasure_foreground_rock_shape.color = treasure_foreground_rock_color
	treasure_foreground_rock_shape.scale = fit_scale
	treasure_foreground_rock_shape.position = Vector2(left_edge_x - target_width / 2.0, bottom_edge_y - target_height) - raw_min * fit_scale
	treasure_foreground_rock_shape.z_index = 1

# The seam-killer (see horizon_haze_height/horizon_haze_alpha's own doc).
# vertex_colors, not a flat Polygon2D.color - Godot interpolates per-
# vertex colors across the polygon's fill, which is what gives this a
# real soft top-to-bottom fade (fully transparent at the top edge, full
# horizon_haze_alpha at the bottom, right on the seam) using nothing but
# a flat 4-point rect, same "simple primitives only" language every other
# shape here already follows - no shader needed. .color is left at plain
# white so it never modulates the per-vertex colors below it.
func _add_horizon_haze(layer: ParallaxLayer, floor_line_y: float) -> void:
	var haze := Polygon2D.new()
	haze.color = Color(1, 1, 1, 1)
	var top_y := floor_line_y - horizon_haze_height
	haze.polygon = PackedVector2Array([
		Vector2(0, top_y), Vector2(background_tile_width, top_y),
		Vector2(background_tile_width, floor_line_y), Vector2(0, floor_line_y),
	])
	var opaque := Color(sky_gradient_horizon_color.r, sky_gradient_horizon_color.g, sky_gradient_horizon_color.b, horizon_haze_alpha)
	var transparent := Color(opaque.r, opaque.g, opaque.b, 0.0)
	haze.vertex_colors = PackedColorArray([transparent, transparent, opaque, opaque])
	layer.add_child(haze)

# --- Particulates (this pass's own brief) - sparse drifting motes, two
# depth bands (see the @export group's own doc for far/near). One shared
# populate function, called once per band with that band's own count/
# color/drift speed - same "one function, different arguments per call"
# shape _populate_far_layer()/_populate_mid_layer() already established
# for far/mid structures. Each mote is a tiny irregular blob (reuses
# _irregular_blob_shape(), same "not a texture" vocabulary as ground
# patches/seam debris - left on the blob generator per this pass's own
# brief, since shape is irrelevant at a 2-3px particulate size) with
# field_particulate.gd attached for its own ambient drift -
# see that script for why drift is independent of this layer's own
# motion_scale. Scattered across the FULL vertical band (top to floor
# line), not just near the structures - motes drifting through open sky
# is the point, not motes clustered near the silhouettes.
func _populate_particulate_layer(layer: ParallaxLayer, count: int, color: Color, drift_speed_px_sec: float) -> void:
	var floor_line_y := RoomState.floor_line_y
	for i in count:
		# FieldParticulate extends Polygon2D itself (see field_particulate.
		# gd) rather than being a second node wrapping a plain Polygon2D -
		# simplest way to get "this node animates itself" without an extra
		# layer of nesting per mote. set_script() on a plain Polygon2D.new()
		# (not preloading/instancing a whole mote .tscn) matches how every
		# other shape in this vocabulary is built - fields set directly on
		# a freshly-made node, not an instanced scene. Deliberately `var
		# mote =`, NOT `:=` - `:=` would statically type mote as plain
		# Polygon2D (inferred from Polygon2D.new()'s own return type),
		# which has no drift_speed_px_sec/wrap_width of its own; the
		# script attaching them is a RUNTIME effect the static analyzer
		# can't see, so the untyped form is what lets the two lines below
		# actually compile instead of erroring on an unknown member.
		var mote = Polygon2D.new()
		mote.set_script(FIELD_PARTICULATE_SCRIPT)
		mote.color = color
		mote.polygon = _irregular_blob_shape(particulate_radius)
		mote.position = Vector2(randf_range(0.0, background_tile_width), randf_range(0.0, floor_line_y))
		mote.drift_speed_px_sec = drift_speed_px_sec
		mote.wrap_width = background_tile_width
		layer.add_child(mote)

# --- Foreground occluders (foreground_occluders_enabled's own doc) -
# a single tiling Sprite2D built from foreground_band_texture (2026-08-30
# generated-asset pass, REPLACING the per-instance procedural shapes
# this layer used to build - they read as geometric spikes and slabs at
# foreground scale, ~200px+, even though the same technique works fine
# at the ~20-30px ground-decoration scale it was built for
# (_irregular_blob_shape() still does exactly that job for ground
# patches/seam debris); a generated texture replaces them entirely
# rather than being tuned further). Bible §10/§5: foreground framing is
# its own layer, darkest values, strong silhouettes, limited internal
# information - one continuous dark strip IS that, more directly than
# many small shapes ever were.
#
# Sized via region_rect + texture_repeat rather than texture_scale alone
# (same "vertex/region position acts as a texture-space pixel coordinate,
# texture_repeat wraps it" technique _position_floor() already uses for
# the ground texture) - region_rect spans background_tile_width/scale_
# factor texture-pixels wide (so the RENDERED width, after Sprite2D.scale
# is applied, comes out to exactly background_tile_width) at the
# texture's own native height (no vertical tiling - the asset is meant to
# show once per row, not repeat top-to-bottom). scale_factor is derived
# from `band_height` ONLY, applied uniformly to both axes, so the
# asset's own 2172:294 aspect ratio is preserved rather than stretched -
# width tiles at whatever period that same scale implies.
#
# Parameterized (2026-08-30 foreground-depth pass) rather than reading
# foreground_band_height/_overshoot/occluder_color directly, so the same
# function builds both the near instance (occluder_layer) and the
# further-back one (occluder_far_layer, its own height/overshoot/tint,
# and offset_x so its tile content doesn't align with the near band's
# identical texture - see foreground_band_far_offset_x's own doc for why
# a plain position shift is sufficient) without duplicating this logic.
func _populate_occluder_layer(layer: ParallaxLayer, band_height: float, band_overshoot: float, offset_x: float, tint: Color) -> void:
	# Same condition _apply_coastal_opening_room_layout() already uses -
	# the coastal band (a wrack line) is opening-room-only, every other
	# room gets either band, picked below by the region gradient. Runs the
	# FULL tile width either way, with no shore-line bound - unlike the
	# coastal ground decoration functions (_add_coastal_seam_debris()
	# etc.), a wrack line sitting in front of the water's edge, past the
	# shore, is correct here. Both instances (near and far) share this
	# same selection - there is only one texture per room, not a separate
	# near/far asset pair.
	#
	# Region gradient (2026-08-31 wet-to-dry pass) - below foreground_
	# band_crossover, the wrack line still implies a reachable tide (true
	# early in the region); at or above it, that implication would be
	# false, so the plain grass band takes over instead. The opening room
	# is checked FIRST and wins regardless of the gradient - see the
	# Region Gradient export group's own doc for why that's still correct
	# even though its own gradient value already happens to land below
	# the crossover.
	var use_coastal_band := RunState.current_node == RunState.opening_node
	if not use_coastal_band and region_gradient_enabled:
		use_coastal_band = _region_gradient_value < foreground_band_crossover
	var texture := foreground_band_texture_coastal if use_coastal_band else foreground_band_texture
	if texture == null:
		return
	# The anchor is the room's ACTUAL visible bottom edge, not _room_
	# height() (2026-08-30 foreground-framing fix pass). The camera is a
	# child of Player with no vertical local offset ever applied
	# (FieldCamera's own lookahead is horizontal-only), so its rendered
	# center tracks the player's Y subject to Camera2D's own limit_top/
	# limit_bottom clamping - get_screen_center_position() is the
	# post-clamp value actually used for rendering (unlike plain
	# global_position, which is the raw, UNclamped transform and does NOT
	# reflect this - confirmed the hard way: an earlier version of this
	# comment claimed the visible bottom sits ~290px below _room_height()
	# based on reading global_position; that was wrong. At today's
	# tuning, limit_bottom exactly equals both _room_height() and the
	# viewport height, leaving zero clamping slack, so the camera's real
	# center is pinned to _room_height()/2 regardless of floor_line_y, and
	# the true visible bottom edge currently DOES equal _room_height().
	# Deriving it from the camera instead of hardcoding that equality is
	# still correct to do - it stops being a coincidence and starts being
	# true by construction, which is what keeps this correct if limit_
	# bottom, floor_line_y, or the viewport size are ever retuned
	# independently of each other. Both instances share this same anchor
	# formula - only band_height/band_overshoot (and therefore the final
	# Y) differ between them.
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	var visible_bottom_y := camera.get_screen_center_position().y + viewport_height / 2.0
	var band_bottom_y := visible_bottom_y + band_overshoot
	var native_size := texture.get_size()
	var scale_factor := band_height / native_size.y
	var band := Sprite2D.new()
	band.texture = texture
	band.centered = false
	# Top-left origin instead of Sprite2D's own default (centered=true) -
	# makes `position` directly the rendered rect's own top-left corner,
	# so band_bottom_y - band_height below is a simple, exact placement
	# instead of also having to subtract half the rendered size.
	band.region_enabled = true
	band.region_rect = Rect2(0.0, 0.0, background_tile_width / scale_factor, native_size.y)
	band.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	band.scale = Vector2(scale_factor, scale_factor)
	_apply_vertical_shade(band, tint, foreground_vertical_shade)
	band.position = Vector2(offset_x, band_bottom_y - band_height)
	layer.add_child(band)

# A flat rectangle primitive, positioned by its own center. Currently
# unused (2026-08-30 strip pass removed its only callers - the crane/
# gantry/pipe silhouettes and hanging occluders) - left in place as a
# small, generic shape helper rather than deleted outright, since it
# carries no content of its own to cut.
func _add_rect(parent: Node, center: Vector2, size: Vector2, color: Color, rotation_radians: float = 0.0) -> void:
	var rect := Polygon2D.new()
	rect.color = color
	rect.polygon = PackedVector2Array([
		Vector2(-size.x / 2.0, -size.y / 2.0), Vector2(size.x / 2.0, -size.y / 2.0),
		Vector2(size.x / 2.0, size.y / 2.0), Vector2(-size.x / 2.0, size.y / 2.0),
	])
	rect.position = center
	rect.rotation = rotation_radians
	parent.add_child(rect)

@export_group("Vegetation - clump textures")
@export var vegetation_clump_textures: Array[Texture2D] = []
# assets/regions/beach/Grass/grass_00.png..grass_05.png (6 tuft variants,
# 2026-08-30 tuft-set swap, REPLACING an earlier 8-variant set whose
# blades had a solid base/mound and zero opacity on their bottom row -
# these taper to nothing at the base instead, no mound) - pure black on
# transparent, base at the bottom edge of each image, assigned in the
# scene rather than hardcoded as preloads here (same pattern ground_
# texture/foreground_band_texture already use). _add_vegetation_clump()
# no-ops if this is empty (see its own doc).
@export var vegetation_scale_min: float = 0.08
@export var vegetation_scale_max: float = 0.18
# Retuned for the current tuft set's own native size (219-485px wide,
# 348-652px tall) - at 0.13 (roughly this range's own midpoint) these
# render ~30-65px wide, ~45-85px tall on screen, against a 154px player
# (2026-08-30 tuft-set swap; the previous range, 0.12-0.28, was sized for
# the prior set's smaller 90-130x135-277px native art). Starting points
# for live tuning, not a considered final value. Applied uniformly to
# both axes (see _add_vegetation_clump() below) so a clump scales
# without stretching.

@export_group("Vegetation - clustering")
@export var vegetation_min_clumps: int = 4
# Art Direction Bible §14: grass reads as grouped masses, not individual
# objects (2026-08-30, clustering pass) - a floor UNDERNEATH whichever
# per-generator count is already configured (vegetation_per_structure for
# mid-layer, seam_vegetation_count for the seam - see _populate_mid_
# layer()/_add_seam_vegetation()), not a replacement for either: a room
# never places fewer than this many clumps in ONE generator's own pass,
# even if that generator's own count export is set lower (both default
# below this floor today, 1 and 2 respectively - a single lone tuft was
# exactly the "planted at intervals, one row" complaint this pass fixes).
# Coastal seam vegetation (the opening room only) is NOT floored - its
# sparseness is deliberate, see _add_coastal_seam_vegetation()'s own doc.
@export var vegetation_cluster_count: int = 3
@export var vegetation_cluster_spread: float = 90.0
# Horizontal jitter around a cluster's own center X (2026-08-30,
# clustering pass) - see _vegetation_cluster_x_positions()'s own doc for
# the full algorithm both mid-layer and seam vegetation now share.

@export_group("Vegetation - sway")
@export var vegetation_sway_enabled: bool = true
@export var vegetation_sway_degrees: float = 2.5
# Peak rotation either side of upright (2026-08-31, vegetation-sway pass)
# - the only motion anywhere in the field while the player stands still,
# so it's the cheapest available cue that the world keeps going rather
# than pausing with them (a coastal region where wind is the only thing
# still happening). Kept small deliberately: at 2.5 degrees a clump's own
# TIP (the point furthest from the pivot - see _add_vegetation_clump()'s
# own pivot doc) moves a visible few pixels while the base stays visually
# still, which is what reads as grass bending, not as a flat sprite
# spinning in place. See _update_vegetation_sway() for the actual motion.
@export var vegetation_sway_period_min: float = 3.5
@export var vegetation_sway_period_max: float = 6.0
# Seconds for one full sway cycle, rolled independently PER CLUMP (see
# _add_vegetation_clump()'s own registration) alongside an independent
# random phase - same "never move in unison" reasoning cloud_drift_speed_
# min/_max and _add_cloud_band()'s old high/low differentiation both
# already established for this file's other ambient-motion systems: a
# shared period would have every clump peak and rest at the same instant,
# reading as one rigid shape breathing rather than as many independent
# plants.

# A randomly selected grass clump texture (2026-08-30 grass-asset pass;
# tuft-set swapped again the same day for the current 6-variant art -
# see vegetation_clump_textures's own doc). No `radius` parameter any
# more - size now comes entirely from vegetation_scale_min/_max, not a
# per-call-site value, so every caller below drops the argument it used
# to pass (that value used to scale the old procedural shape this
# function replaced directly; a couple of call sites still roll their
# own local radius for an unrelated placement-margin calculation - see
# _add_coastal_seam_vegetation()'s own comment - which is untouched).
#
# Base-anchored placement: the asset's own base sits at the bottom edge
# of the image (per its spec), matching the SAME contract the procedural
# shape this replaced used to guarantee (base at local y=0, placed with
# no offset). Sprite2D has no equivalent "bottom-anchored" origin built
# in (centered=false puts the origin at the TOP-left of the rendered
# rect, centered=true at its middle), so matching that contract takes an
# Art Direction Bible §14: grass reads as grouped masses, not individual
# objects planted at intervals (2026-08-30, clustering pass) - shared by
# both _populate_mid_layer()'s own vegetation and _add_seam_vegetation(),
# the two callers this pass touches, since both need the exact same "pick
# a few cluster centers, scatter clumps around them unevenly" algorithm,
# introduced together for the first time here rather than independently
# evolved copies - a different situation from this file's usual "two
# uses, still duplicate" instinct, which is about features that DRIFT
# apart over separate passes, not one new algorithm two callers need
# identically on day one. Coastal seam vegetation is NOT a caller - see
# _add_coastal_seam_vegetation()'s own doc for why its sparseness stays
# untouched.
#
# Cluster centers are picked independently at random X positions across
# [min_x, max_x] - NOT evenly spaced, so the clusters themselves don't
# just reproduce the same "planted at intervals" problem one level up.
# Each of `clump_count` clumps is then assigned to a RANDOMLY CHOSEN
# center (with replacement - not a pre-divided even split across
# centers) and jittered by up to vegetation_cluster_spread around it -
# membership comes out uneven on its own this way (some clusters land
# one clump, some land three, per this pass's own brief) with no
# separate "how many go in this cluster" roll needed. clampf() keeps a
# jittered position from drifting past the span's own edges, the same
# bound every existing placement call already enforced by construction
# (randf_range can't exceed its own range) before an ADDED offset could
# push a result outside it.
func _vegetation_cluster_x_positions(min_x: float, max_x: float, clump_count: int) -> Array[float]:
	var centers: Array[float] = []
	for i in vegetation_cluster_count:
		centers.append(randf_range(min_x, max_x))
	var positions: Array[float] = []
	for i in clump_count:
		var center: float = centers[randi() % centers.size()]
		positions.append(clampf(center + randf_range(-vegetation_cluster_spread, vegetation_cluster_spread), min_x, max_x))
	return positions

# Rendered rect: horizontally centered on base.x, vertically positioned
# so its OWN bottom edge - not its top-left origin - lands exactly at
# base.y. Achieved via `offset`, not `position`, as of the 2026-08-31
# vegetation-sway pass - see the pivot note just below for why.
#
# Pivot fix (2026-08-31, vegetation-sway pass): this used to set `clump.
# position` DIRECTLY to the computed top-left corner (base.x - rendered_
# size.x/2, base.y - rendered_size.y), with `offset` left at its default
# zero. That renders identically to today (offset shifts the same rect by
# the same amount either way), but a Node2D's `rotation` always pivots
# around its OWN local origin, i.e. wherever `position` points - so the
# old version pivoted around the rendered rect's TOP-LEFT CORNER, not
# `base` (confirmed headlessly before this pass: for a real clump, the
# old formula placed the pivot ~85px above and ~20px left of `base`, not
# AT it, contrary to what centered=false might suggest at a glance - it
# puts the ORIGIN at the corner, and only this function's own extra math
# moved the corner to the right place, not the origin itself to the
# base). A pivot at that corner would swing the clump like a door around
# a point in empty air above-left of its own base, not bend it FROM its
# base - exactly wrong for sway. Setting `clump.position = base` directly
# instead puts the true rotation pivot at the ground-contact point, and
# `offset` (which is NOT affected by rotation's own pivot - it's measured
# in the sprite's local, pre-transform space, same as the texture's own
# pixels) reproduces the exact same rendered rect as before by shifting
# from that pivot instead of from the corner. Native-pixel units, not
# rendered_size (already-scaled) units - offset is subject to the node's
# own `scale` just like the texture's native pixels are, so using native
# units here and letting `scale` do the multiplying is what keeps this
# equivalent to the old rendered_size-based math, not double-scaled.
func _add_vegetation_clump(parent: Node, base: Vector2, color: Color) -> void:
	if vegetation_clump_textures.is_empty():
		return
	var clump := Sprite2D.new()
	clump.texture = vegetation_clump_textures[randi() % vegetation_clump_textures.size()]
	clump.centered = false
	# Random horizontal flip, NO rotation of the TEXTURE itself here -
	# growth has an up direction, so a permanently rotated plant would
	# point it sideways or downward. Sway (below) is a live, animated
	# rotation applied on top of this, not a substitute for it.
	clump.flip_h = randf() < 0.5
	var clump_scale := randf_range(vegetation_scale_min, vegetation_scale_max)
	clump.scale = Vector2(clump_scale, clump_scale)
	# modulate multiplies per-channel against the texture's own sampled
	# RGB, so it can only ever DARKEN what's already there - it can never
	# introduce color a black pixel doesn't have (0 x anything = 0). That
	# is why these clump assets must be WHITE masks (2026-08-30 white-mask
	# fix, replacing an earlier black-mask set that rendered as flat
	# black regardless of vegetation_color/coastal_vegetation_color - see
	# that pass's own read-only report for the confirmed root cause):
	# white x color = color exactly, so the full color below actually
	# reaches the screen. The foreground band (foreground_band_tileable.png)
	# and its own mass pieces are ALSO white masks now (2026-09-06,
	# band-flatten pass - they used to be the OPPOSITE, deliberately
	# painted/near-black assets a white-mask modulate would have washed
	# out), but they still must NOT take these clumps' own vegetation_
	# color/coastal_vegetation_color - they modulate from their own
	# separate painted_preview_fg_color instead, so the two families stay
	# independently tintable. Tower/structure assets remain the one
	# deliberately-near-black family left - swapping THEIR mask color
	# would still break them. Any future tintable asset added to this
	# vocabulary must be a white mask, not a black one, and should get its
	# own modulate source rather than sharing an unrelated family's.
	clump.modulate = color
	var native_size := clump.texture.get_size()
	clump.position = base
	clump.offset = Vector2(-native_size.x / 2.0, -native_size.y)
	parent.add_child(clump)
	_painted_preview_decoration_nodes.append(clump)

	if vegetation_sway_enabled:
		_vegetation_sway_state.append({
			"sprite": clump,
			"phase": randf_range(0.0, TAU),
			"period": randf_range(vegetation_sway_period_min, vegetation_sway_period_max),
		})

# Per-frame sway for every clump _add_vegetation_clump() registered above
# (mid-layer vegetation, seam vegetation, and coastal seam vegetation all
# go through that one function - see its own doc - so all three get sway
# from this single call site) - invoked from the room's shared _process()
# (see that function's own doc for why several unrelated per-frame
# concerns share it). Cheap no-op if sway is off or nothing registered
# (cloud_drift_enabled-style early return - see _update_cloud_drift()'s
# own matching check).
#
# A single shared elapsed-time accumulator (_vegetation_sway_time) drives
# every clump's own sin() - see that var's own doc for why one clock is
# enough. rotation is set directly (not accumulated/added) every frame,
# so this is idempotent regardless of frame rate - exactly like _update_
# cloud_drift() setting position.x from a running total rather than
# nudging it, just a rotation instead of a translation.
func _update_vegetation_sway(delta: float) -> void:
	if not vegetation_sway_enabled or _vegetation_sway_state.is_empty():
		return
	_vegetation_sway_time += delta
	var amplitude: float = deg_to_rad(vegetation_sway_degrees)
	for entry in _vegetation_sway_state:
		var sprite: Sprite2D = entry["sprite"]
		var phase: float = entry["phase"]
		var period: float = entry["period"]
		sprite.rotation = amplitude * sin(TAU * _vegetation_sway_time / period + phase)

# --- Ground texture (2026-08-30 ground-texture pass) ---
#
# Tiled across floor_polygon's own full horizontal span - set
# unconditionally in _position_floor() rather than inside _apply_
# standard_ground_treatment() (which early-returns for the opening room)
# so it reaches BOTH the standard ground and the coastal sand floor, per
# this pass's own decision: same region, same beach, a textured standard
# floor beside an untextured sand floor would read as inconsistent at
# the exact point the player arrives. ground_base_color and OPENING_
# ROOM_SAND_COLOR are UNCHANGED, still set exactly where they already
# were (see each's own call site) - they now act as a tint OVER the
# texture (Polygon2D multiplies texture x color) instead of a flat fill,
# which is what keeps the standard ground and the coastal sand visually
# distinct even though both tile the identical texture.
@export_group("Ground texture")
@export var ground_texture_enabled: bool = true
@export var ground_texture: Texture2D
# Expected: assets/regions/beach/ground_tile_wide.png (2570x512,
# horizontally seamless, mean luminance 0.78, uniform top to bottom - no
# built-in vertical gradient of its own, which is exactly why ground_
# texture_depth_tint/_apply_floor_depth_tint() below exist). REPLACES
# ground_tile.png (1336x512, kept on disk unused, 2026-08-31 wide-ground
# pass) - at 1336px the texture repeated roughly twice across a 2800px
# standard room, and that repeat was visible mid-frame; at 2570px a room
# is covered in essentially one pass. Assigned in the scene, not
# hardcoded as a preload here, matching how every other artist-facing
# tunable in this file is a plain @export.
@export var ground_texture_scale: float = 1.0
# UNCHANGED by the wide-ground swap above, deliberately - see this pass's
# own report (measured via horizontal autocorrelation, not eyeballed):
# the new texture's HORIZONTAL grain is noticeably coarser in native
# pixels than the old one's (roughly 35-40% larger, not simply the ~92%
# the width difference alone might suggest), while its VERTICAL grain
# (same 512px height, unchanged) is essentially the same size as before.
# Polygon2D applies one scalar to both axes (texture_scale below), so no
# single value restores both exactly - a value chosen to fix the
# horizontal repeat would also needlessly shrink the vertical grain,
# which was never wrong. Left at 1.0 pending a live look, not retuned
# blind against a single-axis measurement of an asset with two different
# per-axis answers.
@export_range(0.0, 1.0, 0.01) var ground_texture_depth_tint: float = 0.45
# How strongly the far edge (at floor_line_y) fades toward sky_gradient_
# horizon_color relative to the near edge (at _room_height(), left
# unmodified) - see _apply_floor_depth_tint() below for the vertex-color
# mechanics. Independent of ground_patch_depth_fade/seam_debris_depth_
# fade (2026-08-30 depth-variation pass) - the floor and the decoration
# sitting on it share the same fading-toward-the-horizon IDEA but are
# separate draws with separate tuning knobs, same as every other
# per-element color export in this file.
#
# _validate_background_contrast() is UNCHANGED (still checks ground_
# base_color, not whatever this pass renders) and still correctly checks
# the thing that matters: ground_base_color is the TINT multiplied over
# the texture, and the texture's own mean luminance (0.79) sits
# comfortably above background_plane_luminance_floor (0.70) on its own -
# a pale tint over an already-pale texture can only read paler than the
# tint alone, never darker, so the existing check stays a valid (if now
# slightly conservative) floor rather than a stale one.
#
# When ground_texture_enabled is false, or ground_texture is unset,
# _position_floor() falls back to exactly today's behavior: no texture,
# flat color fill, no vertex-color gradient either (see _apply_floor_
# depth_tint(), which clears floor_polygon.vertex_colors in that case) -
# a real off switch, not just a visual no-op.

# --- Standard-room ground treatment - cracked ground with patches
# breaking through, built from _irregular_blob_shape()/_crack_shape()/
# _add_floor_decoration() (below). Randomized per room load (not a
# hand-placed list, unlike the opening room's own fixed narrative-
# position decorations) - standard rooms already regenerate their own
# layout fresh each visit, so there's no fixed-position requirement to
# honor here the way the opening room's own beats have.
@export_group("Ground - standard rooms")
@export var ground_base_color: Color = Color(0.76, 0.71, 0.66, 1)
# WARMED (2026-09-01, battle-plate ground-match pass) - shifted toward a
# warmer, more ochre hue (R +0.03, G -0.01, B -0.02 from the prior 0.73,
# 0.72, 0.68) at essentially the same luminance (0.719 vs 0.718 before -
# background_plane_luminance_floor's own 0.70 clears with the same margin
# as before, not a new margin) and chroma 0.10 (max-min), landing inside
# the battle backdrop's own measured 0.077-0.106 ground chroma range - the
# two currently read as different materials (field near-neutral, battle
# ochre-buff) and this closes that gap on hue alone, not value. This is
# the region_gradient_enabled=false FALLBACK only - see ground_color_wet/
# _dry below for the colors actually rendered by default (region_
# gradient_enabled defaults to true), warmed the same way in the same
# pass so the fallback and the live path don't drift apart.
@export var ground_crack_color: Color = Color(0.57, 0.56, 0.54, 0.55)
@export var ground_patch_color: Color = Color(0.67, 0.66, 0.62, 0.5)
@export var ground_crack_count: int = 3
@export var ground_patch_count: int = 8
@export_range(0.0, 1.0, 0.01) var ground_patch_depth_fade: float = 0.35
# How strongly a patch's color shifts with its own depth in the ground
# band (2026-08-30 depth-variation pass) - see _depth_tinted_color()'s
# own doc for the far/near formula. 0 disables the fade entirely (every
# patch stays exactly ground_patch_color); kept subtle by default since
# this reinforces the radius-by-depth cue below, it doesn't replace it.
# Pale, nearly neutral gray-tan (2026-08-30 palette retune) - the bright,
# washed-out ground this region's own brief calls for, not a distinct
# silt, mud, or sand material. All three ground colors here (base, crack,
# patch) sit close together in the same near-neutral family, differing
# mainly in luminance - base is the palest (the plane itself), crack the
# darkest (so the crack reads against it), patch a step in between -
# rather than in hue. See the chest-contrast note below for why hue
# separation still matters even though the palette itself has gone
# colorless.
#
# ground_base_color and ground_patch_color are both checked by
# _validate_background_contrast() - as of the 2026-08-30 floor rewrite
# they're in DIFFERENT tiers, not the same one: ground_base_color is the
# walkable PLANE itself (background_plane_luminance_floor), while
# ground_patch_color is a detail sitting within that plane
# (background_detail_luminance_floor, the lower of the two floors) -
# even though neither is technically one of the ParallaxLayer
# "background layers." Historically (pre-rewrite, when this was a
# ceiling rather than a floor) the chest specifically (field_chest.gd's
# chest_color, (0.95, 0.85, 0.2) - a saturated gold, luminance ~0.81)
# was flagged as low-contrast against an earlier warm tan ground despite
# the luminance gap, because both sat in the same warm-yellow hue
# family; moving the ground off that hue fixed it by widening the hue
# gap, not just the luminance gap - worth keeping in mind now that the
# ground has gone pale and near-neutral rather than reintroducing a
# warm cast that would put it back in the chest's own hue family.

# --- Sky/ground seam breakup (2026-08-24) - purely a RENDERING pass,
# same "content_root drawing on top of Floor, behind Player" seam every
# other floor decoration above already uses. Floor's own polygon (see
# _position_floor()) and RoomState.floor_line_y are completely untouched
# by any of this - the flat, straight walkable plane the player actually
# stands on isn't going anywhere, only what's drawn ON it and just above
# its edge changes. See this feature's own inspection note in DESIGN.md
# for why that split is safe: Floor has no collision of its own at all
# (no CollisionShape2D/CollisionPolygon2D anywhere near it), and player.
# gd never reads floor_line_y or moves vertically (velocity.y is always
# 0) - the visual seam and "where the player can stand" have never been
# the same mechanism.
@export_group("Ground - seam breakup")
@export var seam_debris_color: Color = Color(0.59, 0.58, 0.55, 0.8)
@export var seam_debris_count: int = 4
@export var seam_debris_min_radius: float = 18.0
@export var seam_debris_max_radius: float = 42.0
@export_range(0.0, 1.0, 0.01) var seam_debris_depth_fade: float = 0.35
# Same treatment as ground_patch_depth_fade, independently tunable since
# seam debris sits at a smaller scale (2026-08-30 depth-variation pass) -
# see _depth_tinted_color()'s own doc for the formula.
# Pale, near-neutral gray (2026-08-30 palette retune) - a detail sitting
# within the ground plane, not a distinct debris material. Same
# near-neutral family as ground_base_color/tide_band_color, held to the
# lower detail floor rather than the plane floor.
#
# Sediment mounds resting just below floor_line_y (see
# _add_seam_debris()) - each one's Y is jittered across a band starting
# right at the seam, breaking up how close to the horizon ground clutter
# can sit rather than leaving a dead zone right at the edge. Reuses
# _irregular_blob_shape(), the same vocabulary ground patches/cracks
# already draw from - no new shape language.
#
# CORRECTED (2026-08-27, "stay below the field line" fix): this used to
# deliberately jitter EACH piece's Y across the seam itself so it
# genuinely crossed the line, not just sat above or below - the original
# "break up the hard sky/ground seam" brief this whole family was built
# for. Debris reading as sitting ON the ground, entirely below the line,
# turned out to matter more than that seam-breakup effect - see _add_
# seam_debris()'s own doc for the corrected placement, which now stays
# entirely below floor_line_y (each piece's own exact upward reach, not
# a flat margin) while still spreading across real depth in the band
# below it, not just hugging the line.

@export var tide_band_count: int = 3
@export var tide_band_color: Color = Color(0.64, 0.62, 0.59, 1)
@export_range(0.0, 1.0, 0.01) var tide_band_contrast: float = 0.35
@export var tide_band_height: float = 22.0
@export var tide_band_wave_amplitude: float = 8.0
# Pale, near-neutral gray (2026-08-30 palette retune), not a distinct
# wet-ground material - kept in the SAME family as ground_base_color and
# kept darker than it (this color's own luminance ~0.62 vs
# ground_base_color's ~0.72), so the "wet near the seam, lighter further
# down" direction still reads as a tonal shift within one pale family
# rather than a color change.
#
# Two or three wavy horizontal bands stacked downward from the seam (see
# _add_tide_band()) - band 0 (closest to floor_line_y) is drawn at
# tide_band_contrast's own alpha, each band after it fainter by an equal
# step, fading toward plain ground_base_color by the last one - "darker
# near the seam, lightening downward," texture rather than stripes
# because the alpha step is small AND each band's top/bottom edge is
# jittered per length-segment (tide_band_wave_amplitude) rather than a
# straight rule. Purely a color overlay on TOP of Floor's existing flat
# fill - no shape/height change to the ground itself.

@export var seam_vegetation_count: int = 2
# Sparse growth breaking the seam line (see _apply_standard_ground_
# treatment()) - reuses _add_vegetation_clump()/vegetation_color
# verbatim, the exact same generator and color the mid-layer structures'
# own base vegetation already uses, just placed at the seam instead of a
# structure's base. Low by design (2, matching this pass's own "low
# count" brief) - a few interruptions, not a hedge.

# --- Ground line decoration (2026-09-06) ---
#
# Track A alpha masks straddling floor_line_y itself, so the seam between
# the ground strip and the wet flat stops reading as one uninterrupted
# straight edge. In content_root at gameplay-plane depth (motion_scale
# 1.0), NOT painted_mid_layer - at that layer's 0.35 motion_scale these
# would slide relative to the floor line as the camera pans and drift off
# the boundary they exist to break. Applies to every field room, including
# the opening room - see _populate_ground_line_decoration()'s own call
# site in _ready().
@export_group("Ground line decoration")
@export var ground_line_enabled: bool = true
@export var ground_line_count_min: int = 2
@export var ground_line_count_max: int = 6
# Shared across every variant below, same role painted_preview_mid_scale_
# jitter already plays for the painted mid plates - one instance of a
# variant should not render at an identical size to the next.
@export_range(0.0, 1.0, 0.01) var ground_line_scale_jitter: float = 0.25
# Same direction-agnostic interval-overlap check painted_mid_layer's own
# plate placement uses (see _apply_painted_preview()'s mid-plate loop) -
# a candidate X within this many px of an already-placed piece's span is
# rejected and re-rolled, up to ground_line_placement_retry_limit times.
@export var ground_line_min_gap_px: float = 30.0
@export var ground_line_placement_retry_limit: int = 10

@export_subgroup("Grass (sparse)")
@export var ground_line_grass_texture: Texture2D = preload("res://assets/regions/beach/GroundLine/ground_grass_sparse.png")
@export_range(0.0, 1.0, 0.01) var ground_line_grass_spawn_chance: float = 0.6
@export var ground_line_grass_height_frac: float = 0.028
# Added to floor_line_y for this variant's own visual contact point -
# NOT derived from the texture's own bounds. These masks have irregular,
# slightly curved bottoms rather than a flat cut edge, so anchoring to
# the rendered rect's bottom edge (the bottom-center anchor _populate_
# ground_line_decoration() sets up for every piece) leaves a sliver of
# transparent padding between the visible mass and floor_line_y, i.e.
# floating. Tune each one by eye in the running room, same as painted_
# preview_mid_hull_a_y_offset and friends already are.
@export var ground_line_grass_y_offset: float = 0.0
@export var ground_line_grass_color: Color = Color(0.62, 0.59, 0.53, 1)

@export_subgroup("Half-buried plank")
@export var ground_line_plank_texture: Texture2D = preload("res://assets/regions/beach/GroundLine/ground_plank.png")
@export_range(0.0, 1.0, 0.01) var ground_line_plank_spawn_chance: float = 0.35
@export var ground_line_plank_height_frac: float = 0.032
@export var ground_line_plank_y_offset: float = 0.0
@export var ground_line_plank_color: Color = Color(0.58, 0.54, 0.48, 1)

@export_subgroup("Low ridge")
@export var ground_line_ridge_texture: Texture2D = preload("res://assets/regions/beach/GroundLine/ground_ridge.png")
@export_range(0.0, 1.0, 0.01) var ground_line_ridge_spawn_chance: float = 0.45
@export var ground_line_ridge_height_frac: float = 0.03
@export var ground_line_ridge_y_offset: float = 0.0
@export var ground_line_ridge_color: Color = Color(0.60, 0.57, 0.52, 1)

@export_subgroup("Single stone")
@export var ground_line_stone_single_texture: Texture2D = preload("res://assets/regions/beach/GroundLine/ground_stone_single.png")
@export_range(0.0, 1.0, 0.01) var ground_line_stone_single_spawn_chance: float = 0.5
@export var ground_line_stone_single_height_frac: float = 0.022
@export var ground_line_stone_single_y_offset: float = 0.0
@export var ground_line_stone_single_color: Color = Color(0.56, 0.55, 0.53, 1)

@export_subgroup("Stone cluster")
@export var ground_line_stone_cluster_texture: Texture2D = preload("res://assets/regions/beach/GroundLine/ground_stone_cluster.png")
@export_range(0.0, 1.0, 0.01) var ground_line_stone_cluster_spawn_chance: float = 0.4
@export var ground_line_stone_cluster_height_frac: float = 0.026
@export var ground_line_stone_cluster_y_offset: float = 0.0
@export var ground_line_stone_cluster_color: Color = Color(0.56, 0.55, 0.53, 1)

# --- Opening room (coastal) ground treatment (2026-08-26) ---
#
# The opening room's own sand variant of the treatment above - same
# vocabulary (_add_wavy_band()/_add_floor_decoration()/_add_vegetation_
# clump(), all unchanged, all shared with the standard rooms), retuned
# for a beach instead of duplicated wholesale. Lives in its OWN functions
# (_add_coastal_tide_bands()/_add_coastal_seam_debris()/_add_coastal_
# seam_vegetation() below) rather than being folded into _apply_standard_
# ground_treatment()'s own early-return - that function runs BEFORE
# _apply_coastal_opening_room_layout() in _ready()'s own sequence (see
# its own header comment), which is what actually sets the sand's real
# left edge (the shore line, past the ocean - see _apply_coastal_opening_
# room_layout()'s own floor_poly[0].x line); calling these from THERE
# instead, after that edge is known, is what lets every decoration below
# correctly stop at the shore instead of one call earlier assuming the
# standard rooms' left bound (which would place debris/vegetation
# underwater). Extending the standard function's own early-return with a
# sand branch was the alternative considered - rejected specifically for
# that ordering reason, not because reusing the vocabulary was wrong.
#
# Every color/count/size below is its OWN export, independent of the
# standard treatment's identically-shaped ones (tide_band_color, etc.) -
# retuning the beach was never meant to also retune inland rooms, and
# vice versa, even though both ultimately call the same drawing helpers.
@export_group("Opening room - coastal ground treatment")
@export var coastal_tide_band_color: Color = Color(0.66, 0.64, 0.6, 1)
# Pale, near-neutral wet-sand darkening (2026-08-30 palette retune) -
# same "family, just darker" relationship to OPENING_ROOM_SAND_COLOR
# that tide_band_color already holds to ground_base_color, both now pale
# near-neutral rather than a distinct warm-sand hue.
@export var coastal_tide_band_count: int = 4
@export var coastal_tide_band_contrast: float = 0.5
# Both higher than the standard treatment's 3/0.35 - a real beach, unlike
# inland silt, actually has a waterline close by, so the wet-sand read
# near floor_line_y (band 0, the strongest and closest - see _add_wavy_
# band()'s own stacking) should register more strongly here, per this
# pass's own brief, not just match inland at a different hue.
@export var coastal_tide_band_height: float = 22.0
@export var coastal_tide_band_wave_amplitude: float = 8.0
# Unchanged from the standard treatment's own tide_band_height/_wave_
# amplitude - "reads more strongly" is a contrast/count change (above),
# not a shape change; there's no reason a wave on sand should jitter
# differently than a wave on silt.

@export var coastal_seam_debris_color: Color = Color(0.58, 0.56, 0.52, 0.85)
# Pale, near-neutral gray (2026-08-30 palette retune) - the same blob
# shape _add_seam_debris() draws inland (see _irregular_blob_shape())
# reads equally well as a beached debris mound here, purely from this
# color swap - no new shape vocabulary needed.
@export var coastal_seam_debris_count: int = 5
@export var coastal_seam_debris_min_radius: float = 16.0
@export var coastal_seam_debris_max_radius: float = 38.0
# Slightly more numerous, slightly smaller than the standard treatment's
# 4 @ 18-42 - a wrack line reads as a scatter of smaller debris, not a
# few large rubble piles.

@export var coastal_vegetation_color: Color = Color(0.6, 0.6, 0.48, 1)
# Pale, near-neutral yellow-green (2026-08-30 palette retune) - a step
# paler and less saturated than vegetation_color's own pale green, for a
# sun-bleached beach read rather than the mid layer's own growth.
@export var coastal_vegetation_count: int = 1
# Sparser than the standard treatment's already-modest 2, per this
# pass's own brief ("sparse beach growth") - beach grass clings in a
# clump or two, not evenly distributed tufts.

func _coastal_shore_x() -> float:
	# Duplicates _apply_coastal_opening_room_layout()'s own ocean_depth
	# expression (20.0 + OPENING_ROOM_OCEAN_DEPTH) rather than reading a
	# shared variable - that function's own local is computed fresh each
	# call and never stored on self, and threading a new field through
	# just for this would touch working, carefully-tuned ocean-placement
	# code for no functional gain. Two lines of duplication is cheaper
	# than that risk.
	return 20.0 + OPENING_ROOM_OCEAN_DEPTH

func _add_coastal_tide_bands() -> void:
	var left_x := _coastal_shore_x()
	var right_x := _room_floor_right_x()
	for i in coastal_tide_band_count:
		var alpha: float = coastal_tide_band_contrast * (1.0 - float(i) / float(coastal_tide_band_count))
		if alpha <= 0.0:
			continue
		var y_center := RoomState.floor_line_y + coastal_tide_band_height * (i + 0.5)
		var color := Color(coastal_tide_band_color.r, coastal_tide_band_color.g, coastal_tide_band_color.b, alpha)
		_add_wavy_band(y_center, coastal_tide_band_height, color, coastal_tide_band_wave_amplitude, left_x, right_x)

# Softens the water's own top edge - see the "Shoreline edge" export
# group's own header for why this exists as a second overlay band
# rather than a change to FieldWall itself. Spans exactly the ocean's
# own width (0 to the shore line), not _add_wavy_band()'s own left_x/
# right_x default of the room's full span - the same explicit-bounds
# override _add_coastal_tide_bands() above already passes, for the
# opposite reason: that one must not run under the sand, this one must
# not run past the shore into the sand's own space.
func _add_coastal_water_edge() -> void:
	var water_top_y := RoomState.floor_line_y - opening_room_water_height_above_floor
	_add_wavy_band(water_top_y, coastal_water_edge_height, OPENING_ROOM_OCEAN_COLOR, coastal_water_edge_wave_amplitude, 0.0, _coastal_shore_x())

func _add_coastal_seam_debris() -> void:
	var left_x := _coastal_shore_x()
	var right_x := _room_floor_right_x()
	for i in coastal_seam_debris_count:
		var radius: float = randf_range(coastal_seam_debris_min_radius, coastal_seam_debris_max_radius)
		# The HORIZONTAL margin has to clear this piece's OWN visual
		# extent, not a flat number - a blob (_irregular_blob_shape())
		# jitters each vertex independently up to blob_jitter_max, so
		# `radius * blob_jitter_max` is the worst-case distance ANY vertex
		# can sit from the shape's own center, regardless of which vertex
		# it ends up being. Rotating the shape (below) doesn't change that
		# bound - rotation only turns the point set around its own center,
		# never changes a vertex's distance from it - so the same margin
		# still safely covers a rotated piece, not just an unrotated one.
		# A flat margin smaller than this could let a large piece's
		# rendered edge cross the shore line into the ocean even though
		# its position itself never does (confirmed headlessly - this was
		# a real bug, not a hypothetical, before this margin accounted
		# for it).
		#
		# The shape is built BEFORE rolling a Y position now (2026-08-27,
		# "stay below the field line" fix) - the VERTICAL band a piece can
		# land in depends on its own exact upward reach
		# (_shape_max_upward_reach(), which is NOT the same radius *
		# blob_jitter_max figure above - that one is specific to the
		# horizontal direction; see that function's own doc), so the shape
		# has to exist first to measure it.
		#
		# Rotation randomized per instance (2026-08-30 per-instance-
		# variation pass - see _irregular_blob_shape()'s own doc) so
		# pieces at the same radius no longer share an orientation on top
		# of no longer sharing an outline.
		var rotation_radians := randf_range(0.0, TAU)
		var shape: PackedVector2Array = _irregular_blob_shape(radius)
		var min_y := RoomState.floor_line_y + _shape_max_upward_reach(shape, rotation_radians)
		var max_y := ROOM_FLOOR_BOTTOM_Y - GROUND_DEBRIS_BOTTOM_MARGIN_PX
		if min_y > max_y:
			push_warning("Coastal seam debris piece (radius %.1f) can't fit entirely below floor_line_y within the ground band - skipped rather than shrunk." % radius)
			continue
		var pos := Vector2(
			randf_range(left_x + radius * blob_jitter_max, right_x - 40.0),
			randf_range(min_y, max_y),
		)
		_add_floor_decoration(shape, pos, coastal_seam_debris_color, rotation_radians)

func _add_coastal_seam_vegetation() -> void:
	var left_x := _coastal_shore_x()
	var right_x := _room_floor_right_x()
	for i in coastal_vegetation_count:
		# Still rolled for the horizontal margin below, even though it's
		# no longer passed to _add_vegetation_clump() (2026-08-30
		# grass-asset pass - clump size now comes from vegetation_scale_
		# min/_max, not a per-call radius) - see _add_coastal_seam_
		# debris()'s own note on why the margin needs a value like this
		# at all, kept here so a future retune of this margin has a real
		# number to work from rather than a magic constant.
		var radius := randf_range(16.0, 26.0)
		var pos := Vector2(
			randf_range(left_x + radius * 1.3, right_x - 40.0),
			RoomState.floor_line_y + randf_range(-10.0, 10.0),
		)
		_add_vegetation_clump(content_root, pos, coastal_vegetation_color)

# Depth tint shared by ground patches and seam debris (2026-08-30
# depth-variation pass) - Bible §5: "contrast separates depth planes."
# `t` is the same 0 (far, at floor_line_y) .. 1 (near, at ROOM_FLOOR_
# BOTTOM_Y) fraction each caller already uses to interpolate radius and
# Y position, reused here so a piece's size, placement, AND color all
# agree about how close it is. Far pieces lerp toward sky_gradient_
# horizon_color (paler, lower-contrast against the pale ground) by up to
# fade_strength; near pieces darken by up to HALF that - deliberately a
# weaker push than the far end ("slightly darker," not "equally darker
# as the far end is paler"). Alpha is reset back to base_color's own
# after the lerp (Color.lerp() would otherwise pull it toward sky_
# gradient_horizon_color's opaque alpha=1.0 too) - this fades hue/value
# only, never how transparent the decoration itself is.
func _depth_tinted_color(base_color: Color, t: float, fade_strength: float) -> Color:
	var color := base_color.lerp(sky_gradient_horizon_color, (1.0 - t) * fade_strength)
	color.a = base_color.a
	return color.darkened(t * fade_strength * 0.5)

# ground_base_color stays the untouched fallback (region_gradient_enabled
# = false, or a future caller that just wants the flat color) - see the
# Region Gradient export group's own doc for why ground_color_wet/_dry
# are a separate pair of exports rather than repurposing this one as an
# endpoint.
func _region_ground_color() -> Color:
	if not region_gradient_enabled:
		return ground_base_color
	return ground_color_wet.lerp(ground_color_dry, _region_gradient_value)

func _apply_standard_ground_treatment() -> void:
	# The opening room sets its own floor color/decorations (sand or
	# concrete, per its variant) - see _apply_opening_room_layout(),
	# called later in _ready() - so it's excluded here rather than having
	# this treatment applied first and then overwritten.
	if RunState.current_node == RunState.opening_node:
		return
	var ground_color := _region_ground_color()
	floor_polygon.color = ground_color
	_apply_floor_depth_tint(ground_color)

	var right_x := _room_floor_right_x()
	# Both loops below build the shape (and, for cracks, its rotation)
	# BEFORE rolling a Y position now (2026-08-27, "stay below the field
	# line" fix) - the valid Y band depends on the SPECIFIC piece's own
	# measured upward reach (_shape_max_upward_reach()), not a flat 20px
	# guess, so the shape has to exist first. A piece whose own reach
	# leaves no valid band at all is skipped with a warning rather than
	# shrunk (this fix's own brief) - not reachable at today's radius/
	# length ranges (confirmed - see this fix's own report), but a future
	# retune toward larger pieces could hit it.
	for i in ground_patch_count:
		# One depth fraction (0 = far, at floor_line_y; 1 = near, at
		# ROOM_FLOOR_BOTTOM_Y) drives radius, Y position, AND color
		# together (2026-08-30 depth-variation pass) - picking Y
		# independently of radius (the old approach) could land a small
		# "far" patch at the bottom of frame or a large "near" one at the
		# top, undoing the depth cue this pass adds. Radius still has to
		# be picked before the shape (and the shape before the Y band,
		# per the existing "stay below the field line" ordering below),
		# so t is rolled first and reused once the valid Y band is known
		# rather than resampled.
		var t := randf()
		var radius := lerpf(40.0, 70.0, t)
		# Rotation randomized per instance (2026-08-30 per-instance-
		# variation pass) - rolled before the shape/Y-band below so
		# _shape_max_upward_reach() measures THIS rotation's own reach,
		# the same order ground cracks already use for their own
		# randomized rotation.
		var rotation_radians := randf_range(0.0, TAU)
		var shape := _irregular_blob_shape(radius)
		var min_y := RoomState.floor_line_y + _shape_max_upward_reach(shape, rotation_radians)
		var max_y := ROOM_FLOOR_BOTTOM_Y - GROUND_DEBRIS_BOTTOM_MARGIN_PX
		if min_y > max_y:
			push_warning("Ground patch (radius %.1f) can't fit entirely below floor_line_y within the ground band - skipped rather than shrunk." % radius)
			continue
		var pos := Vector2(randf_range(ROOM_FLOOR_LEFT_X + 60.0, right_x - 60.0), lerpf(min_y, max_y, t))
		var color := _depth_tinted_color(ground_patch_color, t, ground_patch_depth_fade)
		_add_floor_decoration(shape, pos, color, rotation_radians)
	for i in ground_crack_count:
		var length := randf_range(80.0, 160.0)
		var rotation_radians := randf_range(-1.2, 1.2)
		var shape := _crack_shape(length, 10.0)
		var min_y := RoomState.floor_line_y + _shape_max_upward_reach(shape, rotation_radians)
		var max_y := ROOM_FLOOR_BOTTOM_Y - GROUND_DEBRIS_BOTTOM_MARGIN_PX
		if min_y > max_y:
			push_warning("Ground crack (length %.1f) can't fit entirely below floor_line_y within the ground band - skipped rather than shrunk." % length)
			continue
		var pos := Vector2(randf_range(ROOM_FLOOR_LEFT_X + 60.0, right_x - 60.0), randf_range(min_y, max_y))
		_add_floor_decoration(shape, pos, ground_crack_color, rotation_radians)

	_add_tide_bands()
	_add_seam_debris()
	_add_seam_vegetation()

# Stacked downward from floor_line_y, band 0 closest - see tide_band_
# count/tide_band_contrast's own doc for the fade math. Spans the
# room's own visible width (0 to RoomState.room_width(), matching Floor's own
# true-edge-to-true-edge extent - see _position_floor()'s note on why
# that's wider than the walls' inner collision face), not background_
# tile_width - this is ordinary content_root geometry, 1:1 with the
# camera like every other floor decoration, not inside the parallax
# stack.
func _add_tide_bands() -> void:
	for i in tide_band_count:
		var alpha: float = tide_band_contrast * (1.0 - float(i) / float(tide_band_count))
		if alpha <= 0.0:
			continue
		var y_center := RoomState.floor_line_y + tide_band_height * (i + 0.5)
		var color := Color(tide_band_color.r, tide_band_color.g, tide_band_color.b, alpha)
		_add_wavy_band(y_center, tide_band_height, color, tide_band_wave_amplitude)

# A closed polygon whose top AND bottom edges are each independently
# jittered per segment (not a single overall wave) - see tide_band_
# wave_amplitude's own doc for why: "varying in width along their
# length," not just a wavy straight-width strip. SEGMENTS is fixed, not
# exported - it's a mesh-resolution detail (how smooth the wave reads),
# not something a tuner would ever want to change independently of the
# amplitude that actually controls the visible effect.
const TIDE_BAND_SEGMENTS := 8

# left_x/right_x default to the FLOOR's own full visual span (_floor_
# span_left_x()/_floor_span_right_x(), 2026-08-29 - previously 0 to
# RoomState.room_width(), before the floor's own span was decoupled from room
# width - see _position_floor()'s own doc) - _add_tide_bands()'s only
# call site never passes them, so the standard rooms' own bands are
# completely unaffected by this beyond following the floor's own new
# span. _add_coastal_tide_bands() (2026-08-26) is the one caller that
# passes explicit bounds, so its own bands stop at the shore line instead
# of assuming they can span all the way to world x=0, which is underwater
# in that room - and since it always passes both explicitly, it never
# touches this default at all, opening room or not.
#
# NAN, not a negative sentinel - 0.0 is now a real, legitimate explicit
# left_x value one caller already passes (the ocean's own water-edge
# band), so a "< 0" check would have wrongly treated a real 0.0 as unset
# the moment left_x's own default needed to become non-zero.
#
# parent defaults to null/content_root the same way (2026-08-30, ground
# recession pass) rather than defaulting to the member var directly -
# GDScript default arguments have to be constant expressions, and
# content_root is an @onready var, not a constant. Every existing caller
# omits it and keeps landing in content_root unchanged; the recession-
# band callers are the only ones that pass background_mid/background_far
# instead, to get parallax scroll instead of content_root's flat 1:1.
func _add_wavy_band(y_center: float, height: float, color: Color, wave_amplitude: float, left_x: float = NAN, right_x: float = NAN, parent: Node2D = null) -> void:
	if is_nan(left_x):
		left_x = _floor_span_left_x()
	if is_nan(right_x):
		right_x = _floor_span_right_x()
	if parent == null:
		parent = content_root
	var top_points: Array[Vector2] = []
	var bottom_points: Array[Vector2] = []
	for i in TIDE_BAND_SEGMENTS + 1:
		var x: float = lerpf(left_x, right_x, float(i) / float(TIDE_BAND_SEGMENTS))
		top_points.append(Vector2(x, y_center - height / 2.0 + randf_range(-wave_amplitude, wave_amplitude)))
		bottom_points.append(Vector2(x, y_center + height / 2.0 + randf_range(-wave_amplitude, wave_amplitude)))
	bottom_points.reverse()
	var band := Polygon2D.new()
	band.color = color
	band.polygon = PackedVector2Array(top_points + bottom_points)
	parent.add_child(band)
	_painted_preview_decoration_nodes.append(band)

# Art Direction Bible §6 (diffuse environmental illumination, no dramatic
# lighting) and §14 ("clouds become broad value structures") - formless
# density variations in the air, not defined clouds: no edges, no shapes,
# no billows.
#
# Discrete scattered sprites (2026-08-31, scattered-cloud pass) - REPLACES
# the tiled cloud_band_texture band entirely (cloud_high_*/cloud_low_*
# exports, _add_cloud_band(), _cloud_safe_anchor_x(), all deleted). Eight
# passes in a row tried to make ONE wide tiling band never show a visible
# sprite edge or wrap seam at any camera position (a wrap-seam fix, a
# coverage-step fix, a region-offset-seam fix, and a sign bug in the
# anchor math that last fix introduced - this file's own history has the
# full account). Every one of those fixes closed a specific failure mode
# and left the underlying requirement in place: something has to repeat
# or crop seamlessly, and "seamlessly" turned out to be a much harder bar
# to hit, and re-verify after every unrelated retune, than it looks.
# Scattered discrete sprites remove the requirement instead of meeting it
# yet again: there is no region_rect, no texture_repeat, no tiling
# boundary, and no off-screen-edge guarantee to maintain - each cloud is
# placed once at its own natural size (scaled up), and cloud_textures's
# own asset brief (alpha reaching zero on all four edges) means a cloud
# sprite's edge is never a hard line even when it's on-screen, so there
# is nothing left for a seam to be. cloud_band.png stays on disk, unused
# - not deleted, in case a future pass wants it back for something else.
func _add_clouds(layer: ParallaxLayer) -> void:
	if not clouds_enabled or cloud_textures.is_empty():
		return
	# The shared drift/scatter range, cached once (not per-sprite - see
	# _cloud_drift_range_min/_max's own doc) - deliberately wider than
	# [0, background_tile_width] by margin on each side, so a fresh room
	# can scatter clouds already mid-drift across the tile's own left/
	# right seam instead of opening with a conspicuously empty gap at
	# either edge where nothing has drifted into view yet. margin is
	# derived from the actual assets (the widest native cloud_textures
	# entry, at cloud_scale_max - not a guessed constant), so it's exactly
	# wide enough that EVERY cloud, even the single largest one this room
	# could ever roll, can sit fully outside [0, background_tile_width] at
	# either end of the range before _update_cloud_drift() wraps it.
	var max_native_width: float = 0.0
	for texture in cloud_textures:
		max_native_width = maxf(max_native_width, texture.get_size().x)
	var margin: float = max_native_width * cloud_scale_max
	_cloud_drift_range_min = -margin
	_cloud_drift_range_max = background_tile_width + margin
	for i in cloud_count:
		var sprite := Sprite2D.new()
		# centered = true (Sprite2D's own default, left unset rather than
		# forced to false) - DELIBERATE deviation from this file's usual
		# "centered = false, position = a computed base/foot anchor"
		# convention (landform, vegetation, recession bands): those are
		# all grounded on floor_line_y and need a specific anchor point
		# relative to it. A cloud has no base to anchor on - it's a free-
		# floating shape in open sky - so position representing its own
		# center is both simpler and the semantically correct choice here.
		sprite.texture = cloud_textures[randi() % cloud_textures.size()]
		var scale_val: float = randf_range(cloud_scale_min, cloud_scale_max)
		sprite.scale = Vector2(scale_val, scale_val * cloud_vertical_squash)
		sprite.flip_h = randf() < 0.5
		var alpha: float = randf_range(cloud_alpha_min, cloud_alpha_max)
		sprite.modulate = Color(cloud_color.r, cloud_color.g, cloud_color.b, alpha)
		var x: float = randf_range(_cloud_drift_range_min, _cloud_drift_range_max)
		var y: float = randf_range(cloud_band_top_y, cloud_band_bottom_y)
		sprite.position = Vector2(x, y)
		layer.add_child(sprite)
		if cloud_drift_enabled:
			_cloud_drift_state.append({"sprite": sprite, "speed": randf_range(cloud_drift_speed_min, cloud_drift_speed_max)})
		_painted_preview_cloud_nodes.append(sprite)

# Per-frame drift for every cloud _add_clouds() registered above - called
# from the room's shared _process() (see that function's own doc for why
# it's shared). Cheap no-op if there's nothing to do (drift disabled, or
# _cloud_drift_state empty because clouds_enabled/cloud_textures/cloud_
# drift_enabled made _add_clouds() skip registering anything) - same
# "one check, not a real per-frame cost" reasoning exit_haze's own early
# return already uses.
#
# Each cloud moves right at its own fixed speed (rolled once per cloud at
# creation - see cloud_drift_speed_min/_max's own doc) for its entire
# lifetime, including across wraps. On passing the range's right edge, it
# wraps to the left edge with a freshly rolled Y and scale (this pass's
# own explicit brief) - enough to read as a new cloud entering rather
# than the same one visibly snapping back, without needing to reroll
# texture/alpha/flip_h too (a given sprite keeps its own painted identity
# for as long as the room exists; only where it sits and how big it looks
# change at a wrap).
func _update_cloud_drift(delta: float) -> void:
	if not cloud_drift_enabled or _cloud_drift_state.is_empty():
		return
	for entry in _cloud_drift_state:
		var sprite: Sprite2D = entry["sprite"]
		sprite.position.x += entry["speed"] * delta
		if sprite.position.x > _cloud_drift_range_max:
			sprite.position.x = _cloud_drift_range_min
			sprite.position.y = randf_range(cloud_band_top_y, cloud_band_bottom_y)
			var scale_val: float = randf_range(cloud_scale_min, cloud_scale_max)
			sprite.scale = Vector2(scale_val, scale_val * cloud_vertical_squash)

# The painted preview's OWN cloud drift (2026-09-05, cloud-reenable pass) -
# see _painted_preview_cloud_drift_state's own doc for why this is a
# separate, parallel mechanism rather than reusing _update_cloud_drift()
# above: reparented clouds live in bg_layer's viewport-space, not FarLayer's
# tile-space, so they need their own wrap bounds
# (_painted_preview_cloud_drift_min/_max, sized to the viewport, set once
# in _apply_painted_preview()), not the tile-sized _cloud_drift_range_min/
# _max every non-preview room's own clouds still use unchanged. Same
# per-cloud fixed-speed-for-life, wrap-with-a-fresh-Y-and-scale shape as
# _update_cloud_drift() otherwise - only the bounds/state list differ.
func _update_painted_preview_cloud_drift(delta: float) -> void:
	if _painted_preview_cloud_drift_state.is_empty():
		return
	for entry in _painted_preview_cloud_drift_state:
		var sprite: Sprite2D = entry["sprite"]
		sprite.position.x += entry["speed"] * delta
		if sprite.position.x > _painted_preview_cloud_drift_max:
			sprite.position.x = _painted_preview_cloud_drift_min
			sprite.position.y = randf_range(cloud_band_top_y, cloud_band_bottom_y)
			var scale_val: float = randf_range(cloud_scale_min, cloud_scale_max)
			sprite.scale = Vector2(scale_val, scale_val * cloud_vertical_squash)

# Sediment mounds resting on the ground below floor_line_y - see
# seam_debris_count's own doc. Irregular blobs (_irregular_blob_shape(),
# the same vocabulary ground patches/vegetation clumps already use) -
# blob-only since 2026-08-30 (a strip pass removed a second, rectangular
# "half-buried plate" variant this used to pick between per-instance).
#
# CORRECTED (2026-08-27, "stay below the field line" fix): this used to
# deliberately straddle floor_line_y (the ORIGINAL "break up the sky/
# ground seam" brief this whole debris family was built for) - now kept
# entirely below it instead, per this fix's own brief, the same way
# _add_coastal_seam_debris() was corrected. See that function's own doc
# for why the shape has to be built before the Y position is rolled.
func _add_seam_debris() -> void:
	var right_x := _room_floor_right_x()
	for i in seam_debris_count:
		# Same depth-fraction treatment as ground patches above (2026-08-30
		# depth-variation pass) - see that loop's own doc for why t drives
		# radius/Y/color together instead of being resampled per use.
		var t := randf()
		var radius: float = lerpf(seam_debris_min_radius, seam_debris_max_radius, t)
		# Randomized per instance (2026-08-30 per-instance-variation pass)
		# - see _irregular_blob_shape()'s own doc.
		var rotation_radians := randf_range(0.0, TAU)
		var shape: PackedVector2Array = _irregular_blob_shape(radius)
		var min_y := RoomState.floor_line_y + _shape_max_upward_reach(shape, rotation_radians)
		var max_y := ROOM_FLOOR_BOTTOM_Y - GROUND_DEBRIS_BOTTOM_MARGIN_PX
		if min_y > max_y:
			push_warning("Seam debris piece (radius %.1f) can't fit entirely below floor_line_y within the ground band - skipped rather than shrunk." % radius)
			continue
		var pos := Vector2(
			randf_range(ROOM_FLOOR_LEFT_X + 40.0, right_x - 40.0),
			lerpf(min_y, max_y, t),
		)
		var color := _depth_tinted_color(seam_debris_color, t, seam_debris_depth_fade)
		_add_floor_decoration(shape, pos, color, rotation_radians)

# A few vegetation clumps straddling the seam - see seam_vegetation_
# count's own doc. Reuses _add_vegetation_clump()/vegetation_color, the
# mid-layer's own generator, just placed at the seam instead of a tile.
# CLUSTERED rather than independently random per clump (2026-08-30,
# clustering pass) - the old randf_range()-per-clump scheme spread
# clumps uniformly across the whole seam, which reads just as "planted at
# intervals" as evenly-spaced-by-index does once there are more than one
# or two - see _vegetation_cluster_x_positions()'s own doc for the shared
# algorithm (also used by _populate_mid_layer()). Same horizontal span
# and the same per-clump Y jitter as before - only WHERE along that span
# each clump's X lands changed. vegetation_min_clumps floors the count
# (see its own doc) - this seam never gets fewer than that many even if
# seam_vegetation_count is configured lower (it defaults to 2).
func _add_seam_vegetation() -> void:
	var right_x := _room_floor_right_x()
	var clump_count: int = maxi(seam_vegetation_count, vegetation_min_clumps)
	var min_x: float = ROOM_FLOOR_LEFT_X + 40.0
	var max_x: float = right_x - 40.0
	for cx in _vegetation_cluster_x_positions(min_x, max_x, clump_count):
		# t rolled first and reused for both Y and color (2026-08-30
		# depth-variation pass, vegetation follow-up) - same idiom ground
		# patches/seam debris use, so a clump's own placement and fade
		# agree. Range is unchanged from before this pass (floor_line_y -
		# 10 .. floor_line_y + 10, same distribution as the old
		# randf_range(-10.0, 10.0)) - only now expressed as a lerp so t is
		# available to drive the fade too.
		var t := randf()
		var pos := Vector2(cx, lerpf(RoomState.floor_line_y - 10.0, RoomState.floor_line_y + 10.0, t))
		var color := _depth_tinted_color(vegetation_color, t, vegetation_depth_fade)
		_add_vegetation_clump(content_root, pos, color)

# --- Ground line decoration (2026-09-06) ---
#
# Called directly from _ready(), NOT from _apply_standard_ground_
# treatment() above - that function early-returns for the opening room
# (see its own doc), and this decoration is meant for every field room
# INCLUDING the opening one (this pass's own brief: "regional texture,"
# not a standard-room-only detail).
#
# Track A alpha masks (no colour of their own - tinted here via
# `modulate`, like _add_vegetation_clump()'s white-mask contract), added
# straight into content_root at gameplay-plane depth: NOT painted_mid_
# layer, whose 0.35 motion_scale would slide these relative to the floor
# line as the camera pans, drifting off the boundary they exist to break.
#
# Seeded from RunState.current_node.id.hash() - the same per-room seed
# painted_mid_layer's own plate placement already uses (see mid_rng's own
# doc in _apply_painted_preview()) - so re-entering a room reads the same
# RunNode object and reproduces the same layout, not a fresh roll.
#
# Presence and count are two independent rolls (this pass's own brief):
# each of the five variants below first rolls independently for whether
# it appears in THIS room at all (ground_line_*_spawn_chance); separately,
# a total instance count for the room is rolled once from [ground_line_
# count_min, ground_line_count_max]. Each instance then picks uniformly
# among whichever variants passed their own presence roll - so a room
# where every variant fails its roll ends up with zero pieces regardless
# of count, the "some rooms nearly bare" case this pass's own brief asks
# for, and a room where several pass can still read sparse or dense
# depending on where count itself landed.
#
# _ground_line_decoration_nodes is cleared (queue_free, not free - see
# its own doc) before anything new is added, making this function safely
# re-callable - content_root also holds real interactive content (chests,
# NPCs, the heap/curio/forge), so unlike painted_mid_layer's own get_
# children() clear, blanket-clearing content_root itself is not an option
# here (same reason _hide_painted_preview_decorations() tracks a list
# instead of toggling a container - see its own doc).
func _populate_ground_line_decoration() -> void:
	for existing in _ground_line_decoration_nodes:
		if is_instance_valid(existing):
			existing.queue_free()
	_ground_line_decoration_nodes.clear()
	if not ground_line_enabled:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = RunState.current_node.id.hash()

	var variants: Array[Dictionary] = [
		{
			"texture": ground_line_grass_texture,
			"spawn_chance": ground_line_grass_spawn_chance,
			"height_frac": ground_line_grass_height_frac,
			"y_offset": ground_line_grass_y_offset,
			"color": ground_line_grass_color,
		},
		{
			"texture": ground_line_plank_texture,
			"spawn_chance": ground_line_plank_spawn_chance,
			"height_frac": ground_line_plank_height_frac,
			"y_offset": ground_line_plank_y_offset,
			"color": ground_line_plank_color,
		},
		{
			"texture": ground_line_ridge_texture,
			"spawn_chance": ground_line_ridge_spawn_chance,
			"height_frac": ground_line_ridge_height_frac,
			"y_offset": ground_line_ridge_y_offset,
			"color": ground_line_ridge_color,
		},
		{
			"texture": ground_line_stone_single_texture,
			"spawn_chance": ground_line_stone_single_spawn_chance,
			"height_frac": ground_line_stone_single_height_frac,
			"y_offset": ground_line_stone_single_y_offset,
			"color": ground_line_stone_single_color,
		},
		{
			"texture": ground_line_stone_cluster_texture,
			"spawn_chance": ground_line_stone_cluster_spawn_chance,
			"height_frac": ground_line_stone_cluster_height_frac,
			"y_offset": ground_line_stone_cluster_y_offset,
			"color": ground_line_stone_cluster_color,
		},
	]
	var active_variants: Array[Dictionary] = []
	for variant in variants:
		if variant["texture"] != null and rng.randf() < variant["spawn_chance"]:
			active_variants.append(variant)
	if active_variants.is_empty():
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var min_x := ROOM_FLOOR_LEFT_X
	var max_x := _room_floor_right_x()
	# [left, right] span of every piece placed so far, checked against
	# ground_line_min_gap_px below - the same direction-agnostic interval-
	# overlap test painted_mid_layer's own plate placement uses (see its
	# own doc in _apply_painted_preview()).
	var placed_spans: Array[Vector2] = []
	var count := rng.randi_range(ground_line_count_min, ground_line_count_max)
	for i in count:
		var variant: Dictionary = active_variants[rng.randi() % active_variants.size()]
		var texture: Texture2D = variant["texture"]
		var native_size: Vector2 = texture.get_size()
		var jitter: float = rng.randf_range(1.0 - ground_line_scale_jitter, 1.0 + ground_line_scale_jitter)
		var target_height: float = viewport_size.y * variant["height_frac"] * jitter
		var scale_factor: float = target_height / native_size.y
		var rendered_width: float = native_size.x * scale_factor

		var placed_x := 0.0
		var found := false
		var upper_x := maxf(min_x, max_x - rendered_width)
		for attempt in ground_line_placement_retry_limit:
			var candidate_x: float = rng.randf_range(min_x, upper_x)
			var candidate_right := candidate_x + rendered_width
			var conflict := false
			for span in placed_spans:
				if candidate_x < span.y + ground_line_min_gap_px and span.x < candidate_right + ground_line_min_gap_px:
					conflict = true
					break
			if not conflict:
				placed_x = candidate_x
				found = true
				break
		if not found:
			continue
		placed_spans.append(Vector2(placed_x, placed_x + rendered_width))

		# centered = false + offset = (-w/2, -h) anchors the rendered
		# rect's BOTTOM-CENTER to `position` (the same contract _add_
		# vegetation_clump() uses) - then y_offset nudges from there,
		# since these masks' irregular, slightly curved bottoms would
		# otherwise leave a sliver of transparent padding above floor_
		# line_y (see ground_line_grass_y_offset's own doc).
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.modulate = variant["color"]
		sprite.offset = Vector2(-native_size.x / 2.0, -native_size.y)
		sprite.position = Vector2(placed_x + rendered_width / 2.0, RoomState.floor_line_y + variant["y_offset"])
		content_root.add_child(sprite)
		_ground_line_decoration_nodes.append(sprite)

# --- Opening room (DECIDED - see DESIGN.md's Run Structure & Navigation:
# opening room, and Bestiary: The Tideworn) ---
#
# A prototype for what a BIOME-specific room could look like (see
# DESIGN.md's Biome adaptation of rooms note) - applied ONLY here.
# Every number below is local to this one room; nothing about the
# standard room size/wall styling baked into field_room.tscn changes
# for any other room type - a room this function doesn't apply to (the
# early return below) renders exactly as it always did. Called from
# _ready() AFTER _apply_wall_tint() (so whichever variant's own colors
# below win over the generic COMBAT tint that call already applied to
# every wall) and BEFORE _generate_room_contents()/_spawn_exits() (so
# room_state.gd's own opening-room content positions land correctly).
#
# The opening room's only remaining layout (2026-08-30 strip pass
# removed the INDUSTRIAL variant - see RoomState.opening_room_variant's
# own doc). RoomState.OpeningRoomVariant.INDUSTRIAL still exists as an
# enum value (not touched here - see this pass's own report), but
# nothing in the codebase sets opening_room_variant to it, and this
# function no longer branches on it: every value renders the coastal
# layout below.
func _apply_opening_room_layout() -> void:
	if RunState.current_node != RunState.opening_node:
		return
	_apply_coastal_opening_room_layout()

# --- Coastal variant ---
#
# Only LeftWall gets touched (into the ocean below); top/bottom/right
# walls, the camera limits, and the exit position all stay exactly
# whatever the standard room setup already computed (see
# _position_room_bounds()/_spawn_exits()), same as every other room -
# the opening room shares the one standard_room_width, not a variant of
# its own.
@export_group("Opening room - water extent")
@export var opening_room_water_height_above_floor: float = 260.0
# How far above RoomState.floor_line_y the water's visible AND
# collidable top edge reaches - a shore meeting the sea, not a wall of
# water spanning to the ceiling. The bottom edge is always ROOM_FLOOR_
# BOTTOM_Y (the same bound Floor's own ground-band polygon uses), so
# this one number is the whole knob for "how tall is the water." Collision
# and visual share this exact span - same "what's shown is what's real"
# principle OPENING_ROOM_OCEAN_DEPTH's own comment already holds for the
# water's horizontal depth, now applied to its height too. Tall enough
# to clear the water motion foam band's own footprint, short enough that
# the sky/mountain parallax layers (see Background layering) still show
# above it - a full-room-height band was the bug this fixes.

const OPENING_ROOM_OCEAN_DEPTH := 380.0
# How far the ocean's collision - and its matching visual fill, the
# exact same span, no gap between them - reaches in from the room's
# true left edge. The water is exactly as deep as it LOOKS; there's no
# invisible extra room to wade into past the visible shoreline (the
# same "what's shown is what's real" spirit Combat Telegraphing already
# holds damage numbers to, applied here to terrain instead).
#
# Trimmed ~15% down from an earlier 600 (by request, purely a feel/
# proportion tweak) - still has to clear a hard floor that has nothing
# to do with "how deep should the ocean look": HUD (see field_room.
# tscn's UI/HUD VBoxContainer, offset_right = 420) is a screen-space
# CanvasLayer overlay, fixed regardless of the camera - and the camera
# itself can never scroll past the room's true left edge (Camera2D.
# limit_left = 0 on Player/Camera2D), so a player standing anywhere
# near this side of the room always sees world x=0 pinned to the
# screen's left edge. That means EVERYTHING between world x=0 and x=420
# sits permanently behind the HUD, for every room, always - normally
# unnoticeable (a standard wall's own 40-52px footprint is a sliver of
# that dead zone), but a shallower ocean here would be ENTIRELY
# invisible: an earlier version of this room used depth 320, placing
# its whole span (x:20-340) inside that exact dead zone, and it
# rendered as nothing at all (confirmed by sampling actual screenshot
# pixels, not just inspecting properties - see DESIGN.md's note on
# this). 510 puts the shore line at x=530 - still comfortably past the
# HUD - so a real, visible band of water and foam keeps showing past
# it. Don't trim this much further without re-checking that margin.
# Raised from a darker (0.16, 0.34, 0.46) (2026-08-30 palette retune) -
# exempt from _validate_background_contrast()'s floors (see that
# function's own doc), so nothing forced this change, but the old value
# would have sat as a near-black sea beside the now much paler sand -
# raised to a pale, washed-out blue-gray to stay coherent with the rest
# of the opening room's retuned palette.
const OPENING_ROOM_OCEAN_COLOR := Color(0.62, 0.66, 0.68, 1)
const OPENING_ROOM_FOAM_WIDTH := 46.0
# Repurposes FieldWall's depth-shade strip (see set_depth_shade()) as a
# foam band right at the shore line instead of its usual shadow cue -
# reusing the existing mechanism for a new purpose rather than adding a
# second visual layer.
const OPENING_ROOM_SAND_COLOR := Color(0.78, 0.77, 0.72, 1)

# --- Sea (2026-09-07, sea-polygons pass) - static appearance knobs for
# _build_opening_room_sea() below. Kept as its own group, separate from
# "Opening room - water motion" below, since nothing here animates yet -
# see that pass's own brief ("static only, no motion in this session").
@export_group("Opening room - sea")
@export var opening_room_water_color_far: Color = Color(0.6831, 0.7231, 0.7529, 1.0)
# Sampled directly from background_plate.png's own sea band, just below
# the horizon (mean RGB over rows ~548-564 of the 821-tall plate - see
# this pass's own investigation report) - the water polygon's far/top
# edge reads as a continuation of the painted backdrop's own distant sea
# instead of an arbitrary color picked from nowhere.
@export var opening_room_water_color_near: Color = Color(0.5704, 0.6209, 0.6256, 1.0)
# OPENING_ROOM_OCEAN_COLOR darkened ~8% and nudged ~3.5 points (of 255)
# greener - the near/bottom edge should read as deeper water close to
# the room's own established sea tint, not identical to the far edge the
# painted plate already establishes.
@export var opening_room_water_alpha_deep: float = 0.92
@export var opening_room_water_alpha_edge: float = 0.45
# Alpha at the wall's own outward edge (deep, x=0) vs. at the waterline
# (shallow, near shore) - more opaque out where the ground strip
# shouldn't show through, more transparent right at the shore where the
# wet sand beneath should read through the water.
@export var opening_room_waterline_jitter_px: float = 18.0
# Peak amplitude of the sampled waterline curve the water/foam/wet-band
# polygons all share - see _build_opening_room_sea()'s own doc for the
# sampling method.
@export var opening_room_wet_band_px: float = 28.0
@export var opening_room_wet_band_alpha: float = 0.28
# How far onto dry ground the wet-sand stain reaches past the waterline,
# and its own opacity right at the waterline - it always fades to 0 by
# its own outer edge regardless of this value.
@export var opening_room_foam_width_px: float = 2.0
@export var opening_room_foam_alpha: float = 0.35
# opening_room_foam_color (below, in the water-motion group - reused
# here for its RGB only, not that export's own baked-in 0.55 alpha)
# supplies the static foam band's color; this is its own opacity,
# independent of the motion-pulse alpha swing that export's own group
# still owns.

# --- Water motion (DECIDED - see DESIGN.md's Run Structure &
# Navigation: opening room) ---
#
# A slow tide breath on the waterline itself, not the old field_wall.gd
# depth-shade-pulse trick (2026-09-07, tide-breath pass - REPLACES that
# mechanism entirely: _apply_coastal_opening_room_layout() now hides
# LeftWall's own wall_body/depth_shade via fully transparent colors and
# leaves depth_shade_pulse_enabled false, see that function's own doc).
# The old pulse bred alpha+position motion on ONE flat strip; this one
# moves the actual sampled waterline the water/foam polygons share
# (_build_opening_room_sea()'s own doc) back and forth by up to
# opening_room_tide_amplitude_px, so the water, the foam line riding its
# edge, and a residue foam line left at the high-water mark all read as
# one coherent tide rather than an isolated flickering strip. Driven by
# _update_opening_room_sea(), called from _process() below - no Tween, no
# AnimationPlayer, no shader (this pass's own brief).
#
# Exported here (not baked as consts like the rest of this room's
# numbers) specifically so period/amplitude/opacity can be tuned by eye
# in the Inspector without editing code - this is the one part of the
# room meant to be felt and retuned, not a fixed layout number like the
# ocean's depth.
@export_group("Opening room - water motion")
@export var opening_room_foam_color: Color = Color(0.82, 0.88, 0.86, 0.55)
@export var opening_room_tide_period_sec: float = 7.0
# One full advance-and-recede cycle - kept slow on purpose (matches the
# old pulse's own stance: this should read as background motion, never
# something that competes with the Tideworn/chest/exit for attention).
@export var opening_room_tide_amplitude_px: float = 9.0
# Peak distance the waterline (and the foam line riding it) swings from
# its own base/resting position, each direction - also what the wet
# band's own static inner edge is set back by at build time (see
# _build_opening_room_sea()'s own doc), so the retreating water never
# uncovers a dry gap between itself and the band.
@export_range(0.0, 1.0, 0.01) var opening_room_foam_advance_boost: float = 0.45
# How much brighter the foam line reads at the peak of its advance
# (phase = 0, cos(phase) = 1) than at rest - 0 would leave the foam
# flatly opaque all cycle; 1 would fade it to fully transparent at the
# deepest point of the retreat. See _update_opening_room_sea()'s own doc
# for the exact blend.
@export var opening_room_foam_residue_alpha: float = 0.22
@export var opening_room_foam_residue_fade_fraction: float = 0.4
# The residue foam line's own peak opacity, and how much of one full
# tide period its fade-out after the high-water mark takes (0.4 = 40% of
# opening_room_tide_period_sec) - see _opening_room_sea_residue_
# envelope()'s own doc for the full timing.

# --- Shoreline edge (2026-08-27) ---
#
# The water's top edge is otherwise a plain 4-point rectangle straight
# out of FieldWall._rect_points() (see field_wall.gd) - a ruler-straight
# horizontal line where the sea meets the sand/sky. That script is
# shared by all 4 room walls' geometry and stays untouched here on
# purpose, the same reasoning _add_coastal_tide_bands() already holds
# to for not touching Floor's own polygon - this is a one-room cosmetic
# need, not a generic wall feature. _add_coastal_water_edge() below
# instead overlays a second, independently wavy band on top, reusing
# _add_wavy_band()'s exact jittered-segment technique (already used a
# few hundred lines down for the tide bands) rather than inventing new
# wave math.
@export_group("Opening room - shoreline edge")
@export var coastal_water_edge_height: float = 20.0
# The wavy overlay band's own thickness, straddling water_top_y (half
# above the old flat line, half below) before wave_amplitude's jitter
# is applied - same relationship coastal_tide_band_height already has
# to its own wave_amplitude.
@export var coastal_water_edge_wave_amplitude: float = 22.0
# How far each segment's top/bottom edge wanders from that band, in
# EITHER direction - this is the number that actually breaks up the
# hard waterline. Drawn in the ocean's own color (see _add_coastal_
# water_edge()), so only the UPWARD half of that wander (peaks poking
# past the old flat line into what used to be dry sand/sky) is
# visible; the downward half just repaints already-ocean-colored area,
# which is fine - it's not a wasted half, it's what keeps the band's
# average position anchored on the real waterline instead of drifting.

# The region's continuous ambient bed (2026-08-31 ambient pass) - EVERY
# field room in the current biome gets this, not just the opening room
# (contrast OPENING_ROOM_MUSIC_TRACK just below, which is gated to one
# specific room), so it's called unconditionally from _ready() rather
# than from inside _apply_opening_room_layout(). Reads BiomeData.ambient_
# loop_name (RunState.current_biome, always non-null - see biome_data.gd's
# own doc and battle.gd's _apply_battle_backdrop() for the same
# assumption) rather than a local constant, since a second region will
# want its own different track through the exact same call site - this
# function never changes for that, only the .tres data does.
#
# play_looping() no-ops if the named loop is already playing (see its own
# doc) - calling this every room load is what lets scene_transition.gd's
# go_to() exempt this one loop from its usual stop-everything sweep for a
# field-room-to-field-room transition (see AudioManager.stop_all_looping_
# except() and go_to()'s own ambient-bed note) and still have this line
# behave correctly either way: already playing (room-to-room, survived
# the swap) -> no-op, silent continuation; not playing (arriving fresh
# from battle, an interior, or the reward screen, where it WAS stopped)
# -> starts it. Neither branch needs this function to know which case
# it's in.
func _start_region_ambient_bed() -> void:
	var ambient_loop_name := RunState.current_biome.ambient_loop_name
	if ambient_loop_name != "":
		AudioManager.play_looping(ambient_loop_name)

# The region's continuous field MUSIC bed (2026-09-03, Region 1 field
# music pass) - the direct MusicManager counterpart to _start_region_
# ambient_bed() just above, same shape for the same reason: reads
# BiomeData.field_music_track (SunkenWorks' own value) rather than a
# local constant, so a second region's own track slots in as data
# through this exact call site, no code change needed here.
#
# SKIPPED for the opening room specifically (unlike the ambient bed just
# above, which really does apply everywhere unconditionally) - the
# opening room's own OPENING_ROOM_MUSIC_TRACK is authored SECOND in
# _ready()'s own sequence (via _apply_opening_room_layout(), called
# after this) and unconditionally calls play_music() itself, so calling
# it HERE first too would just get overridden a moment later - but not
# for free: a genuine regression this guard exists to prevent, confirmed
# live during this pass's own verification. Without it, reloading the
# SAME opening room (its own play_music(OPENING_ROOM_MUSIC_TRACK) call
# would otherwise no-op, since that exact track is already playing -
# see play_music()'s own guard) instead restarts room1_waves from 0
# every time, because THIS call's own intermediate play_music(field_
# music_track) swap - immediately superseded, but still a real swap -
# clears whatever was actually already playing first. Every OTHER
# Region 1 field room has no such override coming later, so this call is
# genuinely the only one that matters for them.
func _start_region_field_music() -> void:
	if RunState.current_node == RunState.opening_node:
		return
	var field_music_track := RunState.current_biome.field_music_track
	if field_music_track != "":
		MusicManager.play_music(field_music_track)

const OPENING_ROOM_MUSIC_TRACK := "room1_waves"
# See music_manager.gd's MUSIC_FILES - a looping ambience, not a one-
# shot SFX, so it belongs with MusicManager rather than AudioManager.
# Reuses the exact same lifecycle the title theme already has: scene_
# transition.gd's go_to() stops whatever music is playing at the START
# of every transition, so this stops itself the instant the player
# leaves (through the exit door OR into the Tideworn fight) with no
# special-casing needed here - and picks back up automatically if they
# return to this room after the fight, since _ready() runs again on
# every fresh load.

# Cached by _build_opening_room_sea() below, read back every frame by
# _update_opening_room_sea() (2026-09-07, tide-breath pass) - null for
# every room except the opening one, the same "null check makes the
# per-frame call a cheap no-op everywhere else" shape _opening_room_
# hull_line_label above already uses. _sea_sample_ys/_sea_base_xs are the
# waterline curve's own y-per-sample and BASE (resting, tide-offset-free)
# x-per-sample - the fixed shape _update_opening_room_sea() rebuilds
# water's/foam's own polygons from each frame by adding the current tide
# offset, never re-sampled or re-seeded after room load.
var _sea_sample_ys: Array[float] = []
var _sea_base_xs: Array[float] = []
var _sea_water: Polygon2D = null
var _sea_foam: Polygon2D = null
var _sea_foam_residue: Polygon2D = null
var _sea_wet_band: Polygon2D = null
var _sea_time: float = 0.0

# Builds the opening room's sea as four translucent Polygon2D layers -
# a wet-sand stain on the dry side of the waterline, the water itself, a
# thin foam band straddling the waterline, and a residue foam band at the
# high-water mark (2026-09-07, sea-polygons pass; residue layer and the
# wet band's own tide-aware inset added in the same day's tide-breath
# pass) - REPLACES LeftWall's own wall_body/depth_shade as the visual
# water (see _apply_coastal_opening_room_layout()'s own call site, which
# now hides those via fully transparent colors instead of deleting them -
# collision is completely unaffected, left_wall.configure() there still
# owns the real walk bound).
#
# All four are inserted directly after floor_polygon in tree order via
# move_child(..., floor_polygon.get_index() + N) (the residue band via
# move_child(..., foam.get_index() + 1) instead, right after foam itself,
# since foam's own final index isn't known until after it's placed) -
# drawn in front of the ground strip (now visible underneath, see this
# pass's own removal of the floor's old shore inset) and behind
# everything else (Content, Player, Foreground), the same slot LeftWall's
# own visuals used to sit in within this draw stack.
#
# Duplicates water_top_y/water_bottom_y's own expressions rather than
# threading them in as parameters - the same "two lines of duplication is
# cheaper than touching working code for a shared field" call _coastal_
# shore_x()'s own doc already makes for this exact function.
#
# The ragged waterline curve itself is baked once here, from a seeded
# sample, and never re-rolled - _update_opening_room_sea() (called from
# _process() below) only ever adds a per-frame tide OFFSET on top of the
# cached _sea_base_xs, it doesn't reshape the curve. wet_band is the one
# layer built here and never touched again - see its own doc below for
# why its inner edge is set back by opening_room_tide_amplitude_px in
# anticipation of the tide, rather than needing its own per-frame update.
func _build_opening_room_sea() -> void:
	var water_top_y := RoomState.floor_line_y - opening_room_water_height_above_floor
	var water_bottom_y := _floor_span_bottom_y()
	var shore_x := _coastal_shore_x()
	# The wall's own TRUE outward edge - world x=0, the room's true left
	# boundary (see _apply_coastal_opening_room_layout()'s own doc on why
	# that's where the ocean's collision/visual both reach now). Not
	# re-derived from left_wall's own configure() params here - 0.0 is
	# already the established literal every other true-left-edge caller
	# in this file uses (_floor_span_left_x()'s own opening-room branch,
	# among others).
	var outward_x := 0.0

	# The ragged waterline curve, sampled once and shared by the water
	# polygon's own right edge, the foam band, and the wet band, so all
	# three trace the exact same line instead of three independently-
	# rolled near-misses. Seeded the same way the mid-plate loop seeds its
	# own per-room RNG (RunState.current_node.id.hash()) - the opening
	# node's own id is constant for the life of a run (it's always the
	# same RunNode, unlike a generated combat room's), so this curve is
	# the same every time this room loads, which is expected, not a bug -
	# nothing asked for it to vary.
	const WATERLINE_WAVELENGTH_A := 140.0
	const WATERLINE_WAVELENGTH_B := 310.0
	const WATERLINE_SAMPLE_STEP_PX := 24.0
	const WATERLINE_NOISE_PX := 2.0
	var waterline_rng := RandomNumberGenerator.new()
	waterline_rng.seed = RunState.current_node.id.hash()
	var phase_a := waterline_rng.randf_range(0.0, TAU)
	var phase_b := waterline_rng.randf_range(0.0, TAU)
	var span := water_bottom_y - water_top_y
	var sample_count := maxi(2, ceili(span / WATERLINE_SAMPLE_STEP_PX) + 1)
	var sample_ys: Array[float] = []
	var waterline_xs: Array[float] = []
	var row_colors: Array[Color] = []
	for i in sample_count:
		var y: float = lerpf(water_top_y, water_bottom_y, float(i) / float(sample_count - 1))
		# Amplitude scales with depth_t (0 at water_top_y/far-shallow-end,
		# 1 at water_bottom_y/near-the-player's-feet end) so the waterline
		# reads as receding into the distance at the top instead of
		# jittering as wildly there as it does at the near end.
		var depth_t: float = (y - water_top_y) / span
		var depth_scale: float = lerpf(0.4, 1.0, depth_t)
		var sine_sum: float = sin(TAU * y / WATERLINE_WAVELENGTH_A + phase_a) + sin(TAU * y / WATERLINE_WAVELENGTH_B + phase_b)
		var noise: float = waterline_rng.randf_range(-WATERLINE_NOISE_PX, WATERLINE_NOISE_PX)
		var x: float = shore_x + sine_sum * opening_room_waterline_jitter_px * depth_scale + noise
		sample_ys.append(y)
		waterline_xs.append(x)
		row_colors.append(opening_room_water_color_far.lerp(opening_room_water_color_near, depth_t))

	# --- Wet band: dry-side stain along the waterline, fading out onto
	# dry sand. A ladder like the water polygon below (see its own doc)
	# so a ragged waterline doesn't leave the fade running at an angle
	# across a straight-edged quad. Built ONCE and never touched again
	# (2026-09-07, tide-breath pass) - its own inner edge is set back by
	# opening_room_tide_amplitude_px from the base waterline, i.e. exactly
	# as far INTO the water as the tide's own retreat ever reaches, so the
	# water's real edge (which does move, see _update_opening_room_sea())
	# never uncovers a dry gap between itself and this band even at
	# maximum retreat - at every other point in the cycle the water
	# simply overlaps a little more of it.
	var wet_band := Polygon2D.new()
	add_child(wet_band)
	move_child(wet_band, floor_polygon.get_index() + 1)
	wet_band.color = Color.BLACK
	var wet_points: PackedVector2Array = []
	var wet_colors: PackedColorArray = []
	for i in sample_count:
		wet_points.append(Vector2(waterline_xs[i] - opening_room_tide_amplitude_px, sample_ys[i]))
		wet_colors.append(Color(0.0, 0.0, 0.0, opening_room_wet_band_alpha))
	for i in range(sample_count - 1, -1, -1):
		wet_points.append(Vector2(waterline_xs[i] + opening_room_wet_band_px, sample_ys[i]))
		wet_colors.append(Color(0.0, 0.0, 0.0, 0.0))
	wet_band.polygon = wet_points
	wet_band.vertex_colors = wet_colors

	# --- Water: from the wall's outward edge to the waterline. Built as a
	# ladder - left edge carries the SAME y samples as the waterline, at a
	# fixed x (outward_x), rather than a single straight edge plus a
	# fanned/triangulated fill - so vertex_colors interpolate row by row
	# in clean horizontal bands instead of fanning out from one corner,
	# the same reasoning a naive single-quad-per-side triangulation would
	# get wrong for a non-straight opposite edge.
	var water := Polygon2D.new()
	add_child(water)
	move_child(water, floor_polygon.get_index() + 2)
	var water_points: PackedVector2Array = []
	var water_colors: PackedColorArray = []
	for i in sample_count:
		water_points.append(Vector2(outward_x, sample_ys[i]))
		var deep_color: Color = row_colors[i]
		deep_color.a = opening_room_water_alpha_deep
		water_colors.append(deep_color)
	for i in range(sample_count - 1, -1, -1):
		water_points.append(Vector2(waterline_xs[i], sample_ys[i]))
		var edge_color: Color = row_colors[i]
		edge_color.a = opening_room_water_alpha_edge
		water_colors.append(edge_color)
	water.polygon = water_points
	water.vertex_colors = water_colors

	# --- Foam: thin band straddling the waterline, flat color/alpha (no
	# vertex_colors needed - opening_room_foam_alpha is uniform across it).
	var foam := Polygon2D.new()
	add_child(foam)
	move_child(foam, floor_polygon.get_index() + 3)
	foam.color = Color(opening_room_foam_color.r, opening_room_foam_color.g, opening_room_foam_color.b, opening_room_foam_alpha)
	var foam_half := opening_room_foam_width_px / 2.0
	var foam_points: PackedVector2Array = []
	for i in sample_count:
		foam_points.append(Vector2(waterline_xs[i] - foam_half, sample_ys[i]))
	for i in range(sample_count - 1, -1, -1):
		foam_points.append(Vector2(waterline_xs[i] + foam_half, sample_ys[i]))
	foam.polygon = foam_points

	# --- Residue foam: same construction as foam above, but at the
	# HIGH-water mark (base_x + tide_amplitude, not base_x) - the thin
	# line of foam a wave leaves behind at its own furthest advance,
	# separate from the foam line riding the live waterline. Inserted
	# right after foam itself (foam.get_index(), not floor_polygon's own -
	# foam's final index among its siblings isn't known until after its
	# own move_child() above has run). Starts fully transparent -
	# _update_opening_room_sea() (called from _process() below) is what
	# ever brings it into view, once per tide cycle, near the peak.
	var foam_residue := Polygon2D.new()
	add_child(foam_residue)
	move_child(foam_residue, foam.get_index() + 1)
	foam_residue.color = Color(opening_room_foam_color.r, opening_room_foam_color.g, opening_room_foam_color.b, opening_room_foam_alpha)
	var residue_points: PackedVector2Array = []
	for i in sample_count:
		residue_points.append(Vector2(waterline_xs[i] + opening_room_tide_amplitude_px - foam_half, sample_ys[i]))
	for i in range(sample_count - 1, -1, -1):
		residue_points.append(Vector2(waterline_xs[i] + opening_room_tide_amplitude_px + foam_half, sample_ys[i]))
	foam_residue.polygon = residue_points
	foam_residue.modulate.a = 0.0

	_sea_sample_ys = sample_ys
	_sea_base_xs = waterline_xs
	_sea_water = water
	_sea_foam = foam
	_sea_foam_residue = foam_residue
	_sea_wet_band = wet_band
	_sea_time = 0.0

# Called every frame from _process() above (2026-09-07, tide-breath pass).
# Cheap no-op everywhere except the opening room, the same "null check on
# a cached ref" shape _update_opening_room_hull_line() already uses -
# _sea_water is null for every OTHER room (never assigned outside
# _build_opening_room_sea(), which only that room's own layout calls),
# and is_instance_valid() covers the same node having been freed out from
# under this room's own instance for any other reason.
#
# Rebuilds water's and foam's own polygons fresh each frame from the
# cached _sea_sample_ys/_sea_base_xs plus the current tide offset, rather
# than mutating the existing PackedVector2Array in place - simpler and
# just as cheap at ~30 vertices per polygon (this pass's own brief) than
# working out the ladder's own interleaved index math for an in-place
# edit would have been. vertex_colors are never touched here - same
# array, same order, every frame, exactly what _build_opening_room_sea()
# already set once.
func _update_opening_room_sea(delta: float) -> void:
	if _sea_water == null or not is_instance_valid(_sea_water):
		return
	_sea_time += delta
	var phase := TAU * _sea_time / opening_room_tide_period_sec
	var offset := opening_room_tide_amplitude_px * sin(phase)
	var cos_phase := cos(phase)
	var advancing := cos_phase > 0.0 # true while the waterline is moving toward the sand, not used numerically below - the max(0, cos(phase)) terms already fall to 0 through the same half of the cycle this flags.

	var count := _sea_sample_ys.size()
	var water_points: PackedVector2Array = []
	for i in count:
		water_points.append(Vector2(0.0, _sea_sample_ys[i])) # outward_x - see _build_opening_room_sea()'s own doc for why this is the literal 0.0 every true-left-edge caller in this file uses.
	for i in range(count - 1, -1, -1):
		water_points.append(Vector2(_sea_base_xs[i] + offset, _sea_sample_ys[i]))
	_sea_water.polygon = water_points

	if _sea_foam != null and is_instance_valid(_sea_foam):
		var foam_half := opening_room_foam_width_px / 2.0
		var foam_points: PackedVector2Array = []
		for i in count:
			foam_points.append(Vector2(_sea_base_xs[i] + offset - foam_half, _sea_sample_ys[i]))
		for i in range(count - 1, -1, -1):
			foam_points.append(Vector2(_sea_base_xs[i] + offset + foam_half, _sea_sample_ys[i]))
		_sea_foam.polygon = foam_points
		# cos(phase), not sin(phase) - this peaks at phase=0 (the instant
		# offset=amplitude*sin(phase) is crossing 0 while climbing
		# fastest, i.e. the water advancing at its own quickest), NOT at
		# phase=PI/2 where the waterline itself sits furthest forward
		# (see _opening_room_sea_residue_envelope()'s own PEAK_PHASE,
		# which uses THAT instant instead - a different, later moment in
		# the same cycle). Brightest while the water is rushing in fastest,
		# dimmest through the whole retreating half (cos<0, clamped to 0
		# rather than dipping negative - a foam line doesn't have less-
		# than-nothing to show on the way out, it just stops being boosted).
		_sea_foam.modulate.a = (1.0 - opening_room_foam_advance_boost) + opening_room_foam_advance_boost * maxf(0.0, cos_phase)

	if _sea_foam_residue != null and is_instance_valid(_sea_foam_residue):
		_sea_foam_residue.modulate.a = opening_room_foam_residue_alpha * _opening_room_sea_residue_envelope(phase)

# The residue foam band's own opacity envelope over one tide cycle, as a
# fraction of opening_room_foam_residue_alpha (2026-09-07, tide-breath
# pass). Phase-only, not time-only, so it stays correct regardless of
# opening_room_tide_period_sec: 0 for most of the cycle; ramps 0->1
# (smoothstep, so it doesn't pop into existence) over the last 5% of the
# period BEFORE the peak; holds effectively 1 exactly at the peak
# (phase = PI/2, the same instant _update_opening_room_sea()'s own cos-
# based foam boost also peaks); then fades 1->0 (smoothstep again) across
# the following opening_room_foam_residue_fade_fraction of the period.
# fposmod(), not fmod() - phase - PEAK_PHASE can be negative (any time
# before the peak within one cycle), and this needs a result that's
# always in [0, TAU), never negative, to compare cleanly against the two
# windows below.
func _opening_room_sea_residue_envelope(phase: float) -> float:
	const PEAK_PHASE := PI / 2.0
	const RAMP_IN_FRACTION := 0.05
	var fade_phase: float = TAU * opening_room_foam_residue_fade_fraction
	var ramp_phase: float = TAU * RAMP_IN_FRACTION
	var rel: float = fposmod(phase - PEAK_PHASE, TAU)
	if rel < fade_phase:
		var fade_t: float = rel / fade_phase
		return 1.0 - smoothstep(0.0, 1.0, fade_t)
	var pre_peak: float = TAU - rel
	if pre_peak < ramp_phase:
		var ramp_t: float = 1.0 - pre_peak / ramp_phase
		return smoothstep(0.0, 1.0, ramp_t)
	return 0.0

func _apply_coastal_opening_room_layout() -> void:
	# The ocean reaches the room's TRUE outer edges now, on both the left
	# (0) and the bottom (_floor_span_bottom_y(), the same taller-than-_room_
	# height() value the floor polygon itself reaches at a wide RoomState.
	# field_zoom - 2026-09-07, opening-room floor-bottom fix, REPLACES a
	# flat _room_height() here that used to leave the ocean and the floor
	# stopping short together, exposing empty space beneath both) - not
	# x=20/ROOM_FLOOR_BOTTOM_Y,
	# which left a real, confirmed-visible gap in each direction once
	# LeftWall/BottomWall's own rendered bodies (which used to cover that
	# last sliver) were removed (see _apply_room_framing()). Collision and
	# visual both reach exactly this far, with no void margin (a gap here
	# would read as the water floating just short of the true boundary
	# instead of continuing all the way to it) - the same "what's shown
	# is what's real" principle this room's own depth-tuning notes already
	# hold to. The SHORE line (the ocean's inner/right edge, where it
	# meets the sand) is UNCHANGED - still exactly 20.0 + OPENING_ROOM_
	# OCEAN_DEPTH, the same carefully-tuned distance past the HUD's own
	# dead zone (see that const's own comment) - only the ocean's OUTWARD
	# reach grew to close the gap, not where it meets the shore.
	#
	# Vertically, the water's TOP still rises only opening_room_water_
	# height_above_floor above RoomState.floor_line_y - a shore, not a
	# wall reaching the sky. Background's sky parallax layers (already
	# drawn BEHIND every wall in tree order - see field_room.tscn) show
	# through above that line unobstructed now that the water no longer
	# occupies the whole vertical span.
	var water_top_y := RoomState.floor_line_y - opening_room_water_height_above_floor
	var water_bottom_y := _floor_span_bottom_y()
	var water_half_length := (water_bottom_y - water_top_y) / 2.0
	var water_center_y := (water_top_y + water_bottom_y) / 2.0
	var ocean_depth := 20.0 + OPENING_ROOM_OCEAN_DEPTH
	var ocean_half_thickness := ocean_depth / 2.0
	left_wall.position = Vector2(ocean_half_thickness, water_center_y)
	left_wall.configure(water_half_length, ocean_half_thickness, ocean_depth, 0.0)
	# Re-enabled here (see _apply_room_framing(), which turns it off by
	# default) - the ocean IS real biome content, exactly the kind of
	# thing a plain wall band was standing in for, not a UI frame.
	left_wall.set_visual_enabled(true)
	# Transparent, not disabled outright (2026-09-07, sea-polygons pass) -
	# LeftWall's own wall_body/depth_shade used to BE the visual water; now
	# _build_opening_room_sea() below draws it instead, as three separate
	# Polygon2D layers in front of the ground strip. Collision is completely
	# unaffected either way - configure() just above still owns the real
	# walk bound - so leaving the wall's visual pipeline running (just
	# invisible) rather than calling set_visual_enabled(false) keeps this
	# close to every other wall's own default state, not a special case.
	# The pulse is rebuilt on the new nodes in a later motion pass - not
	# ported here (this pass is static only, see its own brief).
	left_wall.set_wall_color(Color(0.0, 0.0, 0.0, 0.0))
	left_wall.set_depth_shade(Color(0.0, 0.0, 0.0, 0.0), OPENING_ROOM_FOAM_WIDTH)
	left_wall.depth_shade_pulse_enabled = false
	_add_coastal_water_edge()
	_build_opening_room_sea()

	# No left inset any more (2026-09-07, sea-polygons pass - REMOVES the
	# vertex 0/3 x-shift and its matching floor_polygon.uv[0]/[3].x delta
	# this used to carry, both untouched-since-23d0cc3 until now) - the
	# ground strip used to stop at the shore line because the ocean was an
	# OPAQUE wall sitting in front of whatever the floor did under it, so
	# insetting the floor there was free (nothing could ever show the
	# difference). Now the water is translucent Polygon2D layers over the
	# ground (_build_opening_room_sea() below), so the ground has to
	# actually BE there to show through - Floor keeps _position_floor()'s
	# own natural left edge (0, same as every other room) and its own
	# unmodified UVs, and simply runs on under the sea like real ground
	# does. left_wall.configure() above is completely unaffected - the
	# real walk bound still stops at the same collision footprint it
	# always has, this only changes what's drawn, not where the player
	# can stand.
	floor_polygon.color = OPENING_ROOM_SAND_COLOR
	_apply_floor_depth_tint(OPENING_ROOM_SAND_COLOR)

	# Sand texture (2026-08-26) - called from HERE, after the sand color
	# above, not from _apply_standard_ground_treatment() (which
	# runs earlier in _ready() and still excludes this room entirely, see
	# its own header) - see _coastal_shore_x()'s own doc for why that
	# ordering actually matters: the shore line these three read as their
	# left bound isn't known until the lines just above have run.
	if not use_field_backdrop:
		_add_coastal_tide_bands()
		_add_coastal_seam_debris()
		_add_coastal_seam_vegetation()

	# Only a FRESH visit - has_saved_position (see _ready(), which runs
	# after this) still wins and restores wherever the player was
	# standing before a return trip from the Tideworn fight, exactly
	# like every other room.
	player.global_position = Vector2(RoomState.opening_room_player_spawn_x, RoomState.floor_line_y)

	MusicManager.play_music(OPENING_ROOM_MUSIC_TRACK)

# The opening room's INDUSTRIAL layout variant (void/starfield boundary,
# concrete floor/walls, support beams, floor stains/cracks/rust) was
# removed in the 2026-08-30 strip pass, along with its own tuning
# exports and hand-placed position/size constants. See this pass's own
# report for what that removal touched.

# An N-point polygon like a star shape, with each point's radius
# jittered independently at call time (blob_jitter_min..blob_jitter_max)
# instead of read from one shared fixed table - every call produces its
# own one-off outline, so no two blobs on screen share a silhouette even
# at the same radius (2026-08-30 per-instance-variation pass; the old
# OPENING_ROOM_BLOB_JITTER 8-entry table produced the exact same
# silhouette, just rescaled, at every call site and every size). Point
# count raised from 8 to 12 (blob_point_count) for a softer, less
# faceted mass - Bible §14 ("nature... simplification") called for
# grouped masses over literal detail, and a faceted 8-point star read as
# more "star" than "stain." Still reused for several unrelated purposes
# per call site (ground patch, seam debris, coastal seam debris,
# particulate) - see each call site for its own radius and (for
# everything except particulates) its own randomized rotation.
# Vegetation was never a caller of THIS shape - it's textured now (see
# vegetation_clump_textures's own doc), and never rotates either way,
# for the same "growth has an up direction" reason its own doc gives.
@export_group("Ground - blob shape")
@export var blob_point_count: int = 12
@export_range(0.0, 1.0, 0.01) var blob_jitter_min: float = 0.65
@export_range(1.0, 2.0, 0.01) var blob_jitter_max: float = 1.3
# Same 0.65/1.3 span the old fixed 8-entry table used - keeps every
# existing caller's on-screen size envelope unchanged; only the fixed
# per-index pattern is gone, not the overall range.

func _irregular_blob_shape(base_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in blob_point_count:
		var angle := i * TAU / float(blob_point_count)
		var r := base_radius * randf_range(blob_jitter_min, blob_jitter_max)
		points.append(Vector2(cos(angle), sin(angle)) * r)
	return points

# A thin zigzagging sliver rather than a straight line - reads as a
# crack instead of a seam. Built once as a shape, then positioned AND
# rotated per instance (see _apply_standard_ground_treatment()) rather
# than hand-computing rotated endpoints, the same way
# _add_floor_decoration() already handles other floor decorations.
func _crack_shape(length: float, width: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-length / 2.0, 0), Vector2(-length / 4.0, width / 2.0),
		Vector2(length / 4.0, -width / 3.0), Vector2(length / 2.0, 0),
		Vector2(length / 4.0, -width / 2.0), Vector2(-length / 4.0, width / 3.0),
	])

# How far a shape's own vertices reach ABOVE its local origin (the most
# negative Y after rotation, negated to a positive distance) - exactly
# how far a center-anchored decoration's own topmost rendered pixel
# sits above wherever `decoration_position` gets placed (2026-08-27,
# "stay below the field line" fix). Every shape this file builds
# (_irregular_blob_shape()/_crack_shape()) is centered on local (0,0)
# and only ever offset/rotated as a whole via Polygon2D.position/
# rotation (see _add_floor_decoration() below) - never scaled or skewed -
# so rotating each vertex with the engine's own Vector2.rotated() (the
# exact transform Polygon2D.rotation applies at render time) and taking
# the smallest resulting Y is EXACT, not an approximation. Deliberately
# NOT the existing `radius * blob_jitter_max` leftward-reach margin
# _add_coastal_seam_debris() already uses for its own horizontal
# placement - that constant is specific to blobs AND to the horizontal
# direction (see its own doc for why that peak, not a fixed index, is
# the relevant bound now that per-vertex jitter is rolled per call
# rather than read from a table); the true vertical reach for a given
# blob is whatever THIS function actually measures for it, which is why
# blobs use this function instead of a second hand-picked vertical
# constant, and a crack's own reach is shape- and rotation-dependent in a
# way no single hand-picked constant could cover for every future shape
# this file might add.
func _shape_max_upward_reach(shape: PackedVector2Array, rotation_radians: float = 0.0) -> float:
	var max_reach := 0.0
	for point in shape:
		var rotated_point := point.rotated(rotation_radians)
		max_reach = maxf(max_reach, -rotated_point.y)
	return max_reach

# Shared by every floor decoration this file draws (ground patches/
# cracks, seam debris, coastal seam debris) - a shape centered on
# `decoration_position` (and optionally rotated), purely decorative, no
# collision, added to content_root.
func _add_floor_decoration(shape: PackedVector2Array, decoration_position: Vector2, color: Color, rotation_radians: float = 0.0) -> void:
	var decoration := Polygon2D.new()
	decoration.color = color
	decoration.polygon = shape
	decoration.position = decoration_position
	decoration.rotation = rotation_radians
	content_root.add_child(decoration)
	_painted_preview_decoration_nodes.append(decoration)

func _apply_wall_tint() -> void:
	var color: Color
	match RoomState.current_room_type:
		RoomType.Kind.BOSS:
			color = BOSS_WALL_COLOR
		RoomType.Kind.ELITE:
			color = ELITE_WALL_COLOR
		_:
			color = NORMAL_WALL_COLOR
	for wall in walls:
		wall.set_wall_color(color)

# Room framing removal (DECIDED - see DESIGN.md's Run Structure &
# Navigation) - none of the four walls render a visible slab by default
# any more, since in the side-scrolling layout a plain colored band at
# ANY of the room's edges reads as an artificial UI frame around the
# playfield, not architecture. Originally just LeftWall/RightWall (the
# horizontal edges the player actually walks toward and bumps into);
# TopWall/BottomWall turned out to have the exact same problem even
# though the player never approaches them directly - the camera shows
# the room's full height at all times (see the composition & scale
# pass's own note on why: room height == viewport height leaves no
# vertical scroll room at all), so their band was ALWAYS on screen,
# every room, not just at an extreme. Room edges are defined by real
# content instead (structures thinning out, terrain, water) - see
# _apply_coastal_opening_room_layout(), which re-enables LeftWall's
# visual right after turning it into exactly that kind of real content
# (the ocean), since a real feature is what a rendered border was
# standing in for. RightWall/TopWall/BottomWall never get re-enabled
# anywhere - nothing repurposes any of them into content, in any room.
#
# Collision is completely unaffected - see FieldWall.set_visual_enabled()
# for why: only wall_body/depth_shade (plain Polygon2D children with no
# collision role) are hidden, CollisionShape2D is untouched, so the
# player is blocked in exactly the same place as before, just without a
# rendered marker showing where.
func _apply_room_framing() -> void:
	left_wall.set_visual_enabled(false)
	right_wall.set_visual_enabled(false)
	top_wall.set_visual_enabled(false)
	bottom_wall.set_visual_enabled(false)

# Combat AND elite rooms stay locked - every door in the room, at once -
# until every blob listed in RoomState.room_layout is marked defeated -
# see DESIGN.md's Run Structure & Navigation for why (avoidance decisions
# come later with aggro/branching mechanics; for now a fight room is
# about fighting, and an ELITE room is still fundamentally a fight room -
# see DESIGN.md's ELITE Rooms section).
#
# TREASURE joined this list (2026-08-29, three-chest treasure room) -
# locked until ANY ONE of its chests has been opened (RoomState.chest_
# opened has at least one entry for a chest_id in this room's own
# layout), then stays unlocked for good, same "cleared means cleared,
# never re-locks" shape COMBAT/ELITE's own blob check already has. This
# is also the ONLY room type whose exit-lock check gets called a SECOND
# time outside this function's own single call site (see _on_any_chest_
# claimed()) - opening a chest never reloads field_room.tscn the way
# defeating a blob does, so nothing else would ever re-run this for
# TREASURE otherwise. Every other room type was never locked in the
# first place.
func _update_exit_lock() -> void:
	var cleared: bool
	match RoomState.current_room_type:
		RoomType.Kind.COMBAT, RoomType.Kind.ELITE:
			cleared = true
			for entry in RoomState.room_layout:
				if entry["kind"] == "blob" and not RoomState.blob_defeated.get(entry["id"], false):
					cleared = false
					break
		RoomType.Kind.TREASURE:
			cleared = false
			for entry in RoomState.room_layout:
				if entry["kind"] == "chest" and RoomState.chest_opened.get(entry["chest_id"], false):
					cleared = true
					break
		_:
			for door in exits:
				door.unlock(false)
			return
	if cleared and not exits.is_empty():
		AudioManager.play_sfx("door_unlock") # Once for the room, not once per door.
	for door in exits:
		if cleared:
			door.unlock(true)
		else:
			door.lock()
