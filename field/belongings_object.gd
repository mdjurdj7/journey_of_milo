extends Node3D
class_name BelongingsObject

# One of a BelongingsCache's things on the sand - a pack, a bedroll, a
# case. It holds nothing, says nothing and can't be opened from the
# field; the choice is the cache's screen (BelongingsScreen). Made by
# the cache, which places it, yaws it and grounds it.
#
# The glb on the props' shared flat material (Hull's: roughness 1, no
# specular), tinted like the hulls - its own textures are ignored. The
# bbox is measured in this node's space and its bottom seated on the
# origin, so a model whose origin isn't at its base still sits on the
# sand. A box of that bbox is its collision, MAKE_STATIC like every prop
# that must stay solid through RegionField's freeze.
#
# Taken: it sinks its own height into the sand over settle_seconds and
# frees - a settled enemy's ease (FieldEnemy.settle_and_free()).

@export_file("*.glb", "*.tscn") var model_scene_path: String = ""
@export var tint: Color = Color(0.50, 0.47, 0.42):
	set(value):
		tint = value
		if _material != null:
			_material.albedo_color = tint
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
# Uniform, on the model - the bbox, grounding and collision are measured
# after it, and a change rebuilds all three.
@export var model_scale: float = 1.0:
	set(value):
		model_scale = value
		_rebuild()
@export var settle_seconds: float = 0.5
@export var ground_path: NodePath = ^"../../../Ground"

var _model: Node3D = null
var _body: StaticBody3D = null
var _material: StandardMaterial3D = null
var _aabb: AABB = AABB()
var _ground: Ground = null
var _settling: bool = false

func _ready() -> void:
	_spawn_model()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("BelongingsObject '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(ground_to_relief)
	ground_to_relief()

func _spawn_model() -> void:
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("BelongingsObject '%s': could not load %s; no model." % [name, model_scene_path])
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.albedo_color = tint
	_aabb = AABB()
	var has_aabb := false
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Composed first, then the bbox - this node may already be yawed.
		var mi_aabb: AABB = (global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		_aabb = mi_aabb if not has_aabb else _aabb.merge(mi_aabb)
		has_aabb = true
	if not has_aabb:
		return
	_model.position.y -= _aabb.position.y
	_aabb.position.y = 0.0
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_body = body
	var box := BoxShape3D.new()
	box.size = _aabb.size
	var shape_node := CollisionShape3D.new()
	shape_node.shape = box
	shape_node.position = _aabb.get_center()
	body.add_child(shape_node)
	add_child(body)

# A new model_scale: the model, its bbox and its collision again.
func _rebuild() -> void:
	if not is_inside_tree() or _settling:
		return
	if _model != null:
		_model.free()
		_model = null
	if _body != null:
		_body.free()
		_body = null
	_spawn_model()

# Onto the relief at this node's XZ. The cache calls it after moving the
# object; the relief's own rebuild calls it too.
func ground_to_relief() -> void:
	if _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

func settle_and_free() -> void:
	if _settling:
		return
	_settling = true
	if _model == null or _aabb.size.y <= 0.0 or settle_seconds <= 0.0:
		queue_free()
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(_model, "position:y", _model.position.y - _aabb.size.y, settle_seconds)
	tween.tween_callback(queue_free)
