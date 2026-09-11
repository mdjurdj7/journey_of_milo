@tool
extends Sprite2D
class_name WagonPlacement
# The forge's own backdrop prop (2026-09-04, forge-wagon pass) - a Track
# B painted plate (see docs/BACKGROUND_ASSET_SPEC_v1.md §11's painted-
# track register), placed as-is: no modulate tint, no palette
# participation, full opacity. A dedicated @tool script rather than
# folding this placement into field_forge.gd itself - that script isn't
# @tool-safe (it references RunState/AudioManager/CardUpgradeService
# autoloads throughout, none of which exist in the editor), so giving
# THIS node its own small, autoload-free script is what makes the three
# knobs below live-preview in the Inspector, no play-mode relaunch loop
# needed, per this pass's own brief.
#
# Sits as a direct SIBLING of FieldForge's own ForgeRoot, ordered BEFORE
# it in field_forge.tscn's own node list (see that file) - Godot's plain
# "later siblings draw over earlier ones" rule is what keeps the wagon
# behind the bench, with no z_index knob at all (an explicit DO NOT in
# this pass's own brief - draw order is structural, not a tuning value).
# Shares ForgeRoot's own local coordinate space exactly - ForgeRoot
# itself carries no position offset of its own (see field_forge.gd's
# _build_geometry() - only its Slab/Support children ever move), so this
# node's local y=0 IS the same floor line the bench's own supports
# already run down to, and local x=0 is the bench's own horizontal
# center.

# Measured directly off Wagon.png's own ALPHA channel (Pillow: im.
# convert("RGBA").split()[3].getbbox()), not a plain getbbox() on the
# composited RGBA image (which can be fooled by fully-transparent pixels
# that still carry non-zero RGB) - NOT the full canvas either, which
# carries a soft, asymmetric generated-image margin outside the actual
# painted content (33px left, 25px top, 50px right, 42px bottom -
# deliberately uneven, so a symmetric assumption would have been wrong).
const TEXTURE_SIZE_PX := Vector2(1536, 1024)
const CONTENT_TOP_LEFT_PX := Vector2(33, 25)
const CONTENT_BOTTOM_RIGHT_PX := Vector2(1486, 982)
# Content box: 1453x957 - the wagon's own real painted bounds.

# Target height chosen against two existing precedents rather than
# picked freehand: field_structure.gd's own "~1.5x player height" for a
# true LANDMARK (the Pay House) sets the ceiling this must stay well
# under; the Wanderer's own full standing height (~344px - Sprite2D
# scale 8 * 256px frame, offset -97.5, Visual's own 0.2 scale and +17
# root offset - see player_visual.tscn, and field_chest.gd's _spawn_
# gold_number() for the identical derivation spelled out in full) sets
# the floor. 420px lands at ~1.2x player height: taller than the
# Wanderer at the body, comfortably under the ~516px (1.5x) landmark
# threshold - this frames the workstation without upstaging it or the
# room itself.
const TARGET_CONTENT_HEIGHT_PX := 420.0

@export var wagon_scale: float = 1.0:
	# Uniform multiplier ON TOP OF the content-bounds-derived base scale
	# above - 1.0 means "exactly the derived base," a pure nudge from
	# there, never a replacement for the derivation.
	set(value):
		wagon_scale = value
		_apply_placement()

@export var wagon_offset: Vector2 = Vector2.ZERO:
	# Added AFTER the computed floor-line/rear-quarter placement below -
	# (0, 0) means "exactly the derived position," a pure nudge from
	# there.
	set(value):
		wagon_offset = value
		_apply_placement()

@export var wagon_flip_h: bool = true:
	# true is the derived default (2026-09-04 finding): the source art's
	# empty shafts/harness point toward native image-LEFT, but this
	# room's inland direction (the exit door at _room_floor_right_x(),
	# the tower silhouette's own 0.72 screen-x fraction - both in
	# field_room.gd) is toward +X/right, so the art needs a horizontal
	# flip to face inland. Not a look-and-feel knob to nudge by eye -
	# only change this if the inland reading itself turns out wrong.
	set(value):
		wagon_flip_h = value
		_apply_placement()

func _ready() -> void:
	centered = false
	_apply_placement()

# Content-bounds-derived placement (2026-09-04) - see this script's own
# header for the full reasoning. Re-run from every exported setter above
# AND from _ready() (scene load, including in-editor), so the Inspector
# always shows the live, current placement - no play-mode relaunch
# needed to see a knob change take effect.
func _apply_placement() -> void:
	var content_height: float = CONTENT_BOTTOM_RIGHT_PX.y - CONTENT_TOP_LEFT_PX.y
	var base_scale: float = TARGET_CONTENT_HEIGHT_PX / content_height
	var s: float = base_scale * wagon_scale
	scale = Vector2(s, s)
	flip_h = wagon_flip_h

	# flip_h mirrors the SOURCE CONTENT within a fixed texture rect
	# (Sprite2D.position/centered=false still anchor that rect's own
	# top-left corner) rather than moving the rect itself - so the
	# rect's native LEFT margin (33px) becomes the RENDERED right margin
	# once flipped, and the native RIGHT margin (50px) becomes the
	# rendered left margin. This picks whichever margin actually ends up
	# on the rendered-left side, post-flip, so the wagon's rear (post-
	# flip-left) edge lands at this node's own local x=0 - the bench's
	# horizontal center - regardless of wagon_flip_h's own value. That's
	# what makes the bench's own right support/slab lap over the wagon's
	# rear quarter (see field_forge.tscn's own node order for why that
	# reads as "in front of," not just "overlapping").
	var rendered_left_margin: float = (TEXTURE_SIZE_PX.x - CONTENT_BOTTOM_RIGHT_PX.x) if flip_h else CONTENT_TOP_LEFT_PX.x
	var rect_x: float = -rendered_left_margin * s
	# Bottom edge (unaffected by flip_h - only the X axis mirrors) at
	# this node's own local y=0, the shared floor line.
	var rect_y: float = -CONTENT_BOTTOM_RIGHT_PX.y * s

	position = Vector2(rect_x, rect_y) + wagon_offset
