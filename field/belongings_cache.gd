extends Node3D
class_name BelongingsCache

# Three things set down together - a case, a pack, a bedroll - and one
# choice between them, made on a screen (BelongingsScreen) rather than at
# the things themselves. The sand carries the three objects; the screen
# carries the choice, showing each object and nothing of what is in it.
#
# What the three hold is rolled once, when the floor loads (RegionField.
# _spawn_floor_props() calls roll() from the run's own generator): the
# case a card from the prop's pool, the pack the gold, the bedroll a card
# from the floor's rare_pool - the belongings pool while that is empty,
# drawn in one roll with the case's so the two always differ. None of it
# changes after.
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
# opens them from the field and they say nothing. Object i is column i:
# the case (the card), the pack (the gold), the bedroll (the unknown).

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
# On the floor's own gold range (FloorData.gold_min/gold_max) - the
# bundle's own multiplier.
@export var gold_multiplier: float = 1.5
# Whether a take sinks the taken column's object, and whether a decline
# sinks all three. Read when the screen closes.
@export var sink_taken_object: bool = true
@export var sink_on_decline: bool = false
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."
# What the once-per-run set keys this cache under. Set by RegionField to
# the floor resource's path plus the prop's index.
@export var cache_id: String = ""

# Rolled by roll(); null / 0 = that column is left out.
var shown_card: CardData = null
var gold: int = 0
var closed_card: CardData = null

var _objects: Array[BelongingsObject] = []
var _wanderer: Node3D = null
var _opened: bool = false

# cache_id -> PackedInt32Array of the objects that sank. Present = spent.
static var _spent: Dictionary = {}

static func reset_spent() -> void:
	_spent.clear()

func roll(rng: RandomNumberGenerator, gold_min: int, gold_max: int, pool: RewardPool, rare_pool: RewardPool) -> void:
	var rare: bool = rare_pool != null and not rare_pool.entries.is_empty()
	var cards: Array[CardData] = []
	if pool != null:
		cards = pool.roll(1 if rare else 2, rng, null)
	shown_card = cards[0] if cards.size() > 0 else null
	closed_card = cards[1] if cards.size() > 1 else null
	if rare:
		var rare_cards: Array[CardData] = rare_pool.roll(1, rng, null)
		closed_card = rare_cards[0] if not rare_cards.is_empty() else null
	if shown_card == null or closed_card == null:
		push_warning("BelongingsCache '%s': a card slot rolled nothing; that column is left out." % name)
	var base: int = rng.randi_range(mini(gold_min, gold_max), maxi(gold_min, gold_max))
	gold = maxi(roundi(float(base) * gold_multiplier), 1)

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
