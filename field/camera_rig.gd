extends Node3D

@export var target_path: NodePath = ^"../Wanderer"
@export var distance: float = 9.0
@export var height: float = 4.0
@export var pitch_degrees: float = 18.0
@export var follow_smoothing: float = 6.0

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
	global_position = global_position.lerp(_target.global_position, 1.0 - exp(-follow_smoothing * delta))
