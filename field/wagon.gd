extends Node3D
class_name Wagon

# A wagon set down and left, its tools still on it - floor 3's place to
# work Glassbone. Not a merchant, not a station: nothing about it is
# waiting for the Wanderer. Placed from data (a FloorProp: position, yaw,
# roll, world_line; anything else through overrides) - nothing floor-
# specific is in wagon.tscn.
#
# A placeholder body until its model exists: one low box, body_length
# along its own Z by body_width by body_height, in the project's flat
# matte (Hull's shared material, duplicated) at the hulls' weathered-wood
# tint. Origin at the base, grounded by its footprint - the base at the
# mean of the relief under its four bottom corners, pitched along its
# length to the slope between its two ends, so neither end floats - then
# rolled roll_degrees round its long axis and sunk sink_depth into the
# sand: age by placement alone, nothing broken. A box StaticBody3D the Wanderer
# walks round, MAKE_STATIC so the field's freeze leaves it in the space.
#
# The walk-up and the click are PropApproach's, as the collector's are:
# inside approach_radius the world line shows near the body, once per
# visit; a left click on the body in reach emits open_requested, for
# RegionField to open the wagon's screen (WagonScreen) with the field
# locked. Anything else falls through to the field's move click.
#
# What it does lives in the run, not here: tempering spends temper_cost
# Glassbone for a card's tempered version (RunState.temper_card()). The
# screen's lines are this node's exports, so a floor can override them.

signal open_requested(wagon: Wagon)
# A temper export changed - an open screen redraws.
signal temper_changed()

const GROUP := &"wagons"

@export_group("Body")
@export var body_length: float = 2.4:
	set(value):
		body_length = value
		_apply_body()
@export var body_width: float = 1.2:
	set(value):
		body_width = value
		_apply_body()
@export var body_height: float = 1.0:
	set(value):
		body_height = value
		_apply_body()
# Hull.hull_tint's weathered wood.
@export var tint: Color = Color(0.50, 0.47, 0.42):
	set(value):
		tint = value
		_apply_tint()
@export_group("")

@export_group("Placement")
# Its facing, degrees round Y: the long axis runs along +Z at 0. From
# FloorProp.yaw_degrees.
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		_apply_yaw()
# The list round its long axis, settled rather than set level. From
# FloorProp.roll_degrees.
@export var roll_degrees: float = 4.0:
	set(value):
		roll_degrees = value
		_apply_pose()
# How far the base sits into the sand - past the roll's own dip, so
# neither bottom edge floats.
@export var sink_depth: float = 0.08:
	set(value):
		sink_depth = value
		_apply_pose()
@export_group("")

@export_group("Approach")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		_apply_approach_radius()
# Set from FloorProp.world_line by RegionField; this is the placeholder.
@export_multiline var world_line: String = "A wagon, unhitched. The tools are still on it."
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
# Metres above the body's top the line is anchored at.
@export var line_clearance_m: float = 0.6
@export_group("")

@export_group("Temper")
# Glassbone per temper (RunState.temper_card(); at least 1). A change
# re-reads an open screen (temper_changed).
@export var temper_cost: int = 1:
	set(value):
		temper_cost = value
		temper_changed.emit()
# The screen's world-voice line while the Glassbone covers temper_cost,
# and while it doesn't.
@export_multiline var working_line: String = "Someone worked it here. The tools still fit the hand.":
	set(value):
		working_line = value
		temper_changed.emit()
@export_multiline var empty_line: String = "The tools are laid out. There is nothing here to work.":
	set(value):
		empty_line = value
		temper_changed.emit()
# Said over the tempered card after a temper, for held_seconds.
@export_multiline var held_line: String = "It holds.":
	set(value):
		held_line = value
		temper_changed.emit()
@export var held_seconds: float = 1.2
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# Pose carries the pitch, the roll and the sink; the body sits on it.
var _pose: Node3D = null
# Radians round the body's own X: the relief's slope along its length,
# from _ground_to_relief(); 0 until it is grounded.
var _pitch: float = 0.0
var _mesh_instance: MeshInstance3D = null
var _mesh: BoxMesh = null
var _material: StandardMaterial3D = null
var _collision_body: StaticBody3D = null
var _collision_shape: BoxShape3D = null
var _collision_node: CollisionShape3D = null
var _approach: PropApproach = null
var _ground: Ground = null

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief, the entry's yaw and roll as this wagon's own.
func set_floor_placement(world_position: Vector3, yaw: float, roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw
	roll_degrees = roll

func _ready() -> void:
	add_to_group(GROUP)
	_apply_yaw()
	_spawn_body()
	_spawn_approach()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Wagon '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_body() -> void:
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_mesh = BoxMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_mesh_instance.material_override = _material
	_pose.add_child(_mesh_instance)
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# RegionField's freeze would otherwise take the body out of the
	# physics space (the trough's reason).
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_collision_shape = BoxShape3D.new()
	_collision_node = CollisionShape3D.new()
	_collision_node.shape = _collision_shape
	_collision_body.add_child(_collision_node)
	_pose.add_child(_collision_body)
	_apply_body()
	_apply_pose()
	_apply_tint()

# The box on Pose, its underside on Pose's origin.
func _apply_body() -> void:
	var size := Vector3(maxf(body_width, 0.01), maxf(body_height, 0.01), maxf(body_length, 0.01))
	if _mesh != null:
		_mesh.size = size
		_mesh_instance.position = Vector3(0.0, size.y * 0.5, 0.0)
	if _collision_shape != null:
		_collision_shape.size = size
		_collision_node.position = Vector3(0.0, size.y * 0.5, 0.0)
	_ground_to_relief()

func _apply_tint() -> void:
	if _material != null:
		_material.albedo_color = tint

func _apply_yaw() -> void:
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	_ground_to_relief()

# The relief's pitch round X, then the roll round the long axis (Z), at
# the base centre, and the sink.
func _apply_pose() -> void:
	if _pose == null:
		return
	var basis := Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, deg_to_rad(roll_degrees))
	_pose.transform = Transform3D(basis, Vector3(0.0, -sink_depth, 0.0))

# The walk-up and the click (PropApproach): the line near the body once
# per visit; a click on the body in reach asks to open.
func _spawn_approach() -> void:
	_approach = PropApproach.new()
	_approach.name = "Approach"
	_approach.warning_label = "Wagon"
	_approach.on_visit = func() -> void: _say(world_line)
	_approach.can_open_from = can_open_from
	_approach.screen_rect = get_screen_rect
	_approach.open_requested.connect(func() -> void: open_requested.emit(self))
	add_child(_approach)
	_apply_approach_radius()

func _apply_approach_radius() -> void:
	if _approach != null:
		_approach.set_radius(approach_radius)

# The base at the mean height of the relief under the four bottom
# corners, pitched to the slope from its back end to its front.
func _ground_to_relief() -> void:
	if _ground == null or not is_inside_tree():
		return
	var half := Vector2(maxf(body_width, 0.01) * 0.5, maxf(body_length, 0.01) * 0.5)
	var ends: Array[float] = [0.0, 0.0]
	for side: float in [-1.0, 1.0]:
		for end_index in 2:
			var corner := Vector3(side * half.x, 0.0, (-1.0 if end_index == 0 else 1.0) * half.y)
			ends[end_index] += _height_under(corner) * 0.5
	global_position.y = (ends[0] + ends[1]) * 0.5
	# A positive turn round X lowers +Z: the front end up is a negative one.
	_pitch = -atan2(ends[1] - ends[0], half.y * 2.0)
	_apply_pose()

# The relief's height under a point in this wagon's own yawed frame.
func _height_under(local_point: Vector3) -> float:
	var flat := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), Vector3(global_position.x, 0.0, global_position.z))
	var world: Vector3 = flat * local_point
	var local_xz: Vector3 = _ground.to_local(Vector3(world.x, 0.0, world.z))
	return _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# Whether the Wanderer at `from` is in reach (approach_radius, on the
# ground).
func can_open_from(from: Vector3) -> bool:
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

func _say(text: String) -> void:
	if _approach != null:
		_approach.say_near(text, hold_seconds, fade_seconds, self, Vector3.UP * (body_height + line_clearance_m))

# The box on screen, rolled and sunk, grown by padding_px - the
# collector's padded rect.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _pose == null or not is_inside_tree():
		return Rect2()
	var box := AABB(Vector3(-body_width * 0.5, 0.0, -body_length * 0.5), Vector3(body_width, body_height, body_length))
	var to_world: Transform3D = _pose.global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * box.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)
