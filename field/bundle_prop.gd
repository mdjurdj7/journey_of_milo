extends Node3D
class_name BundleProp

# A bundle set down on the sand, tied shut, with one thing inside. What
# that is gets rolled once, when the floor loads (RegionField._setup_
# bundle() calls roll() from the run's own generator): gold_chance gold,
# card_chance a card from the prop's pool, the rest a card from the
# floor's rare_pool. It never changes after that - leaving the loot window
# and coming back shows the same thing.
#
# The belongings card's distance language: inside approach_radius (2.5,
# WorldCard.lift_radius and Hull.approach_radius alike) the world line
# shows once, and a left click on the bundle opens the loot window
# (RegionField._unhandled_input() -> LootScreen). A click from further out
# is an ordinary move click and walks the Wanderer to it.
#
# Taken: the bundle stays where it is, a step darker (opened_tint), and
# is silent from then on - no line, no click. The glb is one static mesh
# with no opened pose, so darker and still is the whole of "opened".
#
# Loads bundle.glb (0.60 m tall, origin at its base, measured from the
# vertex data) under this node on the flat matte material the hulls use,
# duplicated and tinted - the glb's own textures are ignored, as the
# hull's are. Grounded by its AABB anyway, so a re-export with a moved
# origin still sits on the sand.

const MODEL_SCENE_PATH := "res://assets/models/props/bundle/bundle.glb"
const GROUP := &"bundles"

enum Contents { NONE, GOLD, CARD, RARE_CARD }

@export_group("Model")
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
# A step darker than the sand, the hulls' own tint.
@export var bundle_tint: Color = Color(0.50, 0.47, 0.42):
	set(value):
		bundle_tint = value
		_apply_tint()
# Once taken - a step darker again.
@export var opened_tint: Color = Color(0.42, 0.39, 0.35):
	set(value):
		opened_tint = value
		_apply_tint()
# A cylinder round the sack so the Wanderer walks round it, not through.
@export var collision_radius: float = 0.26:
	set(value):
		collision_radius = value
		_apply_collision()
@export_group("")

@export_group("Contents")
# Read by roll() when the floor loads; editing them afterwards changes
# the next roll, never what is already inside.
@export_range(0.0, 1.0) var gold_chance: float = 0.80
@export_range(0.0, 1.0) var card_chance: float = 0.15
# On the floor's own gold range (FloorData.gold_min/gold_max).
@export var gold_multiplier: float = 1.5
@export_group("")

@export_group("Approach")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		_apply_approach_radius()
@export_multiline var world_line: String = "Tied shut. Not recently."
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# What is inside, set by roll(). contents_card is null for gold.
var contents: int = Contents.NONE
var contents_gold: int = 0
var contents_card: CardData = null
var is_opened: bool = false

var _model: Node3D = null
var _material: StandardMaterial3D = null
# The model's combined bbox in this node's space, bottom on the origin.
var _aabb: AABB = AABB()
var _collision_body: StaticBody3D = null
var _collision_shape: CylinderShape3D = null
var _collision_shape_node: CollisionShape3D = null
var _approach_area: Area3D = null
var _approach_shape: SphereShape3D = null
var _ground: Ground = null
# The line is said once. The bundle only exists on its own floor, which a
# run doesn't revisit, so a node-local flag is once per run.
var _line_shown: bool = false

# The one roll: which kind, then what. `pool` is the prop's own (the
# belongings pool), `rare_pool` the floor's - null or empty falls back to
# `pool`, the kind is still RARE_CARD. A card roll that comes back empty
# falls back to gold with a warning, so the bundle is never empty.
func roll(rng: RandomNumberGenerator, gold_min: int, gold_max: int, pool: RewardPool, rare_pool: RewardPool) -> void:
	var point: float = rng.randf()
	if point >= gold_chance:
		var rare: bool = point >= gold_chance + card_chance
		var from: RewardPool = pool
		if rare and rare_pool != null and not rare_pool.entries.is_empty():
			from = rare_pool
		if from != null:
			var rolled: Array[CardData] = from.roll(1, rng, null)
			if not rolled.is_empty():
				contents = Contents.RARE_CARD if rare else Contents.CARD
				contents_card = rolled[0]
				contents_gold = 0
				return
		push_warning("BundleProp '%s': no card to roll; gold instead." % name)
	var base: int = rng.randi_range(mini(gold_min, gold_max), maxi(gold_min, gold_max))
	contents = Contents.GOLD
	contents_gold = maxi(roundi(float(base) * gold_multiplier), 1)
	contents_card = null

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief, yaw onto yaw_degrees; a bundle doesn't roll.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	add_to_group(GROUP)
	_spawn_model()
	_spawn_approach_area()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("BundleProp '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_model() -> void:
	var scene := load(MODEL_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("BundleProp: could not load %s; no model." % MODEL_SCENE_PATH)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply_tint()

	var has_aabb := false
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mi_aabb: AABB = (_model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		_aabb = mi_aabb if not has_aabb else _aabb.merge(mi_aabb)
		has_aabb = true
	if has_aabb:
		_model.position.y = -_aabb.position.y
		_aabb.position.y = 0.0
	print("BundleProp '%s': bbox %.2f x %.2f high x %.2f" % [name, _aabb.size.x, _aabb.size.y, _aabb.size.z])
	_apply_collision()

func _apply_tint() -> void:
	if _material != null:
		_material.albedo_color = opened_tint if is_opened else bundle_tint

# MAKE_STATIC for the same reason as the hull's: RegionField's freeze
# (a battle, the loot window itself) would otherwise take the body out
# of the physics space, and a click would fall through to the sand.
func _apply_collision() -> void:
	if _model == null or _aabb.size == Vector3.ZERO:
		return
	if _collision_body == null:
		_collision_body = StaticBody3D.new()
		_collision_body.name = "Collision"
		_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
		_collision_shape = CylinderShape3D.new()
		_collision_shape_node = CollisionShape3D.new()
		_collision_shape_node.shape = _collision_shape
		_collision_body.add_child(_collision_shape_node)
		add_child(_collision_body)
	_collision_shape.radius = maxf(collision_radius, 0.01)
	_collision_shape.height = maxf(_aabb.size.y, 0.01)
	_collision_shape_node.position = Vector3(_aabb.get_center().x, _aabb.size.y * 0.5, _aabb.get_center().z)

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

func _apply_approach_radius() -> void:
	if _approach_shape != null:
		_approach_shape.radius = maxf(approach_radius, 0.0)

func _on_approach_body_entered(body: Node3D) -> void:
	if is_opened or _line_shown or world_line.is_empty() or not body.is_in_group("wanderer"):
		return
	var region_field := get_node_or_null(region_field_path) as Node
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	var line := WorldVoiceLine.on_hud(hud)
	if line == null:
		push_warning("BundleProp '%s': no FieldHUD to show its world line on." % name)
		return
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	line.show_line(world_line, hold_seconds)
	_line_shown = true

func _ground_to_relief() -> void:
	if _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# Whether a click from `from` (the Wanderer's position) opens it: not yet
# taken, something inside, and within approach_radius on the ground.
func can_open_from(from: Vector3) -> bool:
	if is_opened or contents == Contents.NONE:
		return false
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

# The model's bbox on screen, grown by padding_px - the same padded rect
# a FieldEnemy offers RegionField's click test (FieldEnemy.get_screen_
# rect()), so a small thing on the sand is as easy to click as an enemy.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _aabb.size == Vector3.ZERO:
		return Rect2()
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = global_transform * _aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)

# Called by the loot window once its contents have been taken.
func mark_taken() -> void:
	is_opened = true
	_apply_tint()
