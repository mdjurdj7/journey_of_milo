extends Node
class_name BattleGroundPress

# The battle frame's terrain rule: the near foreground - sand between the
# camera and the fighters - never rises above the fighters' feet line, so
# the frame's bottom edge always shows open ground. While the frame is up
# (CameraRig.is_battle_framing()), Ground presses every vertex nearer the
# camera than the nearest fighter's feet by more than clear_m down toward
# the feet line (Ground.set_battle_press()): fully from ramp_m nearer
# still, easing to nothing at clear_m, never below the sea by less than
# min_over_sea_m. Only what is drawn moves - the walk surface, the feet
# and every height query stay as they are; a prop or scatter item left
# standing on pressed sand fades instead of floating (BattleOcclusion,
# FieldScatter.occludes_battle()).
#
# The press eases in with the camera's swing and out with it
# (smoothstepped over battle_transition_time), its frame - the battle
# eye, the direction to the feet, the feet line - read while the frame is
# up and held while it eases out.
#
# A child of RegionField, made at its _ready(); PROCESS_MODE_ALWAYS.

# Sand this far nearer the camera than the nearest fighter's feet, and
# beyond, is left as it is, metres.
@export var clear_m: float = 1.2
# Over this much nearer again the press reaches full, metres.
@export var ramp_m: float = 2.0
# The level pressed to, over the lowest feet, metres.
@export var level_offset_m: float = 0.0
# Never pressed lower than this over the sea, metres.
@export var min_over_sea_m: float = 0.03

var _field: RegionField = null
# The swing's progress, 0..1, before the smoothstep.
var _progress: float = 0.0
var _eye_xz: Vector2 = Vector2.ZERO
var _forward_xz: Vector2 = Vector2(0.0, -1.0)
var _full_depth: float = 0.0
var _zero_depth: float = 0.0
var _level: float = 0.0
var _pushed: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_field = get_parent() as RegionField

func _process(delta: float) -> void:
	if _field == null:
		return
	var ground := _field.get_node_or_null(_field.ground_path) as Ground
	var rig := _field.get_node_or_null(_field.camera_rig_path) as CameraRig
	if ground == null:
		return
	var framing: bool = rig != null and rig.is_battle_framing() and _field.is_battle_open()
	if framing:
		_read_frame(rig, ground)
	var seconds: float = rig.battle_transition_time if rig != null else 0.6
	_progress = move_toward(_progress, 1.0 if framing else 0.0, delta / maxf(seconds, 1.0e-3))
	var amount: float = smoothstep(0.0, 1.0, _progress)
	if amount <= 0.0 and not _pushed:
		return
	ground.set_battle_press(amount, _eye_xz, _forward_xz, _full_depth, _zero_depth, _level)
	_pushed = amount > 0.0

# Whether the press has finished easing - fully in or fully out.
func is_settled() -> bool:
	return _progress <= 0.0 or _progress >= 1.0

# The press's frame from the battle camera and the feet it frames.
func _read_frame(rig: CameraRig, ground: Ground) -> void:
	var feet: PackedVector3Array = rig.get_battle_feet()
	if feet.is_empty():
		return
	var eye: Vector3 = rig.get_battle_eye()
	var centre := Vector2.ZERO
	var lowest: float = INF
	for foot in feet:
		centre += Vector2(foot.x, foot.z)
		lowest = minf(lowest, foot.y)
	centre /= float(feet.size())
	var eye_xz := Vector2(eye.x, eye.z)
	var forward: Vector2 = centre - eye_xz
	if forward.length() < 1.0e-3:
		return
	forward = forward.normalized()
	var nearest: float = INF
	for foot in feet:
		nearest = minf(nearest, (Vector2(foot.x, foot.z) - eye_xz).dot(forward))
	_eye_xz = eye_xz
	_forward_xz = forward
	_zero_depth = nearest - clear_m
	_full_depth = _zero_depth - ramp_m
	var sea := _field.get_node_or_null(_field.sea_path) as Sea
	var floor_level: float = (sea.sea_level if sea != null else -INF) + min_over_sea_m
	_level = maxf(lowest + level_offset_m, floor_level)
