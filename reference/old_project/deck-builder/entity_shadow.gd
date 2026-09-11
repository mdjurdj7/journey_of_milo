class_name EntityShadow
extends RefCounted
# The ONE deliberate exception to this project's "duplicate a proven
# shape, don't extract a shared helper" convention (see field_heap.gd's
# own header, field_chest.gd's own prompt-machinery doc for that
# convention stated directly) - scoped to exactly one thing: attaching a
# contact shadow. Every entity type still builds its OWN visuals its own
# way, unchanged; this only adds one more child once that visual exists,
# using the same measurement (VisualBounds.compute()) already shared for
# foot-anchoring (field_blob.gd's _build_member_visual()) and hitbox
# sizing (field_blob.gd's _resize_triggers()) - a shadow needs that exact
# same "real rendered bounds" fact regardless of which entity or which of
# this project's several different origin conventions (base-anchored,
# centre-anchored, or the player's collision-box-centre) it's placed on,
# so reusing it here is the same kind of sharing already established, not
# a new kind.

const SHADOW_TEXTURE: Texture2D = preload("res://assets/all entities/contact_shadow.png")
# 512x192, soft white ellipse fading to zero alpha at the edges - white,
# not black, so `modulate` below can tint it (multiply) down to entity_
# shadow_color's dim value; a black mask could never be tinted brighter,
# same reasoning every other tintable mask asset in this project already
# follows (see field_room.gd's vegetation_clump_textures own doc for the
# same rule stated there).

# Measures `measure_root`'s real rendered bounds and adds one shadow
# Sprite2D as a child of `parent`, sized off the measured width and
# centered at the measured BOTTOM edge - one mechanism that works
# regardless of whether `measure_root`'s own origin convention is base-
# anchored, centre-anchored, or something else, since none of that
# matters once the real bounds are known directly (see room_state.gd's
# entity_shadow_enabled/_color/_width_ratio/_height_ratio doc for the
# tunables read below).
#
# `measure_root` must be either `parent` itself or a DIRECT child of
# `parent` - VisualBounds.compute(measure_root) returns bounds in
# measure_root's OWN local space; when measure_root isn't parent, this
# multiplies by measure_root.transform to land those bounds in measure_
# root's PARENT's space (exactly what VisualBounds' own recursion does
# one level up - see its own _bounds_in_parent_space()), which is only
# correct if that parent IS `parent`. Every call site in this project
# today satisfies this (VisualRoot/ChestRoot/visual_root are always
# direct children of the Area2D/CharacterBody2D they shadow, or the
# entity IS its own measure_root - see field_marker.gd's own call).
#
# `parent` is typed `Node`, not `Node2D` (2026-09-01, battle grounding
# pass) - every field call site still passes a Node2D subtype (Area2D/
# CharacterBody2D), so this is a pure widening, not a behavior change for
# them. Battle's own entities (Enemy, PlayerBattleVisual) are `Control`,
# a CanvasItem sibling of Node2D in Godot's own class tree, not a Node2D
# subtype - `parent` is only ever used here for `add_child()` (a plain
# Node method) and an identity check against `measure_root`, neither of
# which needs anything Node2D-specific, so the stricter type was never
# load-bearing.
#
# show_behind_parent = true (2026-08-30) - the FIRST use of this
# CanvasItem property anywhere in this project (confirmed via a project-
# wide search before this pass) - draws the shadow behind `parent`
# regardless of sibling order, without needing a negative z_index or any
# change to how `parent` itself is drawn or ordered among ITS OWN
# siblings.
#
# `y_offset_override` lets ONE entity type replace RoomState.entity_
# shadow_y_offset's own global default with its own value (2026-08-30,
# shadow-tuning pass) - NAN (the default) means "no override, use the
# global one." Explicit 0.0 is a real, meaningful override (not treated
# as "unset") - several callers genuinely want zero lift: see each call
# site's own doc for why. Callers with a real per-entity value pass their
# own @export (npc/chest/curio/heap/marker each carry their own
# shadow_y_offset; field_room.gd carries player_shadow_y_offset for the
# player, since neither player.gd nor player_visual.gd otherwise touches
# shadow concerns at all).
#
# `params`, added for battle (2026-09-01, battle grounding pass) - the
# FIRST caller outside the field room, which has no RoomState of its own
# (RoomState is field-scoped; see its own header) and so no ambient
# "enabled/color/width_ratio/height_ratio" to fall back on the way every
# field consumer implicitly does. A plain Dictionary, not a typed params
# class: only the keys a caller actually wants to override need appear in
# it ("color" alone, say), everything else still falls through to
# RoomState below untouched - a typed class would force every field to a
# real value (or a null-per-field convention, one per type), where a dict
# lookup with a default already gives that for free. Every field-room call
# site today passes nothing (defaulting to {}), so `params.get(key,
# RoomState.xxx)` always resolves to exactly RoomState.xxx for them - this
# is a strict superset of the old behavior, not a parallel path.
#
# y_offset can still arrive via the existing y_offset_override parameter
# OR via params["y_offset"] - y_offset_override wins if it's a real number
# (not NAN), since every existing field call site already spells its
# override that way and this must not change under them. A caller with no
# per-entity y_offset_override of its own (battle, so far) can bundle
# y_offset into params alongside the other four instead.
#
# Width and centre-x come from VisualBounds.compute_bottom_slice(), NOT the
# full compute() bounds (2026-09-01, footprint-measurement fix) - the FULL
# silhouette extent includes anything a raised weapon arm or a flared cape
# reaches, which never touches the ground and shouldn't set the shadow's
# width or where it's centred (see this pass's own investigation report,
# most visible on the Wanderer's own padded sprite canvas, but this applies
# uniformly - every field consumer already shares params.get("footprint_
# slice_fraction", RoomState...) the same way it shares every other
# tunable here). The vertical placement below ALSO reads slice_bounds now,
# not the full bounds (2026-09-01, anchor-gap fix - see that pass's own
# note further down) - the full bounds' own bottom edge turned out not to
# be a stable "ground contact" reference either, for the same padded-
# canvas reason its width wasn't.
#
# `footprint_width_override`/`footprint_center_x_override` are an escape
# hatch for whatever the automatic slice measurement gets wrong for a
# specific entity - NOT the default path (no current entity sets either;
# see room_state.gd's own entity_shadow_footprint_slice_fraction doc and
# this pass's own brief). Both, like every other params key, fall through
# to the slice measurement when absent.
#
# `use_sibling_index_zero` (2026-09-01, battle-rendering-failure fix) -
# show_behind_parent produces NO visible draw slot at all (confirmed via
# live capture, not property reads) when `parent` is a Control living
# under a CanvasLayer, which every battle entity (Enemy, PlayerBattleVisual,
# both under battle.tscn's UI CanvasLayer) is - see DESIGN.md's own note on
# this for what's actually confirmed about the trigger. Default false:
# every field consumer keeps the exact `show_behind_parent = true` behavior
# it already has, unchanged. When true, this does `parent.add_child(shadow)
# ; parent.move_child(shadow, 0)` INSTEAD of setting show_behind_parent -
# NOT the same mechanism, deliberately not unified: index 0 draws behind
# EVERY other sibling `parent` has, where show_behind_parent draws behind
# only `parent`'s OWN drawing regardless of sibling order. They happen to
# produce the same visible result for today's field entities only because
# none of them have a sibling of the shadow that draws BEFORE the shadow
# would otherwise land (index 0 is always the very first child) - a future
# field entity that ever needs a shadow appearing behind some but not all
# of its siblings would need this same param, not a silent behavior change
# here. Battle passes true because it has to; nothing else should set it
# without an equally confirmed reason.
#
# Returns null (adds nothing) if the resolved `enabled` is off, or if
# measure_root has no measurable children (VisualBounds.compute() found
# nothing to bound) - see this pass's own report on which entities that
# was actually reachable for.
static func attach(parent: Node, measure_root: Node2D, y_offset_override: float = NAN, params: Dictionary = {}) -> Sprite2D:
	var enabled: bool = params.get("enabled", RoomState.entity_shadow_enabled)
	if not enabled:
		return null
	var local_bounds: Rect2 = VisualBounds.compute(measure_root)
	if local_bounds.size == Vector2.ZERO and local_bounds.position == Vector2.ZERO:
		return null

	var slice_fraction: float = params.get("footprint_slice_fraction", RoomState.entity_shadow_footprint_slice_fraction)
	var local_slice: Rect2 = VisualBounds.compute_bottom_slice(measure_root, slice_fraction)
	var slice_bounds: Rect2 = local_slice if measure_root == parent else measure_root.transform * local_slice

	var width_ratio: float = params.get("width_ratio", RoomState.entity_shadow_width_ratio)
	var footprint_width: float = params.get("footprint_width_override", slice_bounds.size.x)
	var width: float = footprint_width * width_ratio
	if width <= 0.0:
		return null
	var height_ratio: float = params.get("height_ratio", RoomState.entity_shadow_height_ratio)
	var height: float = width * height_ratio
	var color: Color = params.get("color", RoomState.entity_shadow_color)
	var default_y_offset: float = params.get("y_offset", RoomState.entity_shadow_y_offset)
	var y_offset: float = y_offset_override if not is_nan(y_offset_override) else default_y_offset
	var center_x: float = params.get("footprint_center_x_override", slice_bounds.get_center().x)

	var shadow := Sprite2D.new()
	shadow.texture = SHADOW_TEXTURE
	var use_sibling_index_zero: bool = params.get("use_sibling_index_zero", false)
	if not use_sibling_index_zero:
		shadow.show_behind_parent = true
	shadow.modulate = color
	var native_size := SHADOW_TEXTURE.get_size()
	shadow.scale = Vector2(width / native_size.x, height / native_size.y)
	# Centered on the footprint's own measured span (center_x, not
	# necessarily local x=0 - see slice_bounds above), vertically at the
	# SLICE bounds' own measured bottom edge PLUS y_offset - NOT the full
	# bounds' bottom (2026-09-01, anchor-gap fix). The full bounds' bottom
	# is compute()'s padded CANVAS edge for a Sprite2D, which sits below
	# the real opaque pixels whenever the source art has transparent
	# padding at its bottom (confirmed directly: wanderer_battle.png has
	# 42px of it) - anchoring there put the shadow a real, measured gap
	# below the actual rendered feet, not merely "not tight enough."
	# slice_bounds' own bottom is the real scanned max-Y among the alpha-
	# scanned/vertex points VisualBounds.compute_bottom_slice() already
	# collects - see that function's own doc for why this is safe for
	# every existing caller (nothing previously read this rect's Y). For a
	# Polygon2D-based enemy this is unchanged from before, since Polygon2D
	# bounds are already exact vertex data with no possible padding.
	# y_offset then corrects that raw measurement further if a specific
	# entity's own art still needs it - see RoomState.entity_shadow_y_
	# offset's own doc. No horizontal offset beyond center_x itself, per
	# this pass's own brief: the region's light is diffuse overcast (Art
	# Direction Bible §6), so a directly-overhead shadow is correct without
	# needing to agree with sky_light_direction the way an offset shadow
	# would.
	shadow.position = Vector2(center_x, slice_bounds.position.y + slice_bounds.size.y + y_offset)
	parent.add_child(shadow)
	if use_sibling_index_zero:
		parent.move_child(shadow, 0)
	return shadow
