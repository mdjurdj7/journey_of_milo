extends Node3D
class_name SandFence

# One section of an old sand fence - slats wired together, set along a
# beach to catch blown sand and long since let go: floor 2's broken run
# inland of the strandline. Placed from data (a FloorProp: position,
# yaw, and its lean as roll_degrees); nothing floor-specific is in
# sand_fence.tscn.
#
# The model is sand_fence.glb (1.78 m long along X, 1.2 m high, 0.14 m
# deep, its base at y 0 on the origin) on its own colour map under the
# painted shader, with the enemy_fog pass over it at fog_factor
# (PaintedProp, as the BaskingSlab wears it). The map's rusted wire reads
# orange on the sand; rust_amount turns its saturated colours toward
# rust_tint (wanderer_painted.gdshader), the map itself untouched.
#
# Lean: the section turns about its base line (local X) by lean_degrees,
# its top toward local +Z (negative: toward -Z); +-90 lies it flat. A
# standing or leaning one is grounded by the lowest sand under its
# footprint's corners and centre, so no end floats; a lying one by their
# mean (lying_min_lean_degrees). Then it sinks sink_depth - a standing
# section's base buried, a fallen one bedded in.
#
# Collision only while it stands (|lean| at or under upright_max_lean_
# degrees): a box round the model, MAKE_STATIC so the field's freeze
# leaves it in the space, which the walk grid steps round. A leaning or
# fallen section has none - he walks over or past it. Every section's
# footprint (get_footprint()) is a scatter keep-out (FieldScatter), so
# nothing grows through the slats whether it stands or lies.

@export_group("Model")
@export_file("*.glb", "*.tscn") var model_scene_path: String = "res://assets/models/props/sand_fence/sand_fence.glb":
	set(value):
		model_scene_path = value
		_rebuild()
@export_file("*.jpg", "*.png") var colour_map_path: String = "res://assets/models/props/sand_fence/sand_fence_0.jpg":
	set(value):
		colour_map_path = value
		_rebuild()
# Multiplied into the colour map - white is the map as painted.
@export var tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		tint = value
		_apply_tint()
# The rusted wire's turn toward rust_tint: 0 as painted, 1 all the way.
@export_range(0.0, 1.0, 0.01) var rust_amount: float = 0.85:
	set(value):
		rust_amount = value
		_apply_tint()
# Dark brown-grey, old wire weathered to the slats' colour.
@export var rust_tint: Color = Color(0.30, 0.28, 0.26):
	set(value):
		rust_tint = value
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
		_apply_pose()
# Degrees off upright about its base line, the top toward local +Z
# (negative: -Z); +-90 lies flat. From FloorProp.roll_degrees.
@export_range(-90.0, 90.0, 0.5) var lean_degrees: float = 0.0:
	set(value):
		lean_degrees = value
		_apply_pose()
# How far its lowest point sits into the sand.
@export var sink_depth: float = 0.3:
	set(value):
		sink_depth = value
		_ground_to_relief()
# Standing - and so solid - while it leans no more than this.
@export var upright_max_lean_degrees: float = 5.0:
	set(value):
		upright_max_lean_degrees = value
		_rebuild_collision()
# Lying - grounded on the mean sand under its face, not the lowest -
# from this lean on.
@export var lying_min_lean_degrees: float = 60.0:
	set(value):
		lying_min_lean_degrees = value
		_ground_to_relief()
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

var _model: Node3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
# The model's bbox in its own (unleaned) frame.
var _aabb: AABB = AABB()
var _pivot: Node3D = null
var _collision_body: StaticBody3D = null
var _ground: Ground = null

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief, the entry's yaw as its own, its roll as the lean.
func set_floor_placement(world_position: Vector3, yaw: float, roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw
	lean_degrees = roll

func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Lean"
	add_child(_pivot)
	_spawn_model()
	_apply_pose()
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	_push_fog()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("SandFence '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func is_standing() -> bool:
	return absf(lean_degrees) <= upright_max_lean_degrees

# Its ground outline, world XZ: the hull of its leaned box's corners.
func get_footprint() -> PackedVector2Array:
	var points := PackedVector2Array()
	if _pivot == null or _aabb.size == Vector3.ZERO:
		return points
	for i in 8:
		var corner: Vector3 = _pivot.global_transform * _aabb.get_endpoint(i)
		points.append(Vector2(corner.x, corner.z))
	return Geometry2D.convex_hull(points)

func _spawn_model() -> void:
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("SandFence '%s': could not load %s; no body." % [name, model_scene_path])
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_pivot.add_child(_model)
	_material = PaintedProp.material(colour_map_path, tint)
	_fog = null
	if _material != null:
		_fog = PaintedProp.fog_pass()
		_material.next_pass = _fog
		_apply_tint()
	else:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		_apply_tint()
	_aabb = PaintedProp.dress_model(_model, _material, _pivot)
	_rebuild_collision()

func _rebuild() -> void:
	if not is_inside_tree() or _pivot == null:
		return
	if _model != null:
		_model.free()
		_model = null
	_spawn_model()
	_push_fog()
	_ground_to_relief()

# A box round the model, on the lean pivot, while it stands; none else.
func _rebuild_collision() -> void:
	if _collision_body != null:
		_collision_body.free()
		_collision_body = null
	if _pivot == null or _aabb.size == Vector3.ZERO or not is_standing():
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var box := BoxShape3D.new()
	box.size = _aabb.size
	var shape_node := CollisionShape3D.new()
	shape_node.shape = box
	shape_node.position = _aabb.get_center()
	_collision_body.add_child(shape_node)
	_pivot.add_child(_collision_body)

func _apply_tint() -> void:
	if _material is ShaderMaterial:
		var painted := _material as ShaderMaterial
		painted.set_shader_parameter("albedo_tint", tint)
		painted.set_shader_parameter("rust_amount", rust_amount)
		painted.set_shader_parameter("rust_tint", rust_tint)
	elif _material is BaseMaterial3D:
		(_material as BaseMaterial3D).albedo_color = tint

func _push_fog() -> void:
	PaintedProp.push_fog(_fog, _sky, fog_factor)

func _apply_pose() -> void:
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	if _pivot == null:
		return
	_pivot.rotation = Vector3(deg_to_rad(lean_degrees), 0.0, 0.0)
	_rebuild_collision()
	_ground_to_relief()

# Its lowest point on the lowest sand under its footprint, sunk
# sink_depth.
func _ground_to_relief() -> void:
	if _ground == null or not is_inside_tree() or _pivot == null or _aabb.size == Vector3.ZERO:
		return
	var leaned: Transform3D = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(lean_degrees)), Vector3.ZERO)
	var lowest: float = INF
	for i in 8:
		lowest = minf(lowest, (leaned * _aabb.get_endpoint(i)).y)
	var lowest_sand: float = INF
	var total: float = 0.0
	var footprint: PackedVector2Array = get_footprint()
	footprint.append(Vector2(global_position.x, global_position.z))
	for point in footprint:
		var local_xz: Vector3 = _ground.to_local(Vector3(point.x, 0.0, point.y))
		var height: float = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))
		lowest_sand = minf(lowest_sand, height)
		total += height
	# Lying, its whole face is on the sand: the mean under it, or the
	# lowest corner would bury the rest.
	var sand: float = total / float(footprint.size()) if absf(lean_degrees) >= lying_min_lean_degrees else lowest_sand
	global_position.y = sand - lowest - sink_depth
