extends Node3D

@export var target_path: NodePath = ^"../Wanderer"
@export var distance: float = 9.0
@export var height: float = 4.0
@export var pitch_degrees: float = 18.0
@export var follow_smoothing: float = 6.0
@export var max_follow_speed: float = 10.0

var _target: Node3D

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	camera.rotation_degrees.x = -pitch_degrees
	camera.position = Vector3(0.0, height, distance)
	if _target:
		global_position = _target.global_position

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
