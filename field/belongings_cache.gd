extends Node3D
class_name BelongingsCache

# Three bundles set down together - one choice between them, made on a
# screen (BelongingsScreen) rather than at the bundles themselves. From
# the top-down camera three small things on the sand don't read as three
# offers, so the sand only carries three mounds and the screen carries
# the choice.
#
# What the three hold is rolled once, when the floor loads (RegionField.
# _spawn_floor_props() calls roll() from the run's own generator): a card
# from the prop's pool, the gold, and a closed card from the floor's
# rare_pool - the belongings pool while that is empty, drawn in one roll
# with the shown card so the two always differ. None of it changes after.
#
# Walking within trigger_radius of this node (on the ground plane) opens
# the screen through RegionField.open_belongings_screen(), once. Taking or
# declining spends the cache for the run - keyed by cache_id in a static
# set that survives the floor reload and is cleared by RunState.new_run(),
# as Hull's findings are. A take sinks that column's mound (sink_taken_
# mound); a decline leaves all three (sink_on_decline). Back on a spent
# cache's floor, the mounds that sank stay gone and nothing opens.
#
# The mounds are BundleProps (the bundle's model, cloth and collision)
# with nothing inside and no line, so they neither open a loot window nor
# speak. Mound i stands for column i: the card, the gold, the closed one.

const BUNDLE_SCENE_PATH := "res://field/bundle_prop.tscn"

@export_group("Mounds")
# Each mound's XZ offset from this node, in its own (yawed) frame, and its
# yaw - index i is column i's mound.
@export var mound_offsets: PackedVector2Array = PackedVector2Array([Vector2(0.0, -0.45), Vector2(0.0, 0.0), Vector2(0.0, 0.45)]):
	set(value):
		mound_offsets = value
		_place_mounds()
@export var mound_yaws_degrees: PackedFloat32Array = PackedFloat32Array([20.0, -35.0, 70.0]):
	set(value):
		mound_yaws_degrees = value
		_place_mounds()
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
@export_multiline var world_line: String = "Three bundles, set down together. Nobody came back for them."
# On the floor's own gold range (FloorData.gold_min/gold_max) - the
# bundle's own multiplier.
@export var gold_multiplier: float = 1.5
# Whether a take sinks the taken column's mound, and whether a decline
# sinks all three. Read when the screen closes.
@export var sink_taken_mound: bool = true
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

var _mounds: Array[BundleProp] = []
var _wanderer: Node3D = null
var _opened: bool = false

# cache_id -> PackedInt32Array of the mounds that sank. Present = spent.
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
# mounds ground themselves; yaw onto yaw_degrees.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	var sunk: PackedInt32Array = PackedInt32Array()
	if _spent.has(cache_id):
		_opened = true
		sunk = _spent[cache_id]
	_spawn_mounds(sunk)

# The mounds, one level below this node - so their paths reach one level
# further than this node's own.
func _spawn_mounds(sunk: PackedInt32Array) -> void:
	var scene := load(BUNDLE_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("BelongingsCache: could not load %s; no mounds." % BUNDLE_SCENE_PATH)
		return
	for index in mound_offsets.size():
		if sunk.has(index):
			_mounds.append(null)
			continue
		var mound := scene.instantiate() as BundleProp
		mound.name = "Mound%d" % index
		mound.world_line = ""
		mound.ground_path = NodePath("../" + String(ground_path))
		mound.region_field_path = NodePath("../" + String(region_field_path))
		add_child(mound)
		_mounds.append(mound)
	_place_mounds()

func _place_mounds() -> void:
	for index in _mounds.size():
		var mound: BundleProp = _mounds[index]
		if mound == null or not is_instance_valid(mound) or index >= mound_offsets.size():
			continue
		var offset: Vector2 = mound_offsets[index]
		mound.position = Vector3(offset.x, 0.0, offset.y)
		mound.yaw_degrees = mound_yaws_degrees[index] if index < mound_yaws_degrees.size() else 0.0
		mound.global_position.y = _ground_height(mound.global_position)

# The relief's height under a world point - the to_local()-first idiom
# RewardSpread and Keeper use, since get_height_at() works in Ground's
# own frame. 0 if Ground doesn't resolve. A mound re-grounds itself the
# same way on a relief rebuild.
func _ground_height(world_position: Vector3) -> float:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return 0.0
	var local: Vector3 = ground.to_local(Vector3(world_position.x, 0.0, world_position.z))
	return ground.get_height_at(Vector2(local.x, local.z))

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
	if taken >= 0 and sink_taken_mound:
		sunk.append(taken)
	elif taken < 0 and sink_on_decline:
		for index in _mounds.size():
			sunk.append(index)
	_spent[cache_id] = sunk
	for index in sunk:
		if index < _mounds.size() and _mounds[index] != null and is_instance_valid(_mounds[index]):
			_mounds[index].settle_and_free()
			_mounds[index] = null
