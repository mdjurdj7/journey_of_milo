extends Node3D
class_name Collector

# The collector: a creature still fetching, sorting and handing things
# over, long after the people it did it for left (05_REGION_01 §9 Shop).
# It is not waiting for the Wanderer - it faces its own yaw, never turns
# toward him, never greets, never thanks. Placed from data (a FloorProp:
# position, yaw, world_line, pool; anything else through overrides) -
# nothing floor-specific is in collector.tscn.
#
# The body is model_scene_path on its own colour map (colour_map_path)
# under the painted shader, with the enemy_fog pass laid over it at
# fog_factor (PaintedProp, as the Handcart wears it) - an enemy's share
# of the fog, not a prop's. The model's own frame: feet at y 0 (grounded
# by its box), head along +Z, tail along -Z; the FloorProp's yaw turns
# it. Origin grounded on the relief; a contact pool sized to the box; one
# capsule StaticBody3D along the body, tail tip to nose, the box's
# half-width round - over all four legs - that the Wanderer walks round.
# No idle animation.
#
# The floor 2 trough's trigger, shared through PropApproach: inside
# approach_radius the world line shows near the body, once per visit into
# the radius; a left click on the body's padded screen rect with the
# Wanderer in reach emits open_requested, for RegionField to open the
# collector's screen with the field locked. Anything else falls through
# to the field's move click. On the run's first visit to any collector,
# hint_line follows the world line, hint_gap_seconds after it has faded -
# a word about the healing it always stocks, which floor 4's pup needs
# (DunecurPup). It never names the card, so a rename changes nothing.
# Once per run: a static flag, cleared by RunState.new_run() through
# reset_hint(); a hint cut off by a screen opening waits for the next
# visit.
#
# What it hands over (CollectorScreen), rolled once as the floor loads
# from the run's generator (RunState.rng) and never restocked - the same
# stock, minus what was bought, for as long as the floor lasts - so the
# field can show it before the screen opens:
#   class_card_count cards of the run's class from its reward pool
#     (RegionField.run_reward_pool(), neutrals left out) and neutral_card_
#     count from the neutral pool, each tier first at the floor's own
#     fight rates (RegionField.fight_rarity_rates());
#   one fixed_card (Samphire), one copy;
#   the Bedroll (bedroll_path), one - the screen lists it only while none
#     is carried;
#   one worn piece and one keepsake from the shop's own tables (worn_
#     table_path, keepsake_table_path - never the piece already held);
#   with weapon_chance, one weapon of weapon_paths for the run's class
#     (WeaponData.card_class), never the one carried;
#   and one removal, once.
# A stocked weapon with a model (weapon_display_paths) lies on the sand
# beside it (CollectorDisplay) - display_offset from it, turned display_
# rotation_degrees, display_length_m long - until it is bought.
# Every price is an export, overridable per floor through the FloorProp's
# overrides; a change re-prices an open screen (prices_changed). State
# lives on this node: a new floor is a new node.

signal open_requested(collector: Collector)
# A price changed (an export set live) - an open screen redraws.
signal prices_changed()

const GROUP := &"collectors"

@export_group("Body")
@export_file("*.glb", "*.tscn") var model_scene_path: String = "res://assets/models/collector/collector.glb":
	set(value):
		model_scene_path = value
		_rebuild_body()
# The model's own colour map: its glb's albedo, extracted once on import
# (the glb's other maps are discarded - the painted shader takes none).
@export_file("*.jpg", "*.png") var colour_map_path: String = "res://assets/models/collector/collector_texture_0.png":
	set(value):
		colour_map_path = value
		_rebuild_body()
@export var model_scale: float = 1.0:
	set(value):
		model_scale = value
		_rebuild_body()
# Multiplied into the colour map - white is the map as painted.
@export var tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		tint = value
		_apply_tint()
# Its share of the depth fog - an enemy's (RegionField.enemy_fog_factor).
@export_range(0.0, 1.0, 0.01) var fog_factor: float = 0.4:
	set(value):
		fog_factor = value
		_push_fog()
@export_group("")

@export_group("Approach")
# From the origin (between its legs): reach past the nose (1.22 m out)
# with room for the Wanderer to stand clear of the head.
@export var approach_radius: float = 3.0:
	set(value):
		approach_radius = value
		_apply_approach_radius()
# Set from FloorProp.world_line by RegionField; this is the placeholder.
@export_multiline var world_line: String = "It is sorting what it has."
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
# Metres above the body's top the line is anchored at.
@export var line_clearance_m: float = 0.6
@export_multiline var hint_line: String = "Keeps a thing alive out here."
@export var hint_gap_seconds: float = 0.4
@export_group("")

@export_group("Stock")
@export var class_card_count: int = 1
@export var neutral_card_count: int = 1
@export_file("*.tres") var neutral_pool_path: String = "res://cards/pools/neutral_pool.tres"
# Always stocked beside the roll, one copy, at fixed_price (collector.tscn
# sets Samphire). Null = no fixed slot.
@export var fixed_card: CardData = null
# The Bedroll, one, at bedroll_price. Empty = none.
@export_file("*.tres") var bedroll_path: String = "res://run/data/bedroll.tres"
# The shop's own equipment pool: a worn piece and a keepsake from these
# tables (KeepsakeTable.roll()), and with weapon_chance one of these
# weapons.
@export_file("*.tres") var worn_table_path: String = "res://run/shop/shop_worn.tres"
@export_file("*.tres") var keepsake_table_path: String = "res://run/shop/shop_keepsakes.tres"
@export var weapon_paths: PackedStringArray = PackedStringArray(["res://run/weapons/gaff_hook.tres"])
@export_range(0.0, 1.0, 0.01) var weapon_chance: float = 0.35
@export_group("")

@export_group("Display")
# A stocked weapon's model on the sand, weapon_paths' order (empty: none
# shown), on its colour map (weapon_display_colour_maps).
@export var weapon_display_paths: PackedStringArray = PackedStringArray(["res://assets/models/weapons/gaff_hook/gaff_hook.glb"]):
	set(value):
		weapon_display_paths = value
		_apply_display()
@export var weapon_display_colour_maps: PackedStringArray = PackedStringArray(["res://assets/models/weapons/gaff_hook/gaff_hook_0.jpg"]):
	set(value):
		weapon_display_colour_maps = value
		_apply_display()
# Where it lies: this far from the collector in world axes (XZ - Y from
# the relief), turned (degrees, YXZ - X -90 lays an upright model down),
# this long end to end (CollectorDisplay measures the model's own length,
# however it lies in its box). Floors set their own through the FloorProp's
# overrides.
@export var display_offset: Vector3 = Vector3(3.0, 0.0, 2.9):
	set(value):
		display_offset = value
		_apply_display()
@export var display_rotation_degrees: Vector3 = Vector3(-90.0, 150.0, 0.0):
	set(value):
		display_rotation_degrees = value
		_apply_display()
@export var display_length_m: float = 1.2:
	set(value):
		display_length_m = value
		_apply_display()
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
@export var bedroll_price: int = 45:
	set(value):
		bedroll_price = value
		prices_changed.emit()
@export var worn_price: int = 85:
	set(value):
		worn_price = value
		_reprice_goods()
@export var keepsake_price: int = 75:
	set(value):
		keepsake_price = value
		_reprice_goods()
@export var weapon_price: int = 110:
	set(value):
		weapon_price = value
		_reprice_goods()
@export_group("")
# Set by RegionField._spawn_floor_props(): the floor's path plus the
# prop's index.
@export var collector_id: String = ""
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

var _placement_yaw: float = 0.0
var _model: Node3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _sky: RegionSky = null
# The model's box in this node's frame, feet at y 0.
var _aabb: AABB = AABB()
var _collision_body: StaticBody3D = null
var _contact_shadow: ContactShadow = null
# The stocked weapon on the sand, while one is (_apply_display()).
var _display: CollectorDisplay = null
var _approach: PropApproach = null
var _ground: Ground = null
# hint_line has been said this run.
static var _hint_said: bool = false

static func reset_hint() -> void:
	_hint_said = false

# The rolled stock, a null where a card was bought; rolled once.
var _stock: Array[CardData] = []
var _rolled: bool = false
var _fixed_taken: bool = false
var _removal_used: bool = false
# The rolled equipment (CollectorGood, priced by kind), and the indices
# already taken.
var _goods: Array[CollectorGood] = []
var _goods_taken: Dictionary = {}
var _bedroll: BedrollData = null
var _bedroll_taken: bool = false
# The screen's first open on this floor wrote its collector_stock line.
var _stock_logged: bool = false

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
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	_push_fog()
	_contact_shadow = ContactShadow.new()
	_contact_shadow.name = "ContactShadow"
	_contact_shadow.feet_source = _contact_feet
	add_child(_contact_shadow)
	_apply_shadow_footprint()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Collector '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_contact_shadow.set_ground(_ground)
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()
	# The stock, once the floor is up, so the sand can show it.
	_roll_on_load.call_deferred()

func _roll_on_load() -> void:
	ensure_stock()
	_apply_display()

# The model, dressed, its feet on the origin by its box, and the capsule
# round it.
func _spawn_body() -> void:
	var scene := load(model_scene_path) as PackedScene
	if scene == null:
		push_warning("Collector '%s': could not load %s; no body." % [name, model_scene_path])
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_model.scale = Vector3.ONE * model_scale
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
	_model.position.y -= _aabb.position.y
	_aabb.position.y = 0.0
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# RegionField's freeze would otherwise take the body out of the
	# physics space (the trough's reason).
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	# Along the body's Z, end to end over the box's length, its radius the
	# box's widest half - the legs, the packs and the tail inside it.
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(_aabb.size.x * 0.5, 0.01)
	capsule.height = maxf(_aabb.size.z, capsule.radius * 2.0)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = capsule
	var centre: Vector3 = _aabb.get_center()
	shape_node.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(centre.x, capsule.radius, centre.z))
	_collision_body.add_child(shape_node)
	add_child(_collision_body)

# A new model, colour map or scale: the body, its capsule and its pool
# again.
func _rebuild_body() -> void:
	if not is_inside_tree():
		return
	if _model != null:
		_model.free()
		_model = null
	if _collision_body != null:
		_collision_body.free()
		_collision_body = null
	_spawn_body()
	_push_fog()
	_apply_shadow_footprint()

# A painted material's albedo_tint, the flat fallback's albedo_color.
func _apply_tint() -> void:
	if _material is ShaderMaterial:
		(_material as ShaderMaterial).set_shader_parameter("albedo_tint", tint)
	elif _material is BaseMaterial3D:
		(_material as BaseMaterial3D).albedo_color = tint

func _push_fog() -> void:
	PaintedProp.push_fog(_fog, _sky, fog_factor)
	if _display != null:
		_display.push_fog(_sky, fog_factor)

# The pool's radii: the box's half-extents across and along the body.
func _apply_shadow_footprint() -> void:
	if _contact_shadow != null and _aabb.size != Vector3.ZERO:
		_contact_shadow.footprint = Vector2(_aabb.size.x, _aabb.size.z) * 0.5

# Under the middle of the box, at its feet (ContactShadow.feet_source).
func _contact_feet() -> Vector3:
	var centre: Vector3 = _aabb.get_center()
	return global_transform * Vector3(centre.x, 0.0, centre.z)

# The walk-up and the click (PropApproach): the line near the body once
# per visit; a click on the body in reach asks to open.
func _spawn_approach() -> void:
	_approach = PropApproach.new()
	_approach.name = "Approach"
	_approach.warning_label = "Collector"
	_approach.on_visit = _on_visit
	_approach.can_open_from = can_open_from
	_approach.screen_rect = get_screen_rect
	_approach.open_requested.connect(func() -> void: open_requested.emit(self))
	add_child(_approach)
	_apply_approach_radius()

func _apply_approach_radius() -> void:
	if _approach != null:
		_approach.set_radius(approach_radius)

# The visit's line, and on the run's first visit the hint after it.
func _on_visit() -> void:
	_say(world_line)
	if not _hint_said and not hint_line.is_empty():
		_hint_said = true
		_say_hint_after()

# hint_line once the world line has faded and hint_gap_seconds more - if
# the field is still live then (no screen open); else it waits for the
# next visit.
func _say_hint_after() -> void:
	var region_field: Node = get_node_or_null(region_field_path)
	var voice := WorldVoiceLine.on_hud(region_field.get_node_or_null(^"FieldHUD") if region_field != null else null)
	if voice != null and voice.is_speaking():
		await voice.line_finished
	await get_tree().create_timer(hint_gap_seconds).timeout
	if not is_inside_tree() or not can_process():
		_hint_said = false
		return
	_say(hint_line)

func _ground_to_relief() -> void:
	if _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))
	_apply_display()

# Whether the Wanderer at `from` is in reach (approach_radius, on the
# ground).
func can_open_from(from: Vector3) -> bool:
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

# --- Stock ---

# For probes that change what the roll reads (weapon_chance, the pieces
# held) after the floor has loaded: the stock rolled again.
func reroll_stock() -> void:
	_rolled = false
	ensure_stock()
	_apply_display()

# The roll, on the first call only (the floor's load): the class cards,
# the neutral cards, the worn piece, the keepsake, then the weapon's
# chance - in that order, from the run's generator.
func ensure_stock() -> void:
	if _rolled:
		return
	_rolled = true
	_stock.clear()
	_goods.clear()
	_goods_taken.clear()
	var rng: RandomNumberGenerator = RunState.rng
	var character: CharacterData = RunState.character
	var region_field := get_node_or_null(region_field_path) as RegionField
	var rates: RarityRates = region_field.fight_rarity_rates() if region_field != null else null
	var class_pool: RewardPool = region_field.run_reward_pool(region_field.get_floor_data()) if region_field != null else null
	if class_pool != null:
		_stock.append_array(class_pool.roll_by_rarity(class_card_count, rng, null, false, character, rates, true))
	else:
		push_warning("Collector '%s': no class reward pool; no class card." % name)
	var neutral_pool: RewardPool = load(neutral_pool_path) as RewardPool if not neutral_pool_path.is_empty() else null
	if neutral_pool != null:
		_stock.append_array(neutral_pool.roll_by_rarity(neutral_card_count, rng, null, false, character, rates))
	_bedroll = load(bedroll_path) as BedrollData if not bedroll_path.is_empty() else null
	_add_good(_roll_table(worn_table_path, rng, RunState.worn))
	_add_good(_roll_table(keepsake_table_path, rng, RunState.keepsake))
	if rng.randf() < weapon_chance:
		_add_good(_roll_weapon(rng, character))
	_reprice_goods()
	var names: Array[String] = []
	for card in _stock:
		names.append(card.card_name)
	for good in _goods:
		names.append(str(good.item.get("display_name")))
	print("Collector '%s': stock %s." % [name, ", ".join(names)])

# One trinket from the table at `path`, never `held`; null with none.
func _roll_table(path: String, rng: RandomNumberGenerator, held: TrinketData) -> Resource:
	var table: KeepsakeTable = load(path) as KeepsakeTable if not path.is_empty() else null
	if table == null:
		return null
	return table.roll(rng, held, RunState.keepsakes_offered)

# One of weapon_paths for `character`'s class (or any class), never the
# one carried; null with none.
func _roll_weapon(rng: RandomNumberGenerator, character: CharacterData) -> Resource:
	var candidates: Array[WeaponData] = []
	for path in weapon_paths:
		var weapon := load(path) as WeaponData
		if weapon == null or weapon == RunState.weapon:
			continue
		if weapon.card_class != &"" and (character == null or weapon.card_class != character.card_class):
			continue
		candidates.append(weapon)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _add_good(item: Resource) -> void:
	if item == null:
		return
	var good := CollectorGood.new()
	good.item = item
	if good.is_valid():
		_goods.append(good)

# Each good at its kind's price.
func _reprice_goods() -> void:
	for good in _goods:
		good.price = good_price(good)
	prices_changed.emit()

# A good's price, by its kind: worn_price, keepsake_price, weapon_price.
func good_price(good: CollectorGood) -> int:
	if good == null:
		return 0
	if good.get_weapon() != null:
		return weapon_price
	return worn_price if good.get_trinket().slot == TrinketData.Slot.WORN else keepsake_price

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

# The goods in their slots, a null for each one taken.
func get_goods() -> Array[CollectorGood]:
	var shown: Array[CollectorGood] = []
	for index in _goods.size():
		shown.append(_goods[index] if not _goods_taken.has(index) else null)
	return shown

func take_good(index: int) -> void:
	if index >= 0 and index < _goods.size():
		_goods_taken[index] = true
	_apply_display()

# The first stocked, untaken weapon with a model (weapon_display_paths),
# on the sand at display_offset - or none.
func _apply_display() -> void:
	if not is_inside_tree():
		return
	var model_path: String = ""
	var colour_map: String = ""
	for good in get_goods():
		var weapon: WeaponData = good.get_weapon() if good != null else null
		if weapon == null:
			continue
		var index: int = weapon_paths.find(weapon.resource_path)
		if index >= 0 and index < weapon_display_paths.size() and not weapon_display_paths[index].is_empty():
			model_path = weapon_display_paths[index]
			colour_map = weapon_display_colour_maps[index] if index < weapon_display_colour_maps.size() else ""
			break
	if model_path.is_empty():
		if _display != null:
			_display.queue_free()
			_display = null
		return
	if _display == null:
		_display = CollectorDisplay.new()
		_display.name = "Display"
		add_child(_display)
		_display.set_ground(_ground)
	if not _display.dress(model_path, colour_map):
		_display.queue_free()
		_display = null
		return
	_display.push_fog(_sky, fog_factor)
	_display.place(global_position + Vector3(display_offset.x, 0.0, display_offset.z), display_rotation_degrees, display_length_m)

# For probes: the weapon on the sand, or null.
func get_display() -> CollectorDisplay:
	return _display

# The Bedroll stocked, until it is bought; null with none or once taken.
func get_bedroll() -> BedrollData:
	return _bedroll if not _bedroll_taken else null

func take_bedroll() -> void:
	_bedroll_taken = true

func is_removal_used() -> bool:
	return _removal_used

func use_removal() -> void:
	_removal_used = true

# True on the first call only - the screen's first open on this floor
# logs the stock (CollectorScreen._log_stock()).
func claim_stock_log() -> bool:
	if _stock_logged:
		return false
	_stock_logged = true
	return true

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
		_approach.say_near(text, hold_seconds, fade_seconds, self, Vector3.UP * (_aabb.end.y + line_clearance_m))

# The model's box on screen, grown by padding_px - TroughProp.get_screen_
# rect()'s padded rect.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or not is_inside_tree() or _aabb.size == Vector3.ZERO:
		return Rect2()
	var box: AABB = _aabb
	var to_world: Transform3D = global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * box.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)
