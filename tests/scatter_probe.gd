extends SceneTree

# Headless probe for the ground scatter (FieldScatter) on floors 1 and 2.
# Each floor gives identical placements every load; nothing lies in water
# past its entry's wet edge, within the worn band's keep-out of its
# centreline, inside an exclusion, or at the spawn; the item count is
# under the floor's budget (printed). Floor 1 is near-pristine - two
# samphire patches and a few stones, nothing else - its crab's body and
# battle stance ring clear, its props' footprints excluded; a live edit
# lays it again and back exactly; nothing has collision and the walk grid
# is the same without it. Floor 2's tideline (CONTOUR mode) lies in its
# band inland of the water, kept 5 m off every enemy; nothing on floor 2
# stands in the Sputter and Underfoot's battle line.
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
const FLOOR_2 := 1
const FLOOR_1_KINDS: Array[String] = ["samphire", "stone_small", "stone_large"]
# The worn band's keep-out: its half-width plus its edge noise.
const WEAR_KEEP_OUT_M := 2.8
# The stance ring around a lone enemy is read from the rules it keeps clear
# for (RegionField.stance_distance_min()..stance_distance() for that enemy,
# widened by the scatter's own feet_margin_m) - see _stance_ring().
# A cluster's line: his feet at the stance (his radius + 0.6) and the
# members along it.
const LINE_RADIUS_M := 1.0
const SPAWN_CLEAR_M := 1.5
# A contour item's slack about its band beyond the wander and the across
# jitter: the line is traced between 0.5 m grid cells.
const CONTOUR_SLACK_M := 0.3
const TIDELINE_ENEMY_CLEAR_M := 5.0
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	await _check_floor_1()
	await _check_floor_2()
	if _failures == 0:
		print("scatter_probe: PASSED")
		quit(0)
	else:
		print("scatter_probe: %d FAILED" % _failures)
		quit(1)

# --- Floors ---

func _check_floor_1() -> void:
	await _load_field(FLOOR_1)
	var scatter: Node = _scatter()
	if scatter == null:
		_fail("floor 1 has no scatter")
		await _teardown()
		return
	var first: Array = _snapshot(scatter)
	_check_budget(scatter, 1)
	var kinds: Array[String] = []
	for entry: Resource in scatter.call("get_entries"):
		if not (scatter.call("get_spots", entry) as Array).is_empty():
			kinds.append(str(entry.get("name")))
	kinds.sort()
	var expected: Array[String] = FLOOR_1_KINDS.duplicate()
	expected.sort()
	_expect_eq(kinds, expected, "Floor 1 is near-pristine: samphire and stones only")
	_check_placements(scatter)
	_check_crab_clear(scatter)
	_check_footprints(scatter)
	await _check_live_edit(scatter, first)
	_check_no_collision(scatter)
	await _check_walk_grid()
	await _teardown()
	await _load_field(FLOOR_1)
	scatter = _scatter()
	_expect(scatter != null and _snapshot(scatter) == first, "A second load of floor 1 lays its scatter exactly as the first")
	await _teardown()

func _check_floor_2() -> void:
	await _load_field(FLOOR_2)
	var scatter: Node = _scatter()
	if scatter == null:
		_fail("floor 2 has no scatter")
		await _teardown()
		return
	var first: Array = _snapshot(scatter)
	_check_budget(scatter, 2)
	_check_placements(scatter)
	_check_contours(scatter)
	_check_cluster_line_clear(scatter, &"crab")
	_check_no_collision(scatter)
	await _teardown()
	await _load_field(FLOOR_2)
	scatter = _scatter()
	_expect(scatter != null and _snapshot(scatter) == first, "A second load of floor 2 lays its scatter exactly as the first")
	await _teardown()

# --- Checks ---

func _check_budget(scatter: Node, floor_number: int) -> void:
	var floor_data: Resource = _field.call("get_floor_data")
	var budget: int = int(floor_data.get("scatter_budget"))
	var count: int = int(scatter.call("get_item_count"))
	var line := "Floor %d: %d scatter items (budget %d):" % [floor_number, count, budget]
	for entry: Resource in scatter.call("get_entries"):
		line += " %s %d" % [str(entry.get("name")), (scatter.call("get_spots", entry) as Array).size()]
	print(line)
	_expect(count > 0, "Floor %d has scatter" % floor_number)
	_expect(budget > 0 and count <= budget, "Floor %d's %d items are within its budget of %d" % [floor_number, count, budget])

# Every item: on sand no lower than the water's level less its entry's
# wet edge; clear of the worn band's keep-out (the band's own curve,
# measured here); outside every exclusion the scatter keeps (is_excluded())
# and clear of the spawn.
func _check_placements(scatter: Node) -> void:
	var sea: float = float(scatter.call("get_sea_level"))
	var ground: Node = _field.get_node("Ground")
	var wear: PackedVector2Array = _field.call("get_wear_path")
	_expect(wear.size() >= 3, "The worn band's points are kept for it")
	var problems: Dictionary = {}
	for entry: Resource in scatter.call("get_entries"):
		for spot: RefCounted in scatter.call("get_spots", entry):
			var p: Vector2 = _xz(spot)
			if float(ground.call("get_visible_height_at", p)) < sea - float(entry.get("wet_edge_m")) - 0.001:
				_count(problems, "in water")
			if _curve_distance(wear, p) < WEAR_KEEP_OUT_M - 0.01:
				_count(problems, "on the worn band")
			if bool(scatter.call("is_excluded", p)):
				_count(problems, "inside an exclusion")
			if p.distance_to(Vector2.ZERO) < SPAWN_CLEAR_M:
				_count(problems, "at the spawn")
	_expect(problems.is_empty(), "No item in water, on the worn band, in an exclusion or at the spawn - got %s" % str(problems))

# Floor 1's lone crab: nothing on its body or in the ring his stance lands
# on, however he comes at it.
func _check_crab_clear(scatter: Node) -> void:
	var crab: Node3D = get_nodes_in_group("enemies")[0] as Node3D
	var at := Vector2(crab.global_position.x, crab.global_position.z)
	var ring: Vector2 = _stance_ring(scatter, crab)
	var problems: Dictionary = {}
	for entry: Resource in scatter.call("get_entries"):
		for spot: RefCounted in scatter.call("get_spots", entry):
			var distance: float = _xz(spot).distance_to(at)
			if distance >= ring.x and distance <= ring.y:
				_count(problems, "in the crab's stance ring")
			if distance < 0.9:
				_count(problems, "on the crab")
	_expect(problems.is_empty(), "Nothing at the crab's feet or his - got %s" % str(problems))

# The props' footprints are exclusions: each shape's centre is excluded.
func _check_footprints(scatter: Node) -> void:
	for shape: Node in _field.call("get_obstacle_shapes"):
		var centre: Vector3 = (shape as Node3D).global_position
		_expect(bool(scatter.call("is_excluded", Vector2(centre.x, centre.z))), "The footprint of '%s' is kept clear" % shape.get_parent().name)

# A CONTOUR entry's items lie in their band - contour_inland_m inland of
# the water, give or take the wander, the across jitter and the trace's
# slack - and a tideline's keep 5 m off every enemy.
func _check_contours(scatter: Node) -> void:
	var ground: Node = _field.get_node("Ground")
	var contour_items: int = 0
	var problems: Dictionary = {}
	for entry: Resource in scatter.call("get_entries"):
		if int(entry.get("mode")) != 1:
			continue
		var level: float = float(entry.get("contour_inland_m"))
		var reach: float = float(entry.get("contour_wander_m")) + float(entry.get("contour_across_jitter_m")) + CONTOUR_SLACK_M
		for spot: RefCounted in scatter.call("get_spots", entry):
			contour_items += 1
			var p: Vector2 = _xz(spot)
			var inland: float = -float(ground.call("get_landmass_distance", p))
			if absf(inland - level) > reach:
				_count(problems, "%s off its band (%.2f m inland)" % [str(entry.get("name")), inland])
			for node in get_nodes_in_group("enemies"):
				var enemy := node as Node3D
				if p.distance_to(Vector2(enemy.global_position.x, enemy.global_position.z)) < TIDELINE_ENEMY_CLEAR_M - 0.01:
					_count(problems, "%s within 5 m of an enemy" % str(entry.get("name")))
	_expect(contour_items > 0, "Floor 2 has a tideline")
	_expect(problems.is_empty(), "Every tideline item in its band and off the enemies - got %s" % str(problems))

# A cluster's battle line, from the rules: his stance stance_distance()
# behind the anchor, the members on the line toward the far one, out to
# the line's furthest shift - nothing within LINE_RADIUS_M of it.
func _check_cluster_line_clear(scatter: Node, group: StringName) -> void:
	var anchor: Node3D = null
	var far: Node3D = null
	var gaps: float = 0.0
	for node in get_nodes_in_group("enemies"):
		if node.get("group") != group:
			continue
		if bool(node.get("anchor")):
			anchor = node as Node3D
		else:
			far = node as Node3D
			var gap: float = float((node.get("enemy_data") as Resource).get("cluster_gap_m"))
			gaps += gap if gap >= 0.0 else float(_field.get("cluster_member_gap"))
	if anchor == null or far == null:
		_fail("no '%s' pair on floor 2" % group)
		return
	var a := Vector2(anchor.global_position.x, anchor.global_position.z)
	var along: Vector2 = (Vector2(far.global_position.x, far.global_position.z) - a).normalized()
	var stance: Vector2 = a - along * float(_field.call("stance_distance", anchor))
	var end: Vector2 = a + along * (float(_field.get("battle_line_shift_max")) + gaps)
	var inside: int = 0
	for entry: Resource in scatter.call("get_entries"):
		for spot: RefCounted in scatter.call("get_spots", entry):
			if _segment_distance(_xz(spot), stance, end) < LINE_RADIUS_M - 0.01:
				inside += 1
	_expect_eq(inside, 0, "Nothing in the %s fight's battle line" % group)

# A live edit lays it again the same way: the floor's budget lowered
# thins it, put back restores it exactly.
func _check_live_edit(scatter: Node, first: Array) -> void:
	var floor_data: Resource = _field.call("get_floor_data")
	var budget: int = int(floor_data.get("scatter_budget"))
	floor_data.set("scatter_budget", 5)
	await process_frame
	await process_frame
	var thinner: int = int(scatter.call("get_item_count"))
	_expect(thinner <= 5 and thinner < first.size(), "Budget 5: fewer items (%d of %d)" % [thinner, first.size()])
	floor_data.set("scatter_budget", budget)
	await process_frame
	await process_frame
	_expect(_snapshot(scatter) == first, "...and back at %d, exactly as before" % budget)

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

func _load_field(floor_index: int) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
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

static func _xz(spot: RefCounted) -> Vector2:
	var at: Vector3 = spot.get("position")
	return Vector2(at.x, at.z)

static func _count(problems: Dictionary, what: String) -> void:
	problems[what] = int(problems.get(what, 0)) + 1

static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var h: float = clampf((p - a).dot(ab) / maxf(ab.dot(ab), 1.0e-6), 0.0, 1.0)
	return (p - a - ab * h).length()

# Distance to the band's centreline: three points as the shader draws them
# (a quadratic Bezier through the middle one), sampled finely.
static func _curve_distance(points: PackedVector2Array, p: Vector2) -> float:
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

# The ring a lone enemy's stance can land on, from the rules: inner and
# outer radius (x, y) - its stance distance at the least and the most gap
# (RegionField.stance_distance_min()/stance_distance()), each widened by
# the scatter's feet_margin_m.
func _stance_ring(scatter: Node, enemy: Node) -> Vector2:
	var margin: float = float(scatter.get("feet_margin_m"))
	return Vector2(maxf(float(_field.call("stance_distance_min", enemy)) - margin, 0.0), float(_field.call("stance_distance", enemy)) + margin)
