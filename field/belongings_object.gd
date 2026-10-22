extends Node3D
class_name BelongingsObject

# One of a BelongingsCache's things on the sand - a pack, a bedroll, a
# case. It holds nothing, says nothing and can't be opened from the
# field; the choice is the cache's screen (BelongingsScreen). Made by
# the cache, which places it, yaws it and grounds it.
#
# The glb's own colour map (<model>_Image_0.jpg beside it, Meshy's
# baseColor) on the painted shader, times tint - the models' soft light
# (field/wanderer_painted.gdshader: roughness 1, no specular, no normal
# map). The shader is fog_disabled, so the depth fog is laid back over it
# by an enemy_fog.gdshader pass at fog_factor, filled from the field's
# RegionSky and again whenever its fog changes (both through PaintedProp,
# which the workbench and the handcart share). If the shader or the
# colour map fails to load, the hulls' flat material wears the tint.
# With material_path set, that material is worn instead, as it is - no
# tint, the scene's own fog (the cache's shard, in the seam's Glassbone). The
# bbox is measured in this node's space and its bottom seated on the
# origin, so a model whose origin isn't at its base still sits on the
# sand. A box of that bbox is its collision, MAKE_STATIC like every prop
# that must stay solid through RegionField's freeze.
#
# Taken: it sinks its own height into the sand over settle_seconds and
# frees - a settled enemy's ease (FieldEnemy.settle_and_free()).

# Beside the model: <model>_Image_0.jpg, its colour map.
const COLOUR_MAP_SUFFIX := "_Image_0.jpg"

@export_file("*.glb", "*.tscn") var model_scene_path: String = ""
# A material worn in place of the painted one, untinted; empty = painted.
# Read when the model is made.
@export_file("*.tres") var material_path: String = "":
	set(value):
		material_path = value
		_rebuild()
@export var tint: Color = Color(0.76, 0.62, 0.46):
	set(value):
		tint = value
		if material_path.is_empty():
			set_material_tint(_material, tint)
# The object's share of the depth fog - 1 fogged as the scene fogs it.
@export_range(0.0, 1.0, 0.01) var fog_factor: float = 1.0:
	set(value):
		fog_factor = value
		_push_fog()
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
@export var region_field_path: NodePath = ^"../../.."

var _model: Node3D = null
var _body: StaticBody3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
var _aabb: AABB = AABB()
var _ground: Ground = null
var _settling: bool = false

func _ready() -> void:
	_spawn_model()
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	_push_fog()
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
	_fog = null
	_material = load(material_path) as Material if not material_path.is_empty() else null
	if _material == null:
		if not material_path.is_empty():
			push_warning("BelongingsObject '%s': could not load %s; painted instead." % [name, material_path])
		_material = painted_material(model_scene_path, tint)
		if _material != null:
			_fog = PaintedProp.fog_pass()
			_material.next_pass = _fog
		else:
			_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
			set_material_tint(_material, tint)
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

# The model's own colour map under the painted shader, times tint - its
# own material, so its tint is its own. Null when the shader or the map
# fails to load. BelongingsScreen dresses its renders with it too.
static func painted_material(model_path: String, albedo_tint: Color) -> ShaderMaterial:
	return PaintedProp.material(model_path.get_basename() + COLOUR_MAP_SUFFIX, albedo_tint)

# A painted material's albedo_tint, a flat one's albedo_color.
static func set_material_tint(material: Material, albedo_tint: Color) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("albedo_tint", albedo_tint)
	elif material is BaseMaterial3D:
		(material as BaseMaterial3D).albedo_color = albedo_tint

# The field's depth fog into the fog pass, as the Wanderer's is
# (Wanderer.refresh_fog()).
func _push_fog() -> void:
	PaintedProp.push_fog(_fog, _sky, fog_factor)

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
	_push_fog()

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
