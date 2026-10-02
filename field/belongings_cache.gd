extends Node3D
class_name BelongingsCache

# Three things set down together - a case, a pack, a bedroll - and one
# choice between them, made on a screen (BelongingsScreen) rather than at
# the things themselves. The sand carries the three objects; the screen
# carries the choice, showing each object - what is in it shows only once
# it is taken.
#
# Each object holds one kind of thing, always the same one: the case
# coin (coin_amount), the pack a card from the prop's pool, the bedroll a
# keepsake from keepsake_table. The card, and whether one of the three
# also holds Glassbone (glassbone_chance, which one picked at random),
# are rolled once, when the floor loads (RegionField._spawn_floor_props()
# calls roll() from the run's own generator). The keepsake is drawn the
# first time the screen opens (ensure_keepsake()), as the Keeper draws
# hers, so it is never the one held by then. None of it changes after.
#
# Walking within trigger_radius of this node (on the ground plane) opens
# the screen through RegionField.open_belongings_screen(), once. Taking or
# declining spends the cache for the run - keyed by cache_id in a static
# set that survives the floor reload and is cleared by RunState.new_run(),
# as Hull's findings are. A take sinks that column's object (sink_taken_
# object); a decline leaves all three (sink_on_decline). Back on a spent
# cache's floor, the objects that sank stay gone and nothing opens.
#
# The objects are BelongingsObjects: the model on the hulls' flat
# material and tint, grounded by its bbox, solid, and inert - nothing
# opens them from the field and they say nothing. Object i is column i
# (BelongingsScreen.Slot): the case (the coin), the pack (the card), the
# bedroll (the keepsake).

@export_group("Objects")
# The three models, in column order: the case, the pack, the bedroll.
@export var object_scene_paths: PackedStringArray = PackedStringArray([
	"res://assets/models/props/belongings/case.glb",
	"res://assets/models/props/belongings/pack.glb",
	"res://assets/models/props/belongings/bedroll.glb",
]):
	set(value):
		object_scene_paths = value
		_respawn_objects()
# Each object's XZ offset from this node, in its own (yawed) frame, and
# its yaw - index i is column i's object.
@export var object_offsets: PackedVector2Array = PackedVector2Array([Vector2(0.0, 0.40), Vector2(-0.10, -0.25), Vector2(0.40, -0.10)]):
	set(value):
		object_offsets = value
		_place_objects()
@export var object_yaws_degrees: PackedFloat32Array = PackedFloat32Array([15.0, -20.0, 0.0]):
	set(value):
		object_yaws_degrees = value
		_place_objects()
# Each model's uniform scale, column order - the case at 0.6 so it is the
# smallest of the three, as a case beside a pack and a bedroll should be.
# The screen renders them at these scales too.
@export var object_scales: PackedFloat32Array = PackedFloat32Array([0.6, 1.0, 1.0]):
	set(value):
		object_scales = value
		for index in _objects.size():
			if _objects[index] != null and is_instance_valid(_objects[index]):
				_objects[index].model_scale = object_scale(index)
		_place_objects()
# The hulls' tint.
@export var object_tint: Color = Color(0.50, 0.47, 0.42):
	set(value):
		object_tint = value
		for object in _objects:
			if object != null and is_instance_valid(object):
				object.tint = object_tint
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
@export_group("")

@export_group("Choice")
# Metres on the ground from this node's centre at which the screen opens.
# Read every tick.
@export var trigger_radius: float = 1.5
# The line at the top of the screen - FloorProp.world_line replaces it
# when set.
@export_multiline var world_line: String = "Three packs, set down out of the wind. Nobody came back."
# Whether a take sinks the taken column's object, and whether a decline
# sinks all three. Read when the screen closes.
@export var sink_taken_object: bool = true
@export var sink_on_decline: bool = false
@export_group("")

@export_group("Contents")
# What the case holds. Read when the screen opens.
@export var coin_amount: int = 45
# What the bedroll draws from - never the keepsake held (KeepsakeTable.
# roll()). Read when the screen first opens.
@export var keepsake_table: KeepsakeTable = null
# The chance, per cache, that one of the three (any, equally) also holds
# glassbone_amount Glassbone, taken with it. The chance is read by roll(),
# the amount when the screen opens.
@export_range(0.0, 1.0, 0.01) var glassbone_chance: float = 0.25
@export var glassbone_amount: int = 1
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."
# What the once-per-run set keys this cache under. Set by RegionField to
# the floor resource's path plus the prop's index.
@export var cache_id: String = ""

# The card and glassbone_slot rolled by roll(), the keepsake by ensure_
# keepsake(). null = that column is left out; glassbone_slot is the column
# that also holds Glassbone, -1 for none.
var card: CardData = null
var keepsake: TrinketData = null
var glassbone_slot: int = -1

var _objects: Array[BelongingsObject] = []
var _wanderer: Node3D = null
var _opened: bool = false
var _keepsake_rolled: bool = false

# cache_id -> PackedInt32Array of the objects that sank. Present = spent.
static var _spent: Dictionary = {}

static func reset_spent() -> void:
	_spent.clear()

func roll(rng: RandomNumberGenerator, pool: RewardPool) -> void:
	var cards: Array[CardData] = []
	if pool != null:
		cards = pool.roll(1, rng, null)
	card = cards[0] if not cards.is_empty() else null
	if card == null:
		push_warning("BelongingsCache '%s': the pack's card rolled nothing; that column is left out." % name)
	var has_glassbone: bool = rng.randf() < glassbone_chance
	glassbone_slot = rng.randi_range(0, object_scene_paths.size() - 1) if has_glassbone else -1

# The bedroll's keepsake, drawn once, from the run's generator - never the
# keepsake held as the screen first opens.
func ensure_keepsake() -> void:
	if _keepsake_rolled:
		return
	roll_keepsake(RunState.rng, RunState.keepsake, RunState.keepsakes_offered)

func roll_keepsake(rng: RandomNumberGenerator, equipped: TrinketData, offered: Array[StringName]) -> void:
	_keepsake_rolled = true
	keepsake = keepsake_table.roll(rng, equipped, offered) if keepsake_table != null else null
	if keepsake == null:
		push_warning("BelongingsCache '%s': the bedroll's keepsake rolled nothing; that column is left out." % name)

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, the
# objects ground themselves; yaw onto yaw_degrees.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	_spawn_objects()

# The objects, one level below this node - so their ground path reaches
# one level further than this node's own. Those already sunk this run
# stay gone.
func _spawn_objects() -> void:
	var sunk: PackedInt32Array = PackedInt32Array()
	if _spent.has(cache_id):
		_opened = true
		sunk = _spent[cache_id]
	for index in object_scene_paths.size():
		if sunk.has(index):
			_objects.append(null)
			continue
		var object := BelongingsObject.new()
		object.name = "Object%d" % index
		object.model_scene_path = object_scene_paths[index]
		object.model_scale = object_scale(index)
		object.tint = object_tint
		object.ground_path = NodePath("../" + String(ground_path))
		add_child(object)
		_objects.append(object)
	_place_objects()

func object_scale(index: int) -> float:
	return object_scales[index] if index < object_scales.size() else 1.0

func _respawn_objects() -> void:
	if not is_inside_tree():
		return
	for object in _objects:
		if object != null and is_instance_valid(object):
			object.queue_free()
	_objects.clear()
	_spawn_objects()

func _place_objects() -> void:
	for index in _objects.size():
		var object: BelongingsObject = _objects[index]
		if object == null or not is_instance_valid(object) or index >= object_offsets.size():
			continue
		var offset: Vector2 = object_offsets[index]
		object.position = Vector3(offset.x, 0.0, offset.y)
		object.yaw_degrees = object_yaws_degrees[index] if index < object_yaws_degrees.size() else 0.0
		object.ground_to_relief()

func _physics_process(_delta: float) -> void:
	if _opened:
		return
	if _wanderer == null or not is_instance_valid(_wanderer):
		var found: Array[Node] = get_tree().get_nodes_in_group("wanderer")
		_wanderer = found[0] as Node3D if not found.is_empty() else null
		if _wanderer == null:
			return
	var offset := Vector3(_wanderer.global_position.x - global_position.x, 0.0, _wanderer.global_position.z - global_position.z)
	if offset.length() > trigger_radius:
		return
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null:
		return
	_opened = region_field.open_belongings_screen(self)

# Called by RegionField as the screen closes: `taken` is the column, or
# -1 for a decline. Spent either way.
func resolve(taken: int) -> void:
	_opened = true
	var sunk: PackedInt32Array = PackedInt32Array()
	if taken >= 0 and sink_taken_object:
		sunk.append(taken)
	elif taken < 0 and sink_on_decline:
		for index in _objects.size():
			sunk.append(index)
	_spent[cache_id] = sunk
	for index in sunk:
		if index < _objects.size() and _objects[index] != null and is_instance_valid(_objects[index]):
			_objects[index].settle_and_free()
			_objects[index] = null
