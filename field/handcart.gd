extends Node3D
class_name Handcart

# A two-wheeled handcart set down and left beside floor 3's grindstone
# (the workbench, Wagon): tipped forward round its axle until its shaft
# tips rest on the sand, sunk a little, listing a little. It says
# nothing and opens nothing - the grindstone is what answers him. Placed
# from data (a FloorProp: position, yaw, roll; anything else through
# overrides) - nothing floor-specific is in handcart.tscn.
#
# The body is model_scene_path on its own colour map (colour_map_path)
# under the painted shader, with the enemy_fog pass laid over it at
# fog_factor (PaintedProp, as the belongings items wear it). The model's
# own frame: its base at y 0, the shafts out along +X, the axle across Z
# at axle_point. Its yaw turns +X (the shafts) to (cos, 0, -sin).
#
# The pose, on the relief as drawn (Ground.get_visible_height_at()): the
# axle at wheel_radius over the sand under the two wheels, the cart
# turned round the axle until shaft_tip (and its mirror across Z) meets
# the sand under the tips, rolled round its length to the sand's tilt
# between the wheels plus roll_degrees, and all of it sunk sink_depth.
# Two boxes are its collision - the bed and wheels, and the narrower
# shafts - MAKE_STATIC so the field's freeze leaves them in the space,
# and the walk grid steps round them.

@export_group("Model")
@export_file("*.glb", "*.tscn") var model_scene_path: String = "res://assets/models/props/glassbone wagon/wagon.glb":
	set(value):
		model_scene_path = value
		_rebuild()
# The model's own colour map: its glb's first image, extracted on import.
@export_file("*.jpg", "*.png") var colour_map_path: String = "res://assets/models/props/glassbone wagon/wagon_0.jpg":
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

@export_group("Geometry")
# Measured off the model (handcart glb, metres in its own frame): the
# axle's centre (the hubs, centred across Z), the wheels' radius and how
# far each wheel's tread sits off the middle, and the point of a shaft
# that meets the sand when the cart is tipped onto it - its mirror across
# Z is the other shaft's.
@export var axle_point: Vector3 = Vector3(-0.636, 0.481, 0.0):
	set(value):
		axle_point = value
		_ground_to_relief()
@export var wheel_radius: float = 0.48:
	set(value):
		wheel_radius = value
		_ground_to_relief()
@export var wheel_offset: float = 0.69:
	set(value):
		wheel_offset = value
		_ground_to_relief()
@export var shaft_tip: Vector3 = Vector3(1.495, 0.401, 0.341):
	set(value):
		shaft_tip = value
		_ground_to_relief()
# Where along X the bed's collision box ends and the shafts' begins, and
# the shafts' box's half-width across Z.
@export var shaft_split_x: float = 0.35:
	set(value):
		shaft_split_x = value
		_rebuild()
@export var shaft_half_width: float = 0.45:
	set(value):
		shaft_half_width = value
		_rebuild()
@export_group("")

@export_group("Placement")
# Its facing, degrees round Y: the shafts point along +X at 0. From
# FloorProp.yaw_degrees.
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		_apply_yaw()
# A list round its length on top of the sand's. From
# FloorProp.roll_degrees.
@export var roll_degrees: float = 2.0:
	set(value):
		roll_degrees = value
		_ground_to_relief()
# How far the wheels and the shaft tips sit into the sand.
@export var sink_depth: float = 0.04:
	set(value):
		sink_depth = value
		_ground_to_relief()
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# Pose carries the tip, the roll and the height; the model and its
# collision sit on it.
var _pose: Node3D = null
var _model: Node3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
# The model's bbox on Pose, in the model's own frame.
var _aabb: AABB = AABB()
var _collision_body: StaticBody3D = null
var _ground: Ground = null
# Radians the cart is turned round its axle, shafts down - from
# _ground_to_relief(); 0 until it is grounded.
var _tip: float = 0.0

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief, the entry's yaw and roll as this cart's own.
func set_floor_placement(world_position: Vector3, yaw: float, roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw
	roll_degrees = roll

func _ready() -> void:
	_apply_yaw()
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_spawn_model()
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	_push_fog()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Handcart '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

# The model on Pose in its own frame, dressed, and its two boxes.
func _spawn_model() -> void:
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("Handcart '%s': could not load %s; no body." % [name, model_scene_path])
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_pose.add_child(_model)
	_material = PaintedProp.material(colour_map_path, tint)
	_fog = null
	if _material != null:
		_fog = PaintedProp.fog_pass()
		_material.next_pass = _fog
	else:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		_apply_tint()
	_aabb = PaintedProp.dress_model(_model, _material, _pose)
	if _aabb.size == Vector3.ZERO:
		return
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# RegionField's freeze would otherwise take the body out of the
	# physics space (the trough's reason).
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var split: float = clampf(shaft_split_x, _aabb.position.x, _aabb.end.x)
	# The bed and wheels: the full width, from the tail to the split.
	_add_box(Vector3(_aabb.position.x, _aabb.position.y, _aabb.position.z), Vector3(split, _aabb.end.y, _aabb.end.z))
	# The shafts: from the split to the tips, shaft_half_width either side.
	var half: float = minf(shaft_half_width, _aabb.end.z)
	_add_box(Vector3(split, _aabb.position.y, -half), Vector3(_aabb.end.x, _aabb.end.y, half))
	_pose.add_child(_collision_body)

func _add_box(low: Vector3, high: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = (high - low).abs()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = box
	shape_node.position = (low + high) * 0.5
	_collision_body.add_child(shape_node)

# A new model, colour map or split: the body and its collision again.
func _rebuild() -> void:
	if not is_inside_tree() or _pose == null:
		return
	if _model != null:
		_model.free()
		_model = null
	if _collision_body != null:
		_collision_body.free()
		_collision_body = null
	_spawn_model()
	_push_fog()
	_ground_to_relief()

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
	_ground_to_relief()

# This node at the sand's height under the axle's middle; Pose turned
# round the axle until the shaft tips meet the sand, rolled round the
# cart's length through the axle, the axle wheel_radius over the sand
# under the wheels, all sunk sink_depth.
func _ground_to_relief() -> void:
	if _ground == null or _pose == null or not is_inside_tree():
		return
	var axle_flat := Vector3(axle_point.x, 0.0, 0.0)
	var left: float = _height_under(axle_flat + Vector3(0.0, 0.0, -wheel_offset))
	var right: float = _height_under(axle_flat + Vector3(0.0, 0.0, wheel_offset))
	var wheels: float = (left + right) * 0.5
	var tips: float = (_height_under(Vector3(shaft_tip.x, 0.0, -shaft_tip.z)) + _height_under(Vector3(shaft_tip.x, 0.0, shaft_tip.z))) * 0.5
	global_position.y = wheels
	# In this node's frame, now on the sand under the wheels: the axle's
	# height and the tips' target.
	var axle_y: float = wheel_radius - sink_depth
	var tip_target: float = tips - wheels - sink_depth
	# The shaft tip turned by -tip round the axle (shafts down) is at
	# axle_y + dy cos(tip) - dx sin(tip); solved for tip_target as
	# r cos(tip + phi) with r = |(dx, dy)| and phi = atan2(dx, dy).
	var dx: float = shaft_tip.x - axle_point.x
	var dy: float = shaft_tip.y - axle_point.y
	var r: float = sqrt(dx * dx + dy * dy)
	var phi: float = atan2(dx, dy)
	_tip = acos(clampf((tip_target - axle_y) / maxf(r, 0.001), -1.0, 1.0)) - phi
	# Wheel to wheel the sand tilts round the cart's length; a positive
	# turn round X lowers +Z.
	var roll: float = -atan2(right - left, 2.0 * wheel_offset) + deg_to_rad(roll_degrees)
	var turn := Basis(Vector3.RIGHT, roll) * Basis(Vector3.BACK, -_tip)
	var axle_at := Vector3(axle_point.x, axle_y, 0.0)
	_pose.transform = Transform3D(turn, axle_at) * Transform3D(Basis.IDENTITY, -axle_point)

# The drawn relief's height under a point in this cart's own yawed frame.
func _height_under(local_point: Vector3) -> float:
	var flat := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), Vector3(global_position.x, 0.0, global_position.z))
	var world: Vector3 = flat * local_point
	var local_xz: Vector3 = _ground.to_local(Vector3(world.x, 0.0, world.z))
	return _ground.get_visible_height_at(Vector2(local_xz.x, local_xz.z))

# Degrees the cart stands tipped round its axle, shafts down.
func get_tip_degrees() -> float:
	return rad_to_deg(_tip)

# Where a model-frame point stands in the world, as posed - for probes.
func model_to_world(model_point: Vector3) -> Vector3:
	return _pose.global_transform * model_point if _pose != null else global_transform * model_point
