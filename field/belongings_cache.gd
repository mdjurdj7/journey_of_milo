extends Node3D
class_name BelongingsCache

# Three things set down together - a case, a pack, a shard of Glassbone -
# and one choice between them, made on a screen (BelongingsScreen) rather
# than at the things themselves. The sand carries the three objects; the
# screen carries the choice, showing each object - what is in it shows
# only once it is taken.
#
# Each object holds one kind of thing, always the same one: the case
# coin (coin_amount), the pack pick_count distinct cards from the prop's
# pool - looked through and one taken, or none - and the shard
# glassbone_offer Glassbone. The cards, and whether the case or the pack
# also holds Glassbone (glassbone_chance, which one picked at random),
# are rolled once, when the floor loads (RegionField._spawn_floor_props()
# calls roll() from the run's own generator). None of it changes after.
#
# Walking within trigger_radius of this node (on the ground plane) opens
# the screen through RegionField.open_belongings_screen(), once. Taking or
# declining spends the cache for the run - keyed by cache_id in a static
# set that survives the floor reload and is cleared by RunState.new_run(),
# as Hull's findings are. A take sinks that column's object (sink_taken_
# object); a decline leaves all three (sink_on_decline). Back on a spent
# cache's floor, the objects that sank stay gone and nothing opens.
#
# The objects are BelongingsObjects: the model's own colour map on the
# painted shader times object_tint, grounded by its bbox, solid, and
# inert - nothing opens them from the field and they say nothing - save
# a column whose object_material_paths entry names a material: that
# object wears it instead, untinted (the shard's Glassbone). Object i is
# column i (BelongingsScreen.Slot): the case (the coin), the pack (the
# cards), the shard (the Glassbone).

@export_group("Objects")
# The three models, in column order: the case, the pack, the shard - the
# seam's own model (GlassboneSeam.shard_model_path).
@export var object_scene_paths: PackedStringArray = PackedStringArray([
	"res://assets/models/props/belongings/case.glb",
	"res://assets/models/props/belongings/pack.glb",
	"res://assets/models/props/glassbone_shard/glassbone_shard.glb",
]):
	set(value):
		object_scene_paths = value
		_respawn_objects()
# A material for a column's object in place of its painted colour map and
# object_tint, column order; empty = painted. The shard wears the seam's
# Glassbone (GlassboneSeam.glassbone_material_path), on the sand and on
# the screen.
@export var object_material_paths: PackedStringArray = PackedStringArray(["", "", "res://field/glassbone_material.tres"]):
	set(value):
		object_material_paths = value
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
# smallest of the three, as a case beside a pack should be, and the shard
# (0.8 m long as modelled, for the seam) at 0.4, a fragment the pack's
# height. The screen renders them at these scales too.
@export var object_scales: PackedFloat32Array = PackedFloat32Array([0.6, 1.0, 0.4]):
	set(value):
		object_scales = value
		for index in _objects.size():
			if _objects[index] != null and is_instance_valid(_objects[index]):
				_objects[index].model_scale = object_scale(index)
		_place_objects()
# One shared medium brown multiplied into every object's own colour map -
# on the sand and on the screen (RegionField hands it to BelongingsScreen),
# so the pair match. Darker than dry sand (0.74, 0.70, 0.60).
@export var object_tint: Color = Color(0.76, 0.62, 0.46):
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
@export_multiline var world_line: String = "Someone's things, set down out of the wind."
# Whether a take sinks the taken column's object, and whether a decline
# sinks all three. Read when the screen closes.
@export var sink_taken_object: bool = true
@export var sink_on_decline: bool = false
@export_group("")

@export_group("Contents")
# What the case holds. Read when the screen opens. Its own number - set
# to the Collector's Bedroll price (Collector.bedroll_price), never read
# from it.
@export var coin_amount: int = 45
# How many distinct cards the pack holds, from the prop's pool (fewer
# only when the pool runs short). Read by roll().
@export var pick_count: int = 3
# What the shard holds. Read when the screen opens; 0 leaves that column
# out.
@export var glassbone_offer: int = 1
# The chance, per cache, that the case or the pack (either, equally) also
# holds glassbone_amount Glassbone, taken with it. Floor 2's sets it to 0
# (FloorProp overrides) - its Glassbone is the shard's. The chance is
# read by roll(), the amount when the screen opens.
@export_range(0.0, 1.0, 0.01) var glassbone_chance: float = 0.25
@export var glassbone_amount: int = 1
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."
# What the once-per-run set keys this cache under. Set by RegionField to
# the floor resource's path plus the prop's index.
@export var cache_id: String = ""

# The cards and glassbone_slot rolled by roll(). Empty = the pack's column
# is left out; glassbone_slot is the column that also holds Glassbone, -1
# for none.
var cards: Array[CardData] = []
var glassbone_slot: int = -1

var _objects: Array[BelongingsObject] = []
var _wanderer: Node3D = null
var _opened: bool = false

# cache_id -> PackedInt32Array of the objects that sank. Present = spent.
static var _spent: Dictionary = {}

static func reset_spent() -> void:
	_spent.clear()

# `character` is whose run it is - the pack's cards only of theirs or
# neutral (RewardPool.roll()), distinct.
func roll(rng: RandomNumberGenerator, pool: RewardPool, character: CharacterData = null) -> void:
	cards = pool.roll(pick_count, rng, null, character) if pool != null else ([] as Array[CardData])
	if cards.is_empty():
		push_warning("BelongingsCache '%s': the pack's cards rolled nothing; that column is left out." % name)
	var has_glassbone: bool = rng.randf() < glassbone_chance
	glassbone_slot = rng.randi_range(BelongingsScreen.Slot.GOLD, BelongingsScreen.Slot.CARD) if has_glassbone else -1

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
		object.material_path = object_material_paths[index] if index < object_material_paths.size() else ""
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
