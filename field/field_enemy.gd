extends CharacterBody3D
class_name FieldEnemy

signal contacted(enemy: FieldEnemy)

const MODEL_SCENE_PATH := "res://assets/models/sputter_placeholder.fbx"

@export var enemy_id: StringName = &"enemy"
@export var contact_radius: float = 2.0
@export var model_color: Color = Color(0.2, 0.22, 0.25, 1)
@export var model_scale: float = 1.0
@export var model_yaw_offset: float = 0.0
@export var model_ground_offset: float = 0.0

var _contacted: bool = false

@onready var contact_area: Area3D = $ContactArea
@onready var contact_shape: CollisionShape3D = $ContactArea/CollisionShape3D

func _ready() -> void:
	var shape := SphereShape3D.new()
	shape.radius = contact_radius
	contact_shape.shape = shape

	contact_area.body_entered.connect(_on_body_entered)
	contact_area.body_exited.connect(_on_body_exited)

	_spawn_model()

func _spawn_model() -> void:
	var model := (load(MODEL_SCENE_PATH) as PackedScene).instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = deg_to_rad(model_yaw_offset)

	var material := StandardMaterial3D.new()
	material.albedo_color = model_color
	material.roughness = 1.0
	material.metallic_specular = 0.0

	# Combined AABB of all mesh instances, expressed in this node's own
	# space (not the model's), so its bottom tells us how far to raise the
	# model regardless of the model's own pivot/rotation.
	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = material

		var mi_transform_in_self := global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_self := mi_transform_in_self * mi.get_aabb()
		combined_aabb = mi_aabb_in_self if not has_aabb else combined_aabb.merge(mi_aabb_in_self)
		has_aabb = true

	if has_aabb:
		print("FieldEnemy '%s': model AABB height = %.3f at model_scale = %.3f" % [enemy_id, combined_aabb.size.y, model_scale])
		model.position.y += -combined_aabb.position.y + model_ground_offset

# Called by region_field.gd on contact. Yaws to face target over duration,
# taking the short way around. RegionField's contact freeze stops nothing
# here (FieldEnemy has no _physics_process), but the tween still needs
# TWEEN_PAUSE_PROCESS to play through it, same as Wanderer.enter_battle_stance().
func face_toward(target: Node3D, duration: float) -> void:
	if target == null:
		return

	var to_target := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	if to_target.length() < 0.0001:
		return

	# Same verified direction<->angle convention as Wanderer._angle_from_
	# direction()/_forward_from_angle().
	var face_angle := atan2(-to_target.x, -to_target.z)
	var target_angle := rotation.y + wrapf(face_angle - rotation.y, -PI, PI)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_angle, duration)

func _on_body_entered(body: Node3D) -> void:
	if _contacted or not body.is_in_group("wanderer"):
		return
	_contacted = true
	contacted.emit(self)

# Reset the once-only guard when the Wanderer leaves, so a return visit
# (e.g. after an ESCAPE push-back) can trigger contact again.
func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_contacted = false
