extends StaticBody2D
class_name FieldWall
# A room boundary wall - four instances (top/bottom/left/right), same
# script, each told which edge it is via a few exports rather than
# hand-authoring its own polygon points in field_room.tscn - matches
# enemy.gd/vitals_bar.gd's "compute layout from exports" convention
# instead of baking numbers into the scene file.
#
# Renders as a real wall with thickness and depth, not a hairline flush
# against the screen edge: a void margin between the room's true outer
# boundary and the wall's own outward face, the wall body itself, and a
# thin inner-edge shade strip that reads as a baseboard shadow - the
# cheapest "this has depth" cue available without actual shading.
#
# Collision is UNCHANGED by any of this - CollisionShape2D (see field_
# room.tscn) still spans exactly the same fixed footprint it always did,
# regardless of how the visual geometry below is drawn on top of/around
# it. This whole script only ever touches WallBody/DepthShade, two plain
# Polygon2D children with no collision role - the player is blocked in
# exactly the same places as before.

@export var is_horizontal: bool = true
# True for a top/bottom wall (thickness runs along Y, length along X),
# false for a left/right wall (thickness along X, length along Y).
@export var outward_sign: float = -1.0
# Which local direction points toward the room's TRUE outer edge, away
# from the floor: -1 for the top/left walls, +1 for bottom/right - see
# field_room.tscn for each instance's value.
@export var half_length: float = 1150.0
# Half this wall's length along its own run - 1150 (half the room's
# 2300 width) for top/bottom, 540 (half the 1080 height) for left/right.
@export var collision_half_thickness: float = 20.0
# Half of CollisionShape2D's own fixed thickness (40px total, unchanged
# by this script) - used only to locate the true outer edge and the
# floor line so the visual geometry below can be placed relative to
# them; never used to size anything collidable.

@export var wall_thickness_px: float = 44.0
@export var void_margin_px: float = 8.0
# Gap between the room's true outer edge and the wall's own outward
# face. Without this the wall reads as flush with the screen edge -
# easily mistaken for UI chrome instead of a physical boundary. Default
# thickness+margin (52) slightly exceeds the fixed 40px collision depth
# on purpose - the wall body overlaps a few px onto the floor rather
# than stopping short of it, so it reads as grounded, not floating.
@export var wall_color: Color = Color(0.35, 0.35, 0.4, 1)
# Set directly by field_room.gd's _apply_wall_tint() after this node's
# own _ready() - see set_wall_color() below. This default is just what
# a wall looks like if nothing else ever touches it.
@export var depth_shade_color: Color = Color(0, 0, 0, 0.35)
@export var depth_shade_width_px: float = 6.0
# A thin darker strip along the wall's INNER face (the one facing the
# floor), independent of wall_color/room-type tint - a shadow cue, not
# a room-type signal, so it stays the same regardless of which room
# this is.

@export_group("Depth shade pulse")
# Optional slow breathing on the depth-shade strip - off by default, so
# every existing wall's static shadow strip is completely unaffected.
# Built for field_room.gd's opening-room ocean, where the strip is
# repurposed as a foam band at the shore line (see set_depth_shade())
# and benefits from a little ambient life - but nothing here assumes
# "foam" specifically, it just breathes the strip's own alpha AND
# position, the exact same slow sine-driven technique enemy_visual.gd's
# idle bob already uses (see its own _process()), so any other wall
# could opt into the same subtle life later without a second
# implementation.
@export var depth_shade_pulse_enabled: bool = false
@export var depth_shade_pulse_period_sec: float = 4.0
@export var depth_shade_pulse_alpha_amount: float = 0.2
# How far modulate.a swings above/below 1.0 - NOT the strip's own base
# alpha (that's still entirely owned by depth_shade_color/set_depth_
# shade()). Small on purpose: this should read as gentle background
# breathing, never a flashing or obviously-mechanical loop - see
# DESIGN.md's note on why the opening room's ocean uses this.
@export var depth_shade_pulse_shift_px: float = 12.0
# How far the strip creeps INWARD (toward the floor, the same direction
# _rebuild_geometry() already calls "inward") and back each cycle, along
# whichever axis is this wall's own depth axis (X for a vertical wall,
# Y for a horizontal one - see is_horizontal). Alpha alone only fades a
# fixed shape in place, which doesn't read as "water" so much as "a
# strip flickering" - shifting position too is what actually sells
# motion TOWARD the shore, not just brightness changing. In phase with
# the alpha swing on purpose (brightest exactly when it's advanced
# furthest) rather than a second, offset wave - one simple cue reads as
# a wave washing in and receding; two independent waves would just read
# as busier, not more like water.

var _pulse_time: float = 0.0

@onready var wall_body: Polygon2D = $Polygon2D
@onready var depth_shade: Polygon2D = $DepthShade
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	wall_body.color = wall_color
	depth_shade.color = depth_shade_color
	_rebuild_geometry()

func _process(delta: float) -> void:
	if not depth_shade_pulse_enabled:
		return
	_pulse_time += delta
	var wave := sin(_pulse_time * TAU / depth_shade_pulse_period_sec)
	depth_shade.modulate.a = 1.0 + wave * depth_shade_pulse_alpha_amount
	# -outward_sign: "inward" (toward the floor), the same direction
	# _rebuild_geometry() already uses that name for. depth_shade keeps
	# its own polygon shape untouched (only ever rebuilt by _rebuild_
	# geometry() itself) - this just nudges the whole shape back and
	# forth via the node's own position, cheap and independent of the
	# polygon math above.
	var shift := wave * depth_shade_pulse_shift_px * -outward_sign
	depth_shade.position = Vector2(0, shift) if is_horizontal else Vector2(shift, 0)

# field_room.gd's _apply_wall_tint() calls this instead of setting
# Polygon2D.color directly (which is what it did before this rebuild) -
# the color still just lands on wall_body, so boss/elite/normal tinting
# keeps working exactly as it already did, unaffected by any of the
# geometry changes above.
func set_wall_color(color: Color) -> void:
	wall_color = color
	wall_body.color = color

# Hides/shows this wall's VISUAL only (wall_body + depth_shade) - never
# touches collision_shape, so the player is still blocked in exactly the
# same place regardless (see DESIGN.md's Run Structure & Navigation:
# room framing removal). field_room.gd calls this false on LeftWall/
# RightWall by default - a plain colored slab reads as a UI frame around
# the playfield, not architecture, in the side-scrolling layout; room
# edges should be defined by biome content (structures thinning out,
# terrain, water) instead. A room that DOES have real edge content (the
# opening room's ocean/void on LeftWall) calls this true again after
# configuring that content, since a real feature is exactly what a
# rendered border should have been standing in for.
func set_visual_enabled(enabled: bool) -> void:
	wall_body.visible = enabled
	depth_shade.visible = enabled

# The depth-shade strip's color/width were previously fixed (a shadow
# cue, deliberately independent of room-type tint - see its own export
# comment) - a room that wants to repurpose the SAME strip for a
# different cue (see field_room.gd's opening-room ocean styling, which
# turns this into a foam band at the shore line) needs a way to change
# both without touching wall_color/set_wall_color() at all, since a
# foam band and a room-type tint are two independent things layered on
# the same wall.
func set_depth_shade(color: Color, width_px: float) -> void:
	depth_shade_color = color
	depth_shade_width_px = width_px
	depth_shade.color = color
	_rebuild_geometry()

# Lets a caller resize/rethicken this wall's actual footprint - both
# collision AND visual - after the scene has already loaded. Built for
# field_room.gd's opening-room layout override (see its own comment):
# the first room whose bounds and per-edge styling differ from the
# fixed size baked into field_room.tscn, prepended ahead of the normal
# generated graph (see DESIGN.md's Run Structure & Navigation). Always
# duplicates the CollisionShape2D's shape resource before mutating it -
# collision_shape.shape starts out SHARED between this wall and its
# opposite edge (see field_room.tscn's two RectangleShape2D sub-
# resources, one shared by top+bottom, one by left+right), so resizing
# it in place without duplicating first would silently resize both at
# once, the same "duplicate before mutating a shared resource"
# precaution vitals_bar.gd's own fill stylebox already takes.
func configure(new_half_length: float, new_collision_half_thickness: float, new_wall_thickness_px: float, new_void_margin_px: float) -> void:
	half_length = new_half_length
	collision_half_thickness = new_collision_half_thickness
	wall_thickness_px = new_wall_thickness_px
	void_margin_px = new_void_margin_px
	var shape: RectangleShape2D = (collision_shape.shape as RectangleShape2D).duplicate()
	if is_horizontal:
		shape.size = Vector2(half_length * 2.0, collision_half_thickness * 2.0)
	else:
		shape.size = Vector2(collision_half_thickness * 2.0, half_length * 2.0)
	collision_shape.shape = shape
	_rebuild_geometry()

func _rebuild_geometry() -> void:
	var outward_edge := outward_sign * (collision_half_thickness - void_margin_px)
	var inward_edge := outward_edge - outward_sign * wall_thickness_px
	var shade_outer := inward_edge + outward_sign * depth_shade_width_px

	wall_body.polygon = _rect_points(outward_edge, inward_edge)
	depth_shade.polygon = _rect_points(shade_outer, inward_edge)

# Builds a rectangle spanning the full run (half_length either side of
# center) and the given depth range - shared by the wall body and the
# depth-shade strip so there's one definition of "a slab along this
# wall's run," not two copies that could drift apart.
func _rect_points(depth_a: float, depth_b: float) -> PackedVector2Array:
	var lo: float = min(depth_a, depth_b)
	var hi: float = max(depth_a, depth_b)
	if is_horizontal:
		return PackedVector2Array([
			Vector2(-half_length, lo), Vector2(half_length, lo),
			Vector2(half_length, hi), Vector2(-half_length, hi),
		])
	return PackedVector2Array([
		Vector2(lo, -half_length), Vector2(lo, half_length),
		Vector2(hi, half_length), Vector2(hi, -half_length),
	])
