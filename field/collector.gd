extends Node3D
class_name Collector

# The collector: a creature still fetching, sorting and handing things
# over, long after the people it did it for left (05_REGION_01 §9 Shop).
# It is not waiting for the Wanderer - it faces its own yaw, never turns
# toward him, never greets, never thanks. Placed from data (a FloorProp:
# position, yaw, world_line, pool; anything else through overrides) -
# nothing floor-specific is in collector.tscn.
#
# A placeholder body until its species is decided: one low, elongated
# capsule lying along its facing axis (body_length x body_height), in the
# project's flat matte (Hull's shared material, duplicated) tinted dark
# like the cormorant. Origin at the base, grounded on the relief; a
# capsule StaticBody3D the Wanderer walks round. No idle animation.
#
# The floor 2 trough's trigger (TroughProp): inside approach_radius the
# world line shows near the body, once per visit into the radius; a left
# click on the body's padded screen rect with the Wanderer in reach emits
# open_requested, for RegionField to open the collector's screen with the
# field locked. Anything else falls through to the field's move click.

signal open_requested(collector: Collector)

const GROUP := &"collectors"

@export_group("Body")
@export var body_length: float = 0.9:
	set(value):
		body_length = value
		_apply_body()
@export var body_height: float = 0.5:
	set(value):
		body_height = value
		_apply_body()
# The cormorant's (Bird.bird_tint).
@export var tint: Color = Color(0.28, 0.29, 0.31):
	set(value):
		tint = value
		_apply_tint()
@export_group("")

@export_group("Approach")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		_apply_approach_radius()
# Set from FloorProp.world_line by RegionField; this is the placeholder.
@export_multiline var world_line: String = "It is sorting what it has."
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
# Metres above the body's top the line is anchored at.
@export var line_clearance_m: float = 0.6
@export_group("")

# What its stock rolls from (FloorProp.pool, set by RegionField).
@export var stock_pool: RewardPool = null
# Set by RegionField._spawn_floor_props(): the floor's path plus the
# prop's index.
@export var collector_id: String = ""
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

var _placement_yaw: float = 0.0
var _mesh_instance: MeshInstance3D = null
var _mesh: CapsuleMesh = null
var _material: StandardMaterial3D = null
var _collision_body: StaticBody3D = null
var _collision_shape: CapsuleShape3D = null
var _collision_node: CollisionShape3D = null
var _approach_area: Area3D = null
var _approach_shape: SphereShape3D = null
var _ground: Ground = null
var _wanderer_inside: bool = false
# This visit's line has been said (reset on leaving the radius).
var _line_said: bool = false

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief, the entry's yaw as its facing - for good.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_placement_yaw = yaw
	rotation = Vector3(0.0, deg_to_rad(_placement_yaw), 0.0)

func _ready() -> void:
	add_to_group(GROUP)
	rotation = Vector3(0.0, deg_to_rad(_placement_yaw), 0.0)
	_spawn_body()
	_spawn_approach_area()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Collector '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_body() -> void:
	_mesh = CapsuleMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Body"
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# RegionField's freeze would otherwise take the body out of the
	# physics space (the trough's reason).
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_collision_shape = CapsuleShape3D.new()
	_collision_node = CollisionShape3D.new()
	_collision_node.shape = _collision_shape
	_collision_body.add_child(_collision_node)
	add_child(_collision_body)
	_apply_body()
	_apply_tint()

# A capsule of body_height across, body_length end to end, lying along
# the body's own Z (its facing axis), its underside on the origin.
func _apply_body() -> void:
	var radius: float = maxf(body_height, 0.01) * 0.5
	var length: float = maxf(body_length, radius * 2.0)
	var lying := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, radius, 0.0))
	if _mesh != null:
		_mesh.radius = radius
		_mesh.height = length
		_mesh_instance.transform = lying
	if _collision_shape != null:
		_collision_shape.radius = radius
		_collision_shape.height = length
		_collision_node.transform = lying

func _apply_tint() -> void:
	if _material != null:
		_material.albedo_color = tint

func _spawn_approach_area() -> void:
	_approach_area = Area3D.new()
	_approach_area.name = "ApproachArea"
	_approach_area.monitorable = false
	_approach_shape = SphereShape3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = _approach_shape
	_approach_area.add_child(shape_node)
	add_child(_approach_area)
	_apply_approach_radius()
	_approach_area.body_entered.connect(_on_approach_body_entered)
	_approach_area.body_exited.connect(_on_approach_body_exited)

func _apply_approach_radius() -> void:
	if _approach_shape != null:
		_approach_shape.radius = maxf(approach_radius, 0.0)

func _on_approach_body_entered(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_wanderer_inside = true

func _on_approach_body_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_wanderer_inside = false
		_line_said = false

# Frozen with the field, so nothing is said over a fight or a screen.
func _physics_process(_delta: float) -> void:
	if _wanderer_inside and not _line_said:
		_line_said = true
		_say(world_line)

func _ground_to_relief() -> void:
	if _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# Whether the Wanderer at `from` is in reach (approach_radius, on the
# ground).
func can_open_from(from: Vector3) -> bool:
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

# The trough's click: a left click on the padded screen rect with the
# Wanderer in reach asks to open; anything else falls through to the
# field's move click. The field's freeze stops this with everything else.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null or region_field.wanderer == null:
		return
	if not can_open_from(region_field.wanderer.global_position):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var rect: Rect2 = get_screen_rect(camera, region_field.click_target_padding_px)
	if rect.size == Vector2.ZERO or not rect.has_point(button.position):
		return
	get_viewport().set_input_as_handled()
	open_requested.emit(self)

func _say(text: String) -> void:
	if text.is_empty():
		return
	var region_field := get_node_or_null(region_field_path) as Node
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	var line := WorldVoiceLine.on_hud(hud)
	if line == null:
		push_warning("Collector '%s': no FieldHUD to show its world line on." % name)
		return
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	line.show_line_near(text, hold_seconds, self, Vector3.UP * (body_height + line_clearance_m))

# The body's box on screen, grown by padding_px - TroughProp.get_screen_
# rect()'s padded rect.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or not is_inside_tree():
		return Rect2()
	var half_length: float = maxf(body_length, body_height) * 0.5
	var box := AABB(Vector3(-body_height * 0.5, 0.0, -half_length), Vector3(body_height, body_height, half_length * 2.0))
	var to_world: Transform3D = global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * box.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)
