extends Node3D
class_name RewardSpread

# What a won fight leaves on the sand: three cards from a RewardPool,
# lying where the enemy stood. Walk up and all three lift together; take
# one and the other two are put back down and fade. Walk away and they
# stay exactly as they are for the rest of the run - there is no timer
# and no "skip" control, because walking away IS the skip.
#
# Also a cache placed as a floor prop (FloorProp with this scene and a
# pool, see RegionField._spawn_floor_props()): the same lift/take/dismiss
# with no fight in front of it, laid along an authored fan_axis so the
# cards follow the ground they lie on rather than the camera.
#
# The three are WorldCards, the same ones the Keeper holds out, in their
# standalone configuration: no holder to measure a silhouette against
# (so the near-state gap is taken from the card's own ground point), and
# region_field_path resolved from here so the take-flight still finds the
# Belongings count.
#
# This node owns the LIFT for all three. A WorldCard normally measures
# its own radius, but three cards 0.55 m apart would each cross their own
# radius a step apart and rise raggedly; so their own check is switched
# off (lift_radius_enabled) and this pushes one answer, measured from the
# spread's centre, into all of them (set_lifted()).

@export var pool: RewardPool = null
# Whose fight this was. Passed to RewardPool.roll() for its per-enemy
# bias; null simply rolls the pool flat.
@export var enemy: EnemyData = null
@export var card_count: int = 3

@export_group("Layout")
# The fan's own axis, world XZ. Zero (the fight-drop default) = the
# camera's right, captured ONCE when the spread is built rather than
# tracked: these are cards lying on sand, and a fan that re-aimed itself
# as the camera moved would read as them sliding about. Set for a cache
# so the row follows the alcove it lies in.
@export var fan_axis: Vector2 = Vector2.ZERO:
	set(value):
		fan_axis = value
		_relayout()
@export var spacing: float = 0.55:
	set(value):
		spacing = value
		_relayout()
# Alternating nudge along the fan's own depth, so three cards in a row
# don't read as a ruled line.
@export var depth_stagger: float = 0.18:
	set(value):
		depth_stagger = value
		_relayout()
# Clear of the relief by this much - the quads are flat and would z-fight
# the sand at exactly ground height.
@export var ground_clearance: float = 0.02:
	set(value):
		ground_clearance = value
		_relayout()
@export_group("")

# From the spread's CENTRE, not from any one card.
@export var lift_radius: float = 2.5

@export var ground_path: NodePath = ^"../Ground"
@export var region_field_path: NodePath = ^".."
@export var world_card_scene_path: String = "res://field/world_card.tscn"

var _cards: Array[WorldCard] = []
var _wanderer: Node3D = null
var _lifted: bool = false
# True once one card has been taken: the rest are on their way out and
# this node is waiting to be empty so it can go too.
var _spent: bool = false

# An empty pool is an expected state right now, not a fault: the Wanderer
# has no reward cards authored yet (see DESIGN.md). So it says so once
# per session and goes quietly, rather than pushing a warning per fight
# for a condition nobody can act on mid-run.
static var _empty_pool_reported: bool = false

func _ready() -> void:
	# Same reason WorldCard sets it: the projection its cards do has to
	# run after CameraRig has placed the camera this frame.
	process_priority = 1
	_wanderer = _find_wanderer()
	if pool == null or pool.entries.is_empty():
		if not _empty_pool_reported:
			_empty_pool_reported = true
			print("RewardSpread: reward pool empty; no cards will drop.")
		queue_free()
		return
	_spawn_cards()
	if _cards.is_empty():
		push_warning("RewardSpread: pool holds %d entries but rolled nothing; freeing." % pool.entries.size())
		queue_free()

func _find_wanderer() -> Node3D:
	var found: Array[Node] = get_tree().get_nodes_in_group("wanderer")
	return found[0] as Node3D if not found.is_empty() else null

func _spawn_cards() -> void:
	var rolled: Array[CardData] = pool.roll(card_count, RunState.rng, enemy)
	if rolled.is_empty():
		return
	var scene := load(world_card_scene_path) as PackedScene
	if scene == null:
		push_warning("RewardSpread: could not load %s; nothing to offer." % world_card_scene_path)
		return

	var region_field := get_node_or_null(region_field_path)

	for index in rolled.size():
		var card := scene.instantiate() as WorldCard
		card.name = "RewardCard%d" % index
		card.card = rolled[index]
		# This node decides the lift for the group - see the class doc.
		card.lift_radius_enabled = false
		# No holder: the silhouette gap and the near-state bottom edge both
		# fall back to the card's own ground point, which out here is what
		# they should key off anyway.
		card.holder_path = ^""
		add_child(card)
		if region_field != null:
			card.region_field_path = card.get_path_to(region_field)
		card.taken.connect(_on_card_taken.bind(card))
		_cards.append(card)
	_relayout()

# Seats every card on the fan: index order along the axis, centred on
# this node, alternately nudged along the fan's depth. Called once at
# build and again from the Layout setters, so a Remote-tab edit moves
# the cards in place.
func _relayout() -> void:
	if _cards.is_empty():
		return
	var right: Vector3 = _fan_axis()
	# The fan's own depth axis: right turned a quarter turn on the ground
	# plane, so the stagger runs into and out of the screen rather than
	# up and down it.
	var depth: Vector3 = Vector3(-right.z, 0.0, right.x)
	var count: int = _cards.size()
	for index in count:
		var card: WorldCard = _cards[index]
		if not is_instance_valid(card):
			continue
		var across: float = (float(index) - float(count - 1) / 2.0) * spacing
		var stagger: float = depth_stagger * (0.5 if index % 2 == 1 else -0.5)
		card.global_position = _ground_point(global_position + right * across + depth * stagger)

# fan_axis when set; else the camera's right, flattened. Falls back to
# world +X if there's no camera yet - the fan is still a fan, just not
# aimed at anyone.
func _fan_axis() -> Vector3:
	if fan_axis.length() > 0.0001:
		return Vector3(fan_axis.x, 0.0, fan_axis.y).normalized()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.RIGHT
	var right: Vector3 = camera.global_transform.basis.x
	right = Vector3(right.x, 0.0, right.z)
	return right.normalized() if right.length() > 0.0001 else Vector3.RIGHT

# Seats a point on the relief, clear of it by ground_clearance. Same
# to_local()-first idiom Keeper and ContactShadow use - get_height_at()
# works in Ground's own frame, not the world's.
func _ground_point(world_position: Vector3) -> Vector3:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return world_position + Vector3.UP * ground_clearance
	var local: Vector3 = ground.to_local(Vector3(world_position.x, 0.0, world_position.z))
	var height: float = ground.get_height_at(Vector2(local.x, local.z))
	return Vector3(world_position.x, height + ground_clearance, world_position.z)

func _physics_process(_delta: float) -> void:
	# Cards free themselves - after a take-flight, or at the end of a
	# dismiss fade - so an empty list is how this node learns it's done
	# rather than being told on a timer that could outlive or cut short
	# either animation.
	# Built by hand rather than with filter(): filter() hands back an
	# untyped Array, which won't assign to a typed one.
	var alive: Array[WorldCard] = []
	for card in _cards:
		if is_instance_valid(card) and not card.is_queued_for_deletion():
			alive.append(card)
	_cards = alive
	if _spent:
		if _cards.is_empty():
			queue_free()
		return

	if _wanderer == null or not is_instance_valid(_wanderer):
		_wanderer = _find_wanderer()
		if _wanderer == null:
			return
	var near: bool = global_position.distance_to(_wanderer.global_position) <= lift_radius
	if near == _lifted:
		return
	_lifted = near
	for card in _cards:
		card.set_lifted(near)

# One was taken (it has already granted itself through RunState.add_card
# and is flying to the deck count). The others are put back down and
# faded; this node frees once every card has gone.
func _on_card_taken(_card_data: CardData, taken_card: WorldCard) -> void:
	_spent = true
	for card in _cards:
		if card != taken_card and is_instance_valid(card):
			card.dismiss()
