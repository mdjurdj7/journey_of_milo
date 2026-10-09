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
# The floor 2 trough's trigger, shared through PropApproach: inside
# approach_radius the world line shows near the body, once per visit into
# the radius; a left click on the body's padded screen rect with the
# Wanderer in reach emits open_requested, for RegionField to open the
# collector's screen with the field locked. Anything else falls through
# to the field's move click.
#
# What it hands over (CollectorScreen): stock_count cards rolled from
# stock_pool, tier first at the pool's own rates (RewardPool.roll_by_
# rarity()) from the run's generator, on the first open - then the same
# stock, minus what was bought, for as long as the floor lasts; never
# restocked. Beside them one fixed_card (Samphire), one copy. And one
# removal, once. Every price is an export, overridable per floor through
# the FloorProp's overrides; a change re-prices an open screen
# (prices_changed). State lives on this node: a new floor is a new node.

signal open_requested(collector: Collector)
# A price changed (an export set live) - an open screen redraws.
signal prices_changed()

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

@export_group("Stock")
@export var stock_count: int = 5
# Always stocked beside the roll, one copy, at fixed_price (collector.tscn
# sets Samphire). Null = no fixed slot.
@export var fixed_card: CardData = null
@export_group("")

@export_group("Prices")
@export var price_common: int = 40:
	set(value):
		price_common = value
		prices_changed.emit()
@export var price_uncommon: int = 55:
	set(value):
		price_uncommon = value
		prices_changed.emit()
@export var price_rare: int = 80:
	set(value):
		price_rare = value
		prices_changed.emit()
@export var price_ultra_rare: int = 120:
	set(value):
		price_ultra_rare = value
		prices_changed.emit()
@export var fixed_price: int = 8:
	set(value):
		fixed_price = value
		prices_changed.emit()
@export var removal_price: int = 50:
	set(value):
		removal_price = value
		prices_changed.emit()
@export_group("")
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
var _approach: PropApproach = null
var _ground: Ground = null
# The rolled stock, a null where a card was bought; rolled once.
var _stock: Array[CardData] = []
var _rolled: bool = false
var _fixed_taken: bool = false
var _removal_used: bool = false

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
	_spawn_approach()
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

# The walk-up and the click (PropApproach): the line near the body once
# per visit; a click on the body in reach asks to open.
func _spawn_approach() -> void:
	_approach = PropApproach.new()
	_approach.name = "Approach"
	_approach.warning_label = "Collector"
	_approach.on_visit = func() -> void: _say(world_line)
	_approach.can_open_from = can_open_from
	_approach.screen_rect = get_screen_rect
	_approach.open_requested.connect(func() -> void: open_requested.emit(self))
	add_child(_approach)
	_apply_approach_radius()

func _apply_approach_radius() -> void:
	if _approach != null:
		_approach.set_radius(approach_radius)

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

# --- Stock ---

# The roll, on the first call only (the first open).
func ensure_stock() -> void:
	if _rolled:
		return
	_rolled = true
	_stock.clear()
	if stock_pool == null:
		push_warning("Collector '%s': no stock pool; nothing rolled." % name)
		return
	_stock = stock_pool.roll_by_rarity(stock_count, RunState.rng)
	var names: Array[String] = []
	for card in _stock:
		names.append(card.card_name)
	print("Collector '%s': stock %s." % [name, ", ".join(names)])

# The rolled stock in its slots, a null for each one bought.
func get_stock() -> Array[CardData]:
	return _stock.duplicate()

func take_stock(index: int) -> void:
	if index >= 0 and index < _stock.size():
		_stock[index] = null

func is_fixed_available() -> bool:
	return fixed_card != null and not _fixed_taken

func take_fixed() -> void:
	_fixed_taken = true

func is_removal_used() -> bool:
	return _removal_used

func use_removal() -> void:
	_removal_used = true

# A rolled card's price, by its rarity (an untagged card at Common's).
func price_of(card: CardData) -> int:
	match card.rarity:
		CardData.CardRarity.UNCOMMON:
			return price_uncommon
		CardData.CardRarity.RARE:
			return price_rare
		CardData.CardRarity.ULTRA_RARE:
			return price_ultra_rare
	return price_common

func _say(text: String) -> void:
	if _approach != null:
		_approach.say_near(text, hold_seconds, fade_seconds, self, Vector3.UP * (body_height + line_clearance_m))

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
