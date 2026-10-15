extends Node3D
class_name Wagon

# Floor 3's place to work Glassbone: a grindstone on an A-frame, set
# down beside a handcart (Handcart, its own prop) and stepped away from -
# the tools still on it. Not a merchant, not a station: nothing about it
# is waiting for the Wanderer. Placed from data (a FloorProp: position,
# yaw, roll, world_line; anything else through overrides) - nothing
# floor-specific is in wagon.tscn. The class keeps the wagon's name: the
# screen it opens (WagonScreen) and the run's tempering are the wagon's.
#
# The body is model_scene_path on its own colour map (colour_map_path)
# under the painted shader, with the enemy_fog pass laid over it at
# fog_factor (PaintedProp, as the belongings items wear it). The model's
# bbox bottom is seated on Pose's origin. Grounded by its footprint on
# the relief as drawn (Ground.get_visible_height_at()): the base at the
# mean of the sand under its four bottom corners, pitched and rolled to
# the slope between them, roll_degrees on top, sunk sink_depth. A box of
# the bbox is its collision, MAKE_STATIC so the field's freeze leaves it
# in the space, and the walk grid steps round it.
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

@export_group("Model")
@export_file("*.glb", "*.tscn") var model_scene_path: String = "res://assets/models/props/glassbone grindstone/grindstone.glb":
	set(value):
		model_scene_path = value
		_rebuild()
# The model's own colour map: its glb's first image, extracted on import,
# with the stone wheel taken a step below dry sand (tools/darken_part.py -
# the value rule; it came out brighter than the sand).
@export_file("*.jpg", "*.png") var colour_map_path: String = "res://assets/models/props/glassbone grindstone/grindstone_valued.png":
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
# Its facing, degrees round Y. From FloorProp.yaw_degrees.
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		_apply_yaw()
# A list round its own Z on top of the slope's. From
# FloorProp.roll_degrees.
@export var roll_degrees: float = 0.0:
	set(value):
		roll_degrees = value
		_apply_pose()
# How far the base sits into the sand.
@export var sink_depth: float = 0.03:
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

# Pose carries the slope's pitch and roll and the sink; the model and its
# collision sit on it.
var _pose: Node3D = null
# Radians round the body's own X and Z: the drawn relief's slope under its
# footprint, from _ground_to_relief(); 0 until it is grounded.
var _pitch: float = 0.0
var _ground_roll: float = 0.0
var _model: Node3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
# The model's bbox on Pose, its bottom at Pose's origin.
var _aabb: AABB = AABB()
var _collision_body: StaticBody3D = null
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
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_spawn_model()
	_spawn_approach()
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	_push_fog()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Wagon '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

# The model on Pose, dressed and seated, and its box collision.
func _spawn_model() -> void:
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("Wagon '%s': could not load %s; no body." % [name, model_scene_path])
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
	_model.position.y -= _aabb.position.y
	_aabb.position.y = 0.0
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
	_pose.add_child(_collision_body)
	_apply_pose()

# A new model or colour map: the body and its collision again.
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

# The slope's pitch round X, then its roll and roll_degrees round Z, at
# the base centre, and the sink.
func _apply_pose() -> void:
	if _pose == null:
		return
	var basis := Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, _ground_roll + deg_to_rad(roll_degrees))
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

# The base at the mean height of the drawn relief under the footprint's
# four bottom corners, pitched to the slope from its -Z side to its +Z and
# rolled to the slope from -X to +X.
func _ground_to_relief() -> void:
	if _ground == null or not is_inside_tree() or _aabb.size == Vector3.ZERO:
		return
	var x0: float = _aabb.position.x
	var x1: float = _aabb.end.x
	var z0: float = _aabb.position.z
	var z1: float = _aabb.end.z
	var h00: float = _height_under(Vector3(x0, 0.0, z0))
	var h10: float = _height_under(Vector3(x1, 0.0, z0))
	var h01: float = _height_under(Vector3(x0, 0.0, z1))
	var h11: float = _height_under(Vector3(x1, 0.0, z1))
	global_position.y = (h00 + h10 + h01 + h11) * 0.25
	# A positive turn round X lowers +Z: the front side up is a negative one.
	_pitch = -atan2((h01 + h11) - (h00 + h10), 2.0 * (z1 - z0))
	# A positive turn round Z raises +X.
	_ground_roll = atan2((h10 + h11) - (h00 + h01), 2.0 * (x1 - x0))
	_apply_pose()

# The drawn relief's height under a point in this wagon's own yawed frame.
func _height_under(local_point: Vector3) -> float:
	var flat := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), Vector3(global_position.x, 0.0, global_position.z))
	var world: Vector3 = flat * local_point
	var local_xz: Vector3 = _ground.to_local(Vector3(world.x, 0.0, world.z))
	return _ground.get_visible_height_at(Vector2(local_xz.x, local_xz.z))

# Whether the Wanderer at `from` is in reach (approach_radius, on the
# ground).
func can_open_from(from: Vector3) -> bool:
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

func _say(text: String) -> void:
	if _approach != null:
		_approach.say_near(text, hold_seconds, fade_seconds, self, Vector3.UP * (_aabb.size.y + line_clearance_m))

# The body's bbox on screen, as it stands, grown by padding_px - the
# collector's padded rect.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _pose == null or not is_inside_tree() or _aabb.size == Vector3.ZERO:
		return Rect2()
	var to_world: Transform3D = _pose.global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * _aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)

# The body's bbox on Pose, its bottom at Pose's origin.
func get_body_aabb() -> AABB:
	return _aabb
