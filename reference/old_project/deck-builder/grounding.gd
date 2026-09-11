extends Node
class_name Grounding
# Composed by battle entities (enemy.gd, player_battle_visual.gd) as a
# plain child node, one instance each - NOT shared between them, so each
# gets its own Inspector-tunable export values (enemy.tscn's own Grounding
# instance and player_battle_visual.tscn's own can be tuned independently),
# same "per-scene @export group" shape every other per-entity tunable in
# this project already uses. Holds no visual content itself (extends Node,
# not Node2D/Control) - it only builds/attaches things onto whatever
# `entity_root`/`measure_root` its owner hands it, when its owner calls
# apply_contact_shadow()/apply_foreground_occluder(). Not called from this
# node's own _ready(): the owner doesn't know its own measured silhouette
# bounds until AFTER its visual has been instanced (see enemy.gd's
# _setup_visual(), player_battle_visual.gd's _setup_visual()) - the same
# ordering constraint EntityShadow.attach() itself is already built around.
#
# Reflection is NOT part of this scene (2026-09-01, battle grounding pass,
# revised scope) - cut from this pass per its own brief: the player's
# visual root is a single centered Sprite2D, the enemy's is a CanvasGroup
# of hand-drawn Polygon2D pieces composited for a rim shader - two
# structurally different things, so a shared reflection implementation
# here would be two implementations wearing one shared name, not one
# system. Gets its own commit after the shadow is tuned.

@export_group("Contact Shadow")
@export var contact_shadow_enabled: bool = true
@export_range(0.0, 2.0, 0.01) var contact_shadow_width_ratio: float = 0.55
@export_range(0.0, 1.0, 0.01) var contact_shadow_height_ratio: float = 0.18
@export var contact_shadow_y_offset: float = 0.0
# Battle's own default (0.0), deliberately NOT RoomState.entity_shadow_y_
# offset's field default (-18.0) - that correction exists for field
# silhouettes whose measured bounds don't already land their bottom edge
# exactly on the ground (see RoomState's own doc). Both battle conventions
# (enemy: feet-at-origin authored art; player: a centered sprite whose own
# bottom edge is the figure's feet) already measure their real bottom edge
# correctly via VisualBounds - see this pass's own Phase 1 report. Tune
# per-instance if a specific silhouette's own art proves otherwise.
@export_range(0.0, 1.0, 0.01) var contact_shadow_alpha: float = 0.65
# RAISED from 0.35, then 0.55, now 0.65 (2026-09-01, color-derivation +
# anchor-gap fixes) - the 0.35->0.55 step alone was tuned BEFORE the
# anchor-gap fix (the shadow was landing ~40px of native-canvas-padding
# below the actual feet at the time), so it was partly compensating for a
# placement bug, not just legibility. With placement now correct (tight
# under the feet, confirmed live), re-judged at 100% zoom (not a crop) on
# both plates and raised again alongside luminance_drop below.
@export_range(0.0, 1.0, 0.01) var contact_shadow_luminance_drop: float = 0.48
# RAISED from 0.35 (2026-09-01, same pass as the alpha raise above) - re-
# judged at 100% zoom once the anchor-gap fix put the shadow in its
# correct position; 0.35 read as too faint at actual play resolution even
# though it was clearly visible in a zoomed crop. See this export's own
# original doc below for the luminance-TARGET model itself (unchanged) -
# only the magnitude moved.
# REPLACES contact_shadow_darken_factor (2026-09-01, color-derivation
# fix) - percentage-darkening was the wrong model: on a pale plate (wet
# ground_color_wet is (0.71, 0.68, 0.65), HSV value 0.71) a 30% relative
# darken lands at value ~0.50, which combined with alpha well under 1.0
# reads as noise against similarly-pale wet sand, not a distinct object -
# confirmed live (see this pass's own investigation: the render path
# itself was fine, forcing an opaque near-black color made the exact same
# geometry clearly visible). This is now an ABSOLUTE luminance (HSV value)
# drop below the interpolated ground plate's own value, not a relative
# multiply - see _shadow_color() below: target_value = ground.v - this,
# clamped to [0,1]. An absolute drop holds roughly the same CONTRAST
# regardless of how bright the plate itself is, which is what "read
# consistently on both wet and dry without a per-plate factor" actually
# requires - a relative percentage compresses toward the plate's own
# brightness precisely when the plate is palest, which is the exact case
# that was failing. 0.35: wet plate (value 0.71) lands at 0.36, dry plate
# (ground_color_dry value 0.65) lands at 0.30 - much darker than the old
# model's ~0.50/~0.455 and close enough to each other to read as "the same
# shadow treatment" on both. Never toward black (Bible §7) - this still
# derives from the SAMPLED ground color's own hue/saturation, never an
# independently-authored color that could drift there on its own.
@export_range(0.0, 1.0, 0.01) var contact_shadow_saturation_factor: float = 0.5
# NEW (2026-09-01, color-derivation fix) - the luminance-target model
# takes hue and a REDUCED saturation from the ground color, not its
# saturation unchanged - a shadow reads as a dim, slightly desaturated
# version of what it's cast on, not a full-saturation tinted patch. 0.5:
# eyeballed starting point, same "retune by feel" convention every other
# value here already follows.
@export_range(0.01, 0.5, 0.01) var contact_shadow_footprint_slice_fraction: float = 0.12
# Battle's own copy of RoomState.entity_shadow_footprint_slice_fraction's
# same value (2026-09-01, footprint-measurement fix) - see VisualBounds.
# compute_bottom_slice()'s own doc. Kept as this scene's own export rather
# than reading RoomState directly, for the same reason every other tunable
# here is its own export: battle has no RoomState of its own.
@export var footprint_width_override_px: float = NAN
@export var footprint_center_x_override_px: float = NAN
# Escape hatch for whatever the automatic bottom-slice measurement gets
# wrong for a specific silhouette (2026-09-01) - NAN (default, both) means
# "use the automatic measurement." Left unset for every current entity;
# see EntityShadow.attach()'s own doc on footprint_width_override/
# footprint_center_x_override for when a future one might need this.

var _shadow: Sprite2D = null

# `entity_root` is the entity's own Control (Enemy or PlayerBattleVisual) -
# the shadow attaches as a DIRECT CHILD of it, a sibling of VisualRoot, NOT
# a descendant of VisualRoot (see enemy.gd's own CanvasGroup note: a shadow
# INSIDE that group would be composited into its shared alpha buffer and
# picked up by the rim-highlight shader as part of the creature's own
# silhouette). `measure_root` must satisfy EntityShadow.attach()'s own
# constraint (parent itself or a direct child of it) - both callers pass
# VisualRoot itself, which is a direct child of their own entity_root.
#
# `y_offset_override` lets a caller override contact_shadow_y_offset above
# without touching this shared export (2026-09-01) - NAN (default) means
# "use contact_shadow_y_offset." Player and enemy derive their own baseline
# differently (bounds-bottom of a feet-at-origin silhouette vs. bounds-
# bottom of a centered sprite) - see this pass's own Phase 1 report - so
# this exists for whichever one needs its own correction; neither does
# today, both pass nothing.
func apply_contact_shadow(entity_root: Node, measure_root: Node2D, y_offset_override: float = NAN) -> void:
	if not contact_shadow_enabled:
		return
	var y_offset: float = y_offset_override if not is_nan(y_offset_override) else contact_shadow_y_offset
	var params := {
		"enabled": true,
		# Explicit true, not omitted (2026-09-01) - battle has no RoomState
		# of its own (RoomState is field-scoped), so omitting this would
		# fall through to RoomState.entity_shadow_enabled, a field-only dev
		# toggle with no relationship to battle at all. contact_shadow_
		# enabled above is this scene's own gate; reaching this line already
		# means it's true.
		"color": _shadow_color(),
		"width_ratio": contact_shadow_width_ratio,
		"height_ratio": contact_shadow_height_ratio,
		"footprint_slice_fraction": contact_shadow_footprint_slice_fraction,
		# `show_behind_parent` produces NO visible draw slot at all for a
		# Control living under battle.tscn's UI CanvasLayer (confirmed via
		# live capture, 2026-09-01 rendering-failure investigation - see
		# DESIGN.md's own note) - EntityShadow.attach()'s own doc on this
		# key explains why this is a battle-only override, not a change to
		# the shared default.
		"use_sibling_index_zero": true,
	}
	if not is_nan(footprint_width_override_px):
		params["footprint_width_override"] = footprint_width_override_px
	if not is_nan(footprint_center_x_override_px):
		params["footprint_center_x_override"] = footprint_center_x_override_px
	_shadow = EntityShadow.attach(entity_root, measure_root, y_offset, params)

# The room's interpolated ground tint, re-lit as a shadow via a
# luminance-TARGET, not a percentage-darken - see contact_shadow_
# luminance_drop's own doc above for why (percentage-darkening a pale
# plate doesn't drop far enough to read as an object). RunState.
# current_biome/RoomState.region_progress read directly, not passed in -
# the same two autoload seams battle.gd's own _apply_battle_backdrop()
# already reads for the exact same wet/dry selection, so this always
# agrees with whatever backdrop is actually on screen without any wiring
# between this file and battle.gd.
#
# contact_shadow.png's own peak alpha was measured directly (2026-09-01
# investigation) at 1.0 - not materially below 1.0, so no compensation
# term is needed here; modulate.a alone already reaches full texture
# opacity at the peak of its own soft falloff.
func _shadow_color() -> Color:
	var biome: BiomeData = RunState.current_biome
	var ground: Color = biome.ground_color_wet.lerp(biome.ground_color_dry, RoomState.region_progress)
	var target_value: float = clampf(ground.v - contact_shadow_luminance_drop, 0.0, 1.0)
	var shadow: Color = Color.from_hsv(ground.h, ground.s * contact_shadow_saturation_factor, target_value)
	shadow.a = contact_shadow_alpha
	return shadow

@export_group("Foreground Occluder (placeholder)")
@export var occluder_enabled: bool = false
# OFF by default per this pass's own brief - no real occluder art exists
# yet (see this group's own doc below); shipping this active would put a
# procedural placeholder in front of every entity in every battle, which
# isn't the ask here.
@export_range(1, 8, 1) var occluder_density: int = 3
@export_range(0.0, 200.0, 1.0) var occluder_horizontal_spread_px: float = 60.0
@export var occluder_color: Color = Color(0.16, 0.15, 0.13, 0.8)
# A dark, mostly-opaque neutral - small ground debris (pebbles/reed clumps)
# crossing the base of a silhouette reads as occluding it precisely because
# it's darker/denser than what's behind it, not because of any particular
# hue. Placeholder, same "flat hand-eyeballed color" treatment every other
# procedural placeholder shape in this project already uses (see enemy.gd's
# own FALLBACK_COLOR).

var _occluder: Node2D = null

# Draw order is tree order ONLY (2026-09-01) - no z-index introduced into
# the battle scene for this, per this pass's own brief. Called AFTER
# entity_root's other children (VisualRoot chief among them) already exist,
# and add_child() with no index argument appends to the end of the
# children list - the occluder ends up the LAST child of entity_root,
# drawn last, i.e. in front of everything else entity_root owns. This is
# the entire mechanism; nothing here sets z_index or z_as_relative.
func apply_foreground_occluder(entity_root: Node, baseline: Vector2) -> void:
	if not occluder_enabled:
		return
	_occluder = _build_occluder(baseline)
	entity_root.add_child(_occluder)

# One placeholder shape per occluder_density, small irregular dark blobs
# scattered horizontally across occluder_horizontal_spread_px and centered
# on `baseline` - same "fake a rounded shape with a many-sided polygon"
# technique enemy.gd's own _octagon_points()/_circle_points() already use,
# not a shader or an art asset (per this pass's own brief). A tiny random
# per-blob size/vertical jitter keeps `occluder_density` copies from
# reading as one shape repeated identically.
func _build_occluder(baseline: Vector2) -> Node2D:
	var root := Node2D.new()
	root.position = baseline
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var half_spread := occluder_horizontal_spread_px / 2.0
	for i in occluder_density:
		var blob := Polygon2D.new()
		var radius: float = rng.randf_range(5.0, 9.0)
		blob.polygon = _blob_points(radius)
		blob.color = occluder_color
		var x: float = rng.randf_range(-half_spread, half_spread)
		var y: float = rng.randf_range(-2.0, 2.0)
		blob.position = Vector2(x, y)
		root.add_child(blob)
	return root

func _blob_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	const SEGMENTS := 7
	for i in SEGMENTS:
		var angle := TAU * i / SEGMENTS
		var jittered_radius := radius * randf_range(0.75, 1.0)
		points.append(Vector2(cos(angle), sin(angle) * 0.6) * jittered_radius)
	return points
