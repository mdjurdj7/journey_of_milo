extends Node3D
class_name TroughProp

# A stone trough of still water, cut and left - one drink in it. Floor 2
# puts it at the centre of the dragonflies' island, and it stays inert
# while they hold it: until every FieldEnemy in guard_group is defeated,
# walking up says nothing and a click on it is an ordinary move click.
# The group is read live every tick (FieldEnemy.is_defeated() is set on
# each kill, RegionField._on_enemy_defeated()), so the trough wakes the
# moment the last of them falls - no reload, and a Wanderer who won the
# fight standing beside it hears its line without stepping out and back.
#
# Awake, the belongings bundle's distance language (BundleProp): inside
# approach_radius the world line shows - approach_line while the water
# is there, return_line once it has been drunk - once per visit into the
# radius, as the Keeper's does; and a left click on the trough in reach
# opens its choice (TroughChoice, beside the trough on FieldHUD, the
# field live under it). Drink heals heal_amount through RunState.heal()
# (capped at max HP, allowed at full), says drunk_line and spends it;
# Leave it closes and changes nothing, and the next click opens it again.
#
# Once per run: drunk ids live in a static set keyed by trough_id (the
# floor's path#index, set by RegionField._spawn_floor_props()) - a floor
# can come round again in the same run (the region wraps back to floor
# 1), and a node-local flag would refill the trough on the reload.
# Cleared by RunState.new_run() via reset_drunk().
#
# The model is Water Shrine.glb at its own size (1.00 x 1.20 high x 1.02
# m, origin at the base centre; a basin at +Z with its rim at 0.38 m, a
# back slab at -Z to 1.2 m) in its own texture, the water painted into
# it - the textured treatment FieldEnemy._build_model_material() gives an
# enemy: the imported material kept, roughness 1, no metallic. Grounded
# by its bbox anyway, then sunk sink_depth into the sand and tilted
# tilt_degrees, its raised edge toward tilt_direction_degrees.

const MODEL_SCENE_PATH := "res://assets/Environment/Shrine/Water Shrine.glb"
const CHOICE_SCENE_PATH := "res://battle/trough_choice.tscn"
const GROUP := &"troughs"

@export_group("Model")
# The trough's own facing, on top of the FloorProp's yaw_degrees: at 0
# the basin faces +Z (seaward) and the back slab -Z (inland). 150 is the
# yaw that least often puts the island pack's battle line inside it.
@export var trough_yaw_degrees: float = 150.0:
	set(value):
		trough_yaw_degrees = value
		_apply_yaw()
@export var sink_depth: float = 0.1:
	set(value):
		sink_depth = value
		_apply_pose()
@export var tilt_degrees: float = 3.5:
	set(value):
		tilt_degrees = value
		_apply_pose()
# Which edge the tilt raises, degrees round the trough's own up axis
# from its front (the basin, +Z): 0 = the front lip up, 180 = the back.
# 180 with yaw 150 is the pair the pack's line least often ends inside.
@export var tilt_direction_degrees: float = 180.0:
	set(value):
		tilt_direction_degrees = value
		_apply_pose()
@export_group("")

@export_group("Drink")
@export var heal_amount: int = 15
# What the island's pack is called (FloorEnemy.group); the trough wakes
# once none of it stands. Empty = awake from the start.
@export var guard_group: StringName = &"island"
@export_group("")

@export_group("Approach")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		_apply_approach_radius()
@export_multiline var approach_line: String = "Still water. Someone cut the stone to keep it."
@export_multiline var drunk_line: String = "Cold. It tastes of nothing."
@export_multiline var return_line: String = "The water settles again."
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
@export_group("")

# Set by RegionField._spawn_floor_props(): the floor's path plus the
# prop's index. Empty = derived from the floor and this node's name, see
# _trough_id().
@export var trough_id: String = ""
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# trough_id -> true once drunk this run.
static var _drunk: Dictionary = {}

static func reset_drunk() -> void:
	_drunk.clear()

var _placement_yaw: float = 0.0
# Pose carries the sink and the tilt; the model sits grounded under it.
var _pose: Node3D = null
var _model: Node3D = null
# The model's bbox in the model's own (untilted) space, bottom on 0.
var _model_aabb: AABB = AABB()
var _collision_body: StaticBody3D = null
var _collision_box: BoxShape3D = null
var _collision_shape_node: CollisionShape3D = null
var _approach_area: Area3D = null
var _approach_shape: SphereShape3D = null
var _ground: Ground = null
var _wanderer_inside: bool = false
# This visit's line has been said (reset on leaving the radius).
var _line_said: bool = false
var _choice: TroughChoice = null

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief; the entry's yaw on top of trough_yaw_degrees.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_placement_yaw = yaw
	_apply_yaw()

func _ready() -> void:
	add_to_group(GROUP)
	_apply_yaw()
	_spawn_model()
	_spawn_approach_area()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("TroughProp '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_model() -> void:
	var scene := load(MODEL_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("TroughProp: could not load %s; no model." % MODEL_SCENE_PATH)
		return
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_pose.add_child(_model)
	var material: BaseMaterial3D = null
	var has_aabb := false
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		if material == null:
			material = _build_model_material(mi)
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mi_aabb: AABB = (_model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		_model_aabb = mi_aabb if not has_aabb else _model_aabb.merge(mi_aabb)
		has_aabb = true
	if has_aabb:
		_model.position.y = -_model_aabb.position.y
		_model_aabb.position.y = 0.0
	print("TroughProp '%s': bbox %.2f x %.2f high x %.2f" % [name, _model_aabb.size.x, _model_aabb.size.y, _model_aabb.size.z])
	_apply_pose()

# FieldEnemy._build_model_material()'s recipe: the imported material
# duplicated (its albedo and normal maps kept), forced to the project's
# matte - roughness 1, no metallic or specular, the metallic/roughness
# map cleared so the scalars hold. A flat white fill if the mesh has no
# material of its own.
func _build_model_material(mesh_instance: MeshInstance3D) -> BaseMaterial3D:
	var source_material := mesh_instance.get_active_material(0)
	var material: BaseMaterial3D
	if source_material is BaseMaterial3D:
		material = (source_material as BaseMaterial3D).duplicate()
	else:
		push_warning("TroughProp '%s': the model has no material of its own; flat white." % name)
		material = StandardMaterial3D.new()
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.metallic_texture = null
	material.roughness_texture = null
	return material

func _apply_yaw() -> void:
	rotation = Vector3(0.0, deg_to_rad(trough_yaw_degrees + _placement_yaw), 0.0)

# The sink and the tilt on Pose, round the trough's base centre: the
# edge toward tilt_direction_degrees rises, the opposite one dips.
func _apply_pose() -> void:
	if _pose == null:
		return
	var direction := Vector3(sin(deg_to_rad(tilt_direction_degrees)), 0.0, cos(deg_to_rad(tilt_direction_degrees)))
	var axis: Vector3 = direction.cross(Vector3.UP).normalized()
	_pose.transform = Transform3D(Basis(axis, deg_to_rad(tilt_degrees)), Vector3(0.0, -sink_depth, 0.0))
	_apply_collision()

# A box round the model's footprint, from the sand up to its top - the
# Wanderer walks round it. MAKE_STATIC, the bundle's reason: RegionField's
# freeze would otherwise take the body out of the physics space. Enemies
# move by tween, never by physics, so it stands in nobody's patrol.
func _apply_collision() -> void:
	if _model == null or _model_aabb.size == Vector3.ZERO:
		return
	if _collision_body == null:
		_collision_body = StaticBody3D.new()
		_collision_body.name = "Collision"
		_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
		_collision_box = BoxShape3D.new()
		_collision_shape_node = CollisionShape3D.new()
		_collision_shape_node.shape = _collision_box
		_collision_body.add_child(_collision_shape_node)
		add_child(_collision_body)
	var height: float = maxf(_model_aabb.size.y - sink_depth, 0.01)
	_collision_box.size = Vector3(_model_aabb.size.x, height, _model_aabb.size.z)
	var centre: Vector3 = _model_aabb.get_center()
	_collision_shape_node.position = Vector3(centre.x, height * 0.5, centre.z)

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

# The line waits here rather than in body_entered: the Wanderer may be
# inside already when the guard falls (the fight was beside the trough).
# Frozen with the field, so nothing is said over a fight.
func _physics_process(_delta: float) -> void:
	if _wanderer_inside and not _line_said and is_awake():
		_line_said = true
		_say(return_line if is_drunk() else approach_line)

func _ground_to_relief() -> void:
	if _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# No member of guard_group still standing: not defeated, not on its way
# out - RegionField._required_enemy_remains()'s own test.
func is_awake() -> bool:
	if guard_group == &"":
		return true
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.group != guard_group:
			continue
		if not enemy.is_queued_for_deletion() and not enemy.is_defeated():
			return false
	return true

func is_drunk() -> bool:
	return _drunk.has(_trough_id())

# Whether the choice opens for the Wanderer at `from`: awake, not drunk,
# and within approach_radius on the ground.
func can_open_from(from: Vector3) -> bool:
	if is_drunk() or not is_awake():
		return false
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

# RegionField._try_open_bundle()'s click, for the trough: a left click
# on its padded screen rect with the Wanderer in reach opens the choice;
# a click on it while its choice is open changes nothing. Anything else
# falls through to the field's move click. The field's freeze stops
# this with everything else.
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
	if _choice != null and is_instance_valid(_choice):
		return
	_open_choice(region_field)

func _open_choice(region_field: RegionField) -> void:
	var hud := region_field.get_node_or_null(^"FieldHUD") as CanvasLayer
	if hud == null:
		push_warning("TroughProp '%s': FieldHUD not found; no choice." % name)
		return
	var scene := load(CHOICE_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("TroughProp '%s': could not load %s; no choice." % [name, CHOICE_SCENE_PATH])
		return
	_choice = scene.instantiate() as TroughChoice
	_choice.setup(self, region_field.wanderer, region_field)
	hud.add_child(_choice)

# Drink, from TroughChoice: the heal, the line, spent for the run. Only
# HP moves - Toll and Grace are not the trough's.
func drink() -> void:
	if is_drunk():
		return
	_drunk[_trough_id()] = true
	RunState.heal(heal_amount)
	print("TroughProp '%s': drank, +%d HP (now %d/%d)." % [name, heal_amount, RunState.player_hp, RunState.player_max_hp])
	_line_said = true
	_say(drunk_line)

func _say(text: String) -> void:
	if text.is_empty():
		return
	var region_field := get_node_or_null(region_field_path) as Node
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	var line := WorldVoiceLine.on_hud(hud)
	if line == null:
		push_warning("TroughProp '%s': no FieldHUD to show its world line on." % name)
		return
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	line.show_line(text, hold_seconds)

# trough_id if the spawner set one; else the floor's path plus this
# node's name, which RegionField makes from the prop's index.
func _trough_id() -> String:
	if not trough_id.is_empty():
		return trough_id
	var region_field := get_node_or_null(region_field_path) as RegionField
	var floor_data: FloorData = region_field.get_floor_data() if region_field != null else null
	return "%s:%s" % [floor_data.resource_path if floor_data != null else "", name]

# The model's tilted bbox on screen, grown by padding_px - BundleProp.
# get_screen_rect()'s padded rect.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _pose == null or _model_aabb.size == Vector3.ZERO:
		return Rect2()
	# _model_aabb is in Pose's space (the grounding shift is the model's
	# own position under it), so Pose carries it to the world, tilt and all.
	var to_world: Transform3D = _pose.global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * _model_aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)
