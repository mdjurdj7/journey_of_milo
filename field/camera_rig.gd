extends Node3D

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

var _target: Node3D

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	camera.fov = fov
	if _target:
		global_position = _target.global_position
		_place_camera()

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	var smoothed := global_position.lerp(_target.global_position, 1.0 - exp(-follow_smoothing * delta))
	var motion := smoothed - global_position

	# Below max_follow_speed this is identical to the plain lerp. Above it
	# (a dash burst) the step is clamped so the target visibly leads the
	# frame instead of the camera snapping to keep up.
	var max_step := max_follow_speed * delta
	if motion.length() > max_step:
		motion = motion.normalized() * max_step

	global_position += motion

	_place_camera()

func _place_camera() -> void:
	var pitch_rad := deg_to_rad(pitch_degrees)
	var forward := -global_transform.basis.z
	var ground_forward := Vector3(forward.x, 0.0, forward.z).normalized()

	var look_target := _target.global_position + look_offset

	# Sphere of radius `distance` around the look target: pitch swings the
	# camera between ground level (0) and directly overhead (90).
	camera.global_position = look_target - ground_forward * distance * cos(pitch_rad) + Vector3.UP * distance * sin(pitch_rad)

	# Push the look-at point past the Wanderer along the ground so the camera
	# aims a bit above them instead of dead-on, leaving them framing_bias of
	# the frame height below screen center.
	var frame_half_height := distance * tan(deg_to_rad(fov) * 0.5)
	var biased_target := look_target + ground_forward * frame_half_height * framing_bias

	camera.look_at(biased_target)
