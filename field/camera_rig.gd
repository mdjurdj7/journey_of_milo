extends Node3D
class_name CameraRig

@export var target_path: NodePath = ^"../Wanderer"
@export var distance: float = 9.0
@export var pitch_degrees: float = 18.0
@export var look_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var framing_bias: float = 0.3
@export var follow_smoothing: float = 6.0
@export var max_follow_speed: float = 10.0
@export var fov: float = 40.0:
	set(value):
		fov = value
		if is_instance_valid(camera):
			camera.fov = fov

# Battle framing: side-on, perpendicular to the a->b line, on whichever
# side keeps the Wanderer screen-left. Blended in/out of the follow
# framing above over battle_transition_time, both ways.
@export var battle_pitch: float = 18.0
@export var battle_distance: float = 9.0
@export var battle_fov: float = 35.0
@export var battle_framing_bias: float = 0.0
@export var battle_transition_time: float = 0.6

var _target: Node3D

var _battle_a: Node3D
var _battle_b: Node3D
# Last valid battle look target/axis, kept for the exit transition in case
# a or b (e.g. a defeated enemy) is freed while blending back out.
var _battle_last_target: Vector3
var _battle_last_forward: Vector3 = Vector3.FORWARD

# 0 = pure follow framing, 1 = pure battle framing. Animated by
# _advance_battle_blend() from _blend_from to _blend_to over
# battle_transition_time, eased rather than linear.
var _battle_blend: float = 0.0
var _blend_from: float = 0.0
var _blend_to: float = 0.0
var _blend_elapsed: float = 0.0

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	camera.fov = fov
	if _target:
		global_position = _target.global_position
		_place_camera()

# Called by region_field.gd on enemy contact, before the battle stub shows.
func enter_battle(a: Node3D, b: Node3D) -> void:
	_battle_a = a
	_battle_b = b
	_start_blend(1.0)

# Called by region_field.gd once the battle stub resolves. Follow mode
# resumes as the blend eases back to 0.
func exit_battle() -> void:
	_start_blend(0.0)

func _start_blend(target: float) -> void:
	_blend_from = _battle_blend
	_blend_to = target
	_blend_elapsed = 0.0

func _advance_battle_blend(delta: float) -> void:
	_blend_elapsed = minf(_blend_elapsed + delta, battle_transition_time)
	var t := 1.0 if battle_transition_time <= 0.0 else _blend_elapsed / battle_transition_time
	_battle_blend = lerpf(_blend_from, _blend_to, smoothstep(0.0, 1.0, t))

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	_advance_battle_blend(delta)

	var smoothed: Vector3 = global_position.lerp(_target.global_position, 1.0 - exp(-follow_smoothing * delta))
	var motion := smoothed - global_position

	# Below max_follow_speed this is identical to the plain lerp. Above it
	# (a dash burst) the step is clamped so the target visibly leads the
	# frame instead of the camera snapping to keep up.
	var max_step := max_follow_speed * delta
	if motion.length() > max_step:
		motion = motion.normalized() * max_step

	global_position += motion

	_place_camera()

# The rig never rotates, so this is a fixed world direction — the follow
# framing's viewing axis.
func _rig_ground_forward() -> Vector3:
	var forward := -global_transform.basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()

# Perpendicular to the a->b line, on the side that puts a screen-left:
# right = ground_forward x UP, and UP x axis is exactly the ground_forward
# choice that makes (a - midpoint), which points opposite axis, fall on
# the negative (left) side of that right vector.
func _battle_ground_forward(a_pos: Vector3, b_pos: Vector3) -> Vector3:
	var axis := Vector3(b_pos.x - a_pos.x, 0.0, b_pos.z - a_pos.z)
	if axis.length() < 0.0001:
		return _rig_ground_forward()
	return Vector3.UP.cross(axis).normalized()

func _place_camera() -> void:
	var follow_target := _target.global_position + look_offset
	var follow_forward := _rig_ground_forward()

	var battle_target := _battle_last_target
	var battle_forward := _battle_last_forward
	if is_instance_valid(_battle_a) and is_instance_valid(_battle_b):
		battle_target = (_battle_a.global_position + _battle_b.global_position) * 0.5 + look_offset
		battle_forward = _battle_ground_forward(_battle_a.global_position, _battle_b.global_position)
		_battle_last_target = battle_target
		_battle_last_forward = battle_forward

	var look_target: Vector3 = follow_target.lerp(battle_target, _battle_blend)
	var ground_forward: Vector3 = follow_forward.lerp(battle_forward, _battle_blend)
	ground_forward = follow_forward if ground_forward.length() < 0.0001 else ground_forward.normalized()

	var eff_pitch: float = lerpf(pitch_degrees, battle_pitch, _battle_blend)
	var eff_distance: float = lerpf(distance, battle_distance, _battle_blend)
	var eff_fov: float = lerpf(fov, battle_fov, _battle_blend)
	var eff_framing_bias: float = lerpf(framing_bias, battle_framing_bias, _battle_blend)
	var pitch_rad := deg_to_rad(eff_pitch)

	# Sphere of radius `eff_distance` around the look target: pitch swings
	# the camera between ground level (0) and directly overhead (90).
	camera.global_position = look_target - ground_forward * eff_distance * cos(pitch_rad) + Vector3.UP * eff_distance * sin(pitch_rad)
	camera.fov = eff_fov

	# Push the look-at point past the subject along the ground so the
	# camera aims a bit above them instead of dead-on, leaving them
	# eff_framing_bias of the frame height below screen center.
	var frame_half_height := eff_distance * tan(deg_to_rad(eff_fov) * 0.5)
	var biased_target := look_target + ground_forward * frame_half_height * eff_framing_bias

	camera.look_at(biased_target)
