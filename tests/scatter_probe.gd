extends SceneTree

# Headless probe for the ground scatter (FieldScatter) on floor 1: the
# same floor gives identical placements every load, and again after a
# live edit and back; nothing in deep water, within the worn band's
# keep-out of its centreline, or inside an exclusion - the spawn, a
# prop's footprint, the crab's body and its battle stance ring; the walk
# grid exactly as it is without the scatter, and nothing in it with
# collision; floor 1's item count under its budget (printed).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/scatter_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's field classes (get()/call()), as
# kill_order_probe.gd's header explains: naming RegionField or
# FieldScatter here would compile them before the RunState autoload.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_1 := 0
const BUDGET := 70
# The worn band's keep-out: its half-width plus its edge noise.
const WEAR_KEEP_OUT_M := 2.8
# The stance ring around a lone enemy: battle_spacing_min - 0.6 to
# battle_spacing + 0.6.
const RING_INNER_M := 1.9
const RING_OUTER_M := 4.6
const SPAWN_CLEAR_M := 1.5
const SAFETY_SECONDS := 240.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	await _load_field()
	var scatter: Node = _scatter()
	if scatter == null:
		_fail("floor 1 has no scatter")
		quit(1)
		return
	var first: Array = _snapshot(scatter)
	var count: int = int(scatter.call("get_item_count"))
	print("Floor 1: %d scatter items (budget %d)" % [count, BUDGET])
	_check_budget(scatter, count)
	_check_placements(scatter)
	await _check_live_edit(scatter, first)
	_check_no_collision(scatter)
	await _check_walk_grid()
	await _teardown()
	await _load_field()
	scatter = _scatter()
	_expect(scatter != null and _snapshot(scatter) == first, "A second load of floor 1 lays its scatter exactly as the first")
	await _teardown()
	if _failures == 0:
		print("scatter_probe: PASSED")
		quit(0)
	else:
		print("scatter_probe: %d FAILED" % _failures)
		quit(1)

func _check_budget(scatter: Node, count: int) -> void:
	_expect(count > 0, "Floor 1 has scatter")
	_expect(count <= BUDGET, "Floor 1's %d items are within its budget of %d" % [count, BUDGET])
	var floor_data: Resource = _field.call("get_floor_data")
	_expect_eq(int(floor_data.get("scatter_budget")), BUDGET, "...its scatter_budget")

# Every item: on sand no lower than the water's level less its entry's
# wet edge; clear of the worn band's keep-out (the band's own curve,
# measured here); outside every exclusion the scatter keeps (is_excluded()),
# and - counted here, not by the scatter - clear of the spawn, the crab's
# body and its stance ring.
func _check_placements(scatter: Node) -> void:
	var sea: float = float(scatter.call("get_sea_level"))
	var ground: Node = _field.get_node("Ground")
	var wear: PackedVector2Array = _field.call("get_wear_path")
	_expect(wear.size() >= 3, "The worn band's points are kept for it")
	var crab: Node3D = null
	for node in get_nodes_in_group("enemies"):
		crab = node as Node3D
	var crab_at := Vector2(crab.global_position.x, crab.global_position.z) if crab != null else Vector2.INF
	var spawn := Vector2.ZERO
	var problems: Dictionary = {}
	for entry: Resource in scatter.call("get_entries"):
		for spot: RefCounted in scatter.call("get_spots", entry):
			var at: Vector3 = spot.get("position")
			var p := Vector2(at.x, at.z)
			var height: float = float(ground.call("get_visible_height_at", p))
			if height < sea - float(entry.get("wet_edge_m")) - 0.001:
				problems["in water"] = int(problems.get("in water", 0)) + 1
			if _curve_distance(wear, p) < WEAR_KEEP_OUT_M - 0.01:
				problems["on the worn band"] = int(problems.get("on the worn band", 0)) + 1
			if bool(scatter.call("is_excluded", p)):
				problems["inside an exclusion"] = int(problems.get("inside an exclusion", 0)) + 1
			if p.distance_to(spawn) < SPAWN_CLEAR_M:
				problems["at the spawn"] = int(problems.get("at the spawn", 0)) + 1
			var to_crab: float = p.distance_to(crab_at)
			if to_crab >= RING_INNER_M and to_crab <= RING_OUTER_M:
				problems["in the crab's stance ring"] = int(problems.get("in the crab's stance ring", 0)) + 1
			if to_crab < 0.9:
				problems["on the crab"] = int(problems.get("on the crab", 0)) + 1
	_expect(problems.is_empty(), "No item in water, on the worn band, in an exclusion, at the spawn or the crab's feet - got %s" % str(problems))
	# The props' footprints are exclusions: each hull's and the Keeper's
	# shape centre is excluded.
	for shape: Node in _field.call("get_obstacle_shapes"):
		var centre: Vector3 = (shape as Node3D).global_position
		_expect(bool(scatter.call("is_excluded", Vector2(centre.x, centre.z))), "The footprint of '%s' is kept clear" % shape.get_parent().name)

# A live edit places it again the same way: the floor's density halved
# changes it, put back restores it exactly.
func _check_live_edit(scatter: Node, first: Array) -> void:
	var floor_data: Resource = _field.call("get_floor_data")
	floor_data.set("scatter_density", 0.5)
	await process_frame
	await process_frame
	var thinner: int = int(scatter.call("get_item_count"))
	_expect(thinner < first.size(), "Density 0.5: fewer items (%d of %d)" % [thinner, first.size()])
	floor_data.set("scatter_density", 1.0)
	await process_frame
	await process_frame
	_expect(_snapshot(scatter) == first, "...and back at 1.0, exactly as before")

func _check_no_collision(scatter: Node) -> void:
	_expect(scatter.find_children("*", "CollisionObject3D", true, false).is_empty(), "Nothing in the scatter has collision")
	_expect(scatter.find_children("*", "CollisionShape3D", true, false).is_empty(), "...no collision shape")

# The walk grid with the scatter, and built again without it: the same
# solid cells, water and heights.
func _check_walk_grid() -> void:
	var with: Object = _field.get("_nav")
	if with == null:
		_fail("no walk grid")
		return
	var solid: PackedByteArray = (with.get("base_solid") as PackedByteArray).duplicate()
	var water: PackedByteArray = (with.get("water") as PackedByteArray).duplicate()
	var heights: PackedFloat32Array = (with.get("heights") as PackedFloat32Array).duplicate()
	var scatter: Node = _scatter()
	_field.remove_child(scatter)
	scatter.free()
	_field.call("_build_nav_grid")
	var without: Object = _field.get("_nav")
	_expect(without != with, "The walk grid was built again")
	_expect(without.get("base_solid") == solid and without.get("water") == water and without.get("heights") == heights, "The walk grid is the same without the scatter")

# --- Helpers ---

func _load_field() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_1)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 40:
		await physics_frame

func _scatter() -> Node:
	return _field.call("get_scatter") if _field != null else null

# Every instance of every kind: its kind, transform and colour.
func _snapshot(scatter: Node) -> Array:
	var items: Array = []
	for instance: Node in scatter.call("get_instances"):
		var multimesh: MultiMesh = (instance as MultiMeshInstance3D).multimesh
		for i in multimesh.instance_count:
			items.append([instance.name, multimesh.get_instance_transform(i), multimesh.get_instance_color(i)])
	return items

# Distance to the band's centreline: three points as the shader draws them
# (a quadratic Bezier through the middle one), sampled finely.
func _curve_distance(points: PackedVector2Array, p: Vector2) -> float:
	if points.size() < 3:
		return INF
	var start: Vector2 = points[0]
	var end: Vector2 = points[points.size() - 1]
	var handle: Vector2 = 2.0 * points[1] - 0.5 * (start + end)
	var best: float = INF
	for i in 401:
		var t: float = float(i) / 400.0
		var u: float = 1.0 - t
		best = minf(best, p.distance_to(u * u * start + 2.0 * u * t * handle + t * t * end))
	return best

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
