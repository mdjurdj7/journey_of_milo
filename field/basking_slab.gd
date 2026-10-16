extends Node3D
class_name BaskingSlab

# A stone a basking enemy lies on - the Adder's slab in its den on floor
# 4, and floor 5's crest rock under the Greyshelf (its model and colour
# map through the FloorProp's overrides). Each a stand-in until a
# modelled one replaces it, so the model and its colour map are paths and
# nothing else knows its shape. It says nothing and opens nothing. Placed
# from data (a FloorProp in the encounter: position and yaw; anything
# else through overrides) - nothing floor-specific is in
# basking_slab.tscn. The enemy stands on its top by its own
# FloorEnemy.height_offset_m, not by asking this.
#
# The body is model_scene_path on its own colour map (colour_map_path)
# under the painted shader, with the enemy_fog pass laid over it at
# fog_factor (PaintedProp, as the Handcart wears it). The model's own
# frame: its base at y 0, centred on the origin, Y up.
#
# Grounded on the relief at its own XZ (Ground.get_height_at()), sunk
# sink_depth. One box round the model is its collision, MAKE_STATIC so
# the field's freeze leaves it in the space: low enough to step up onto,
# and the walk grid steps round it.

@export_group("Model")
@export_file("*.glb", "*.tscn") var model_scene_path: String = "res://assets/models/props/basking slab/basking_slab.glb":
	set(value):
		model_scene_path = value
		_rebuild()
# The model's scale per axis, in its own frame (X its length, Z its
# width) - a placeholder stretched to hold what lies on it (floor 5's
# crest rock under the Greyshelf). Its box and collision follow.
@export var model_scale: Vector3 = Vector3.ONE:
	set(value):
		model_scale = value
		_rebuild()
# The model's own colour map.
@export_file("*.jpg", "*.png") var colour_map_path: String = "res://assets/models/props/basking slab/basking_slab_albedo.png":
	set(value):
		colour_map_path = value
		_rebuild()
# Multiplied into the colour map - white is the map as painted.
@export var tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		tint = value
		_apply_tint()
# Its share of the depth fog - 1 fogged as the scene fogs it.
@export_range(0.0, 1.0, 0.01) var fog_factor: float = 1.0:
	set(value):
		fog_factor = value
		_push_fog()
@export_group("")

@export_group("Placement")
# Its facing, degrees round Y: the model's +X (its length) turns to
# (cos, 0, -sin). From FloorProp.yaw_degrees.
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		_apply_yaw()
# How far its base sits into the sand.
@export var sink_depth: float = 0.04:
	set(value):
		sink_depth = value
		_ground_to_relief()
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

var _model: Node3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
# The model's bbox in this node's frame.
var _aabb: AABB = AABB()
var _collision_body: StaticBody3D = null
var _ground: Ground = null

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief, the entry's yaw as this slab's own. It doesn't roll.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	_apply_yaw()
	_spawn_model()
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	_push_fog()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("BaskingSlab '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

# The model in its own frame, dressed, and its box.
func _spawn_model() -> void:
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("BaskingSlab '%s': could not load %s; no body." % [name, model_scene_path])
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = model_scale
	add_child(_model)
	_material = PaintedProp.material(colour_map_path, tint)
	_fog = null
	if _material != null:
		_fog = PaintedProp.fog_pass()
		_material.next_pass = _fog
	else:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		_apply_tint()
	_aabb = PaintedProp.dress_model(_model, _material, self)
	if _aabb.size == Vector3.ZERO:
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# RegionField's freeze would otherwise take the body out of the
	# physics space (the trough's reason).
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var box := BoxShape3D.new()
	box.size = _aabb.size
	var shape_node := CollisionShape3D.new()
	shape_node.shape = box
	shape_node.position = _aabb.get_center()
	_collision_body.add_child(shape_node)
	add_child(_collision_body)

# A new model or colour map: the body and its collision again.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _model != null:
		_model.free()
		_model = null
	if _collision_body != null:
		_collision_body.free()
		_collision_body = null
	_spawn_model()
	_push_fog()

# A painted material's albedo_tint, the flat fallback's albedo_color.
func _apply_tint() -> void:
	if _material is ShaderMaterial:
		(_material as ShaderMaterial).set_shader_parameter("albedo_tint", tint)
	elif _material is BaseMaterial3D:
		(_material as BaseMaterial3D).albedo_color = tint

func _push_fog() -> void:
	PaintedProp.push_fog(_fog, _sky, fog_factor)

func _apply_yaw() -> void:
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)

# This node on the sand under its own origin, sunk sink_depth.
func _ground_to_relief() -> void:
	if _ground == null or not is_inside_tree():
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z)) - sink_depth
