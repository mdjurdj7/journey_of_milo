extends Camera2D
class_name FieldCamera
# Shifts the camera ahead of the player in whatever direction they're
# facing - "looking ahead" down the room instead of staying dead-centered
# on the player. Reads its parent CharacterBody2D's velocity directly,
# the same self-contained "watch velocity, react on its own" pattern
# player_visual.gd already uses for facing - this script doesn't need to
# know anything about PlayerVisual, and vice versa.
#
# The offset is just this Camera2D's own local `position` (relative to
# Player, its parent) - Camera2D's built-in limit_left/limit_right/
# limit_top/limit_bottom (already set on this node in field_room.tscn)
# clamp the actual rendered view to the room's true edges automatically,
# so nudging `position` here can never reveal space past a wall; no
# extra clamping math needed in this script.

@export var facing_offset_px: float = 220.0
@export var offset_smoothing: float = 8.0
# Higher = the camera catches up to the new offset faster after a facing
# change. This is a rate for exponential smoothing, not a duration.

@export var anchor_fraction: float = 0.33
# The player's target horizontal position as a fraction of viewport width,
# measured from the left - only used when flip_with_facing is false (see
# below). 0.5 would center the player; 0.33 sits them a third of the way
# in from the left edge, "looking ahead" down the room without the offset
# ever reversing when the player turns around (2026-09-01, field
# composition pass).

@export var flip_with_facing: bool = false
# False (default, 2026-09-01 composition pass): target offset is a FIXED
# screen position (anchor_fraction) regardless of which way the player is
# walking - _facing below is tracked but not read. True: the original
# facing_offset_px * _facing look-ahead, which reverses side every time
# the player turns.

const FACING_DEADZONE := 1.0 # px/sec of horizontal velocity below which facing doesn't update.

var _parent_body: CharacterBody2D
var _facing: float = 1.0 # 1 = facing right, -1 = facing left. Holds while idle, like player_visual.gd's own _facing.

var follow_enabled: bool = true
# Set false by field_room.gd for a single-screen room exactly one
# viewport wide - COMBAT (2026-08-29, single-screen pass), joined by
# TREASURE (2026-08-31, treasure-overhang pass) - see that file's own
# _is_single_screen_room() - with nothing left to scroll, Camera2D's own
# limit_left/limit_right clamping WOULD probably still pin the rendered
# view to a single stable position even with this left running (there's
# only one valid unclamped position when the limits are exactly viewport-
# wide apart) - but that's relying on the clamp to hide a value that's
# still drifting underneath it by accident, exactly what this pass was
# told explicitly to avoid. False makes the camera genuinely inert
# instead: _process() below returns before ever touching `position`, so
# it stays at whatever it already was the instant this got set (Vector2.
# ZERO, since field_room.gd sets this before this camera's first
# _process() tick ever runs - see _position_room_bounds()) for the rest
# of the room's lifetime. A plain instance var, not @export - this is a
# runtime mode field_room.gd sets per room, not a per-scene tunable.

func _ready() -> void:
	_parent_body = get_parent() as CharacterBody2D
	zoom = Vector2(RoomState.field_zoom, RoomState.field_zoom)
	# Read from RoomState, not a local @export, so the same value also
	# reaches RoomState.combat_room_width()'s width math - see that
	# function's own doc for why the tunable has to live there instead of
	# here (this scene doesn't exist yet when that math runs).

func _process(delta: float) -> void:
	if not follow_enabled:
		return
	if _parent_body:
		var vx := _parent_body.velocity.x
		if absf(vx) > FACING_DEADZONE:
			_facing = 1.0 if vx > 0.0 else -1.0

	var target_offset: Vector2
	if flip_with_facing:
		target_offset = Vector2(facing_offset_px * _facing, 0.0)
	else:
		var viewport_width: float = get_viewport().get_visible_rect().size.x
		target_offset = Vector2((0.5 - anchor_fraction) * viewport_width, 0.0)
	# Frame-rate-independent exponential smoothing toward the target
	# offset, so the re-center speed doesn't change with the game's frame
	# rate - the same "lerp toward a target, not snap to it" idea as any
	# other tween, just done by hand each frame instead of a Tween node.
	var weight := 1.0 - exp(-offset_smoothing * delta)
	position = position.lerp(target_offset, weight)
