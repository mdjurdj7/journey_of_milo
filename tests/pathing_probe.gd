extends SceneTree

# Headless probe for field pathing (NavGrid, RegionField.plan_path(),
# Wanderer.set_move_path()): on every floor a path from spawn to the exit
# that never wades deep water; round a hull and across no ledge line; past
# the Blackback's pack without entering a contact zone - into one only
# when that enemy is the target; a click in deep water ending at the
# nearest reachable point; floor 2's island wade walkable and costed, not
# blocked; smoothing that never wades where the planned path didn't; and
# floor 2's exit-line hold still stopping a planned walk.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/pathing_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# NavGrid through Ground, the Wanderer).

const CASES := 8
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const NAV_GRID_PATH := "res://field/nav_grid.gd"
const BLACKBACK_PATH := "res://battle/rules/enemies/blackback.tres"
const SAFETY_SECONDS := 400.0
# Sampling a path's segments, metres.
const STEP := 0.1

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	await _check_exits()
	await _check_hull()
	await _check_ledge()
	await _check_enemy_zones()
	await _check_unreachable()
	await _check_wade()
	_check_smoothing_stays_dry()
	await _check_hold_line()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("pathing_probe: PASSED")
		quit(0)
	else:
		print("pathing_probe: %d FAILED" % _failures)
		quit(1)

# Every floor: spawn to just short of the exit gate, on the ground alone -
# reached, and no sample of it in deep water.
func _check_exits() -> void:
	for floor_index in 5:
		await _load(floor_index)
		var nav: Object = _field.call("get_nav_grid")
		_expect(nav != null, "Floor %d has its walk grid" % (floor_index + 1))
		if nav != null:
			var spawn: Vector3 = _field.call("get_spawn_position")
			var gate: Node3D = _field.get_node("ExitGate")
			var exit_dir: Vector3 = _field.call("get_exit_direction")
			var target: Vector3 = gate.global_position - exit_dir * 2.0
			var path: PackedVector3Array = _field.call("plan_path", spawn, target, null, false)
			_expect(path.size() >= 2, "Floor %d: a path from spawn to the exit" % (floor_index + 1))
			if path.size() >= 2:
				_expect(_flat(path[path.size() - 1]).distance_to(_flat(target)) < 0.5, "...reaching it")
				var deep: int = 0
				for sample in _samples(path):
					if bool(nav.call("is_deep", nav.call("world_to_cell", sample))):
						deep += 1
				_expect_eq(deep, 0, "...never in deep water")
		await _teardown()
	_completed += 1

# Floor 1: a point behind each hull, from spawn - the path goes round
# (longer than the straight line, which crosses the hull) and no sample of
# it is on a blocked cell; walked, he gets there.
func _check_hull() -> void:
	await _load(0)
	var nav: Object = _field.call("get_nav_grid")
	var wanderer: Node3D = _field.get_node("Wanderer")
	for hull_name in ["Hull0", "Hull2", "Hull3"]:
		var hull := _field.find_child(hull_name, true, false) as Node3D
		if hull == null:
			_fail("no %s on floor 1" % hull_name)
			continue
		var away: Vector3 = hull.global_position - wanderer.global_position
		away.y = 0.0
		var goal: Vector3 = hull.global_position + away.normalized() * 3.5
		var path: PackedVector3Array = _field.call("plan_path", wanderer.global_position, goal, null, false)
		_expect(path.size() >= 3, "%s: the path behind it bends (%d points)" % [hull_name, path.size()])
		var blocked: int = 0
		var samples: PackedVector2Array = _samples(path)
		for i in range(1, samples.size()):
			if not bool(nav.call("is_open", nav.call("world_to_cell", samples[i]))):
				blocked += 1
		_expect_eq(blocked, 0, "...never across a blocked cell")
		_field.call("walk_to", goal)
		await _walk(wanderer, 20.0)
		_expect(_flat(wanderer.global_position).distance_to(_flat(goal)) < 0.5, "...and walked, he gets there (%.2f m off)" % _flat(wanderer.global_position).distance_to(_flat(goal)))
	await _teardown()
	_completed += 1

# Floor 3: from the stem to the Wardling's lobe, the straight line crosses
# a ledge line; the path crosses none of them, and gets there.
func _check_ledge() -> void:
	await _load(2)
	var spawn: Vector3 = _field.call("get_spawn_position")
	var from: Vector3 = spawn + Vector3(0.0, 0.0, -5.0)
	var to: Vector3 = spawn + Vector3(18.1, 0.0, -14.4)
	var ledges: Array = (_field.call("get_floor_data") as Resource).get("ledges")
	_expect(_crosses_ledges(PackedVector2Array([_flat(from) - _flat(spawn), _flat(to) - _flat(spawn)]), ledges), "The straight line from the stem to the lobe crosses a ledge")
	var path: PackedVector3Array = _field.call("plan_path", from, to, null, false)
	var relative := PackedVector2Array()
	for point in path:
		relative.append(_flat(point) - _flat(spawn))
	_expect(path.size() >= 2 and _flat(path[path.size() - 1]).distance_to(_flat(to)) < 0.5, "The path reaches the lobe")
	_expect(not _crosses_ledges(relative, ledges), "...across no ledge line")
	await _teardown()
	_completed += 1

# Floor 3: from spawn to the plaza past the Blackback's pack, and from one
# side of the pack straight across to the other - every sample outside
# every contact zone. To the Blackback itself: into its zone, its
# packmate's left alone (one fight).
func _check_enemy_zones() -> void:
	await _load(2)
	var spawn: Vector3 = _field.call("get_spawn_position")
	var enemies: Array = []
	var blackback: Node3D = null
	for node in get_nodes_in_group("enemies"):
		enemies.append(node)
		if (node.get("enemy_data") as Resource).resource_path == BLACKBACK_PATH:
			blackback = node
	var to: Vector3 = spawn + Vector3(2.5, 0.0, -25.5)
	var path: PackedVector3Array = _field.call("plan_path", spawn, to, null, true)
	_expect(path.size() >= 2 and _flat(path[path.size() - 1]).distance_to(_flat(to)) < 0.5, "Spawn to the plaza past the pack: reached")
	var inside: int = 0
	for sample in _samples(path):
		for enemy: Node3D in enemies:
			if sample.distance_to(_flat(enemy.global_position)) < float(enemy.get("contact_radius")):
				inside += 1
	_expect_eq(inside, 0, "...never inside a contact zone")
	# Straight through the pack: from south of the Blackback to north of
	# it - the straight line enters a zone, the planned path none.
	if blackback != null:
		var south: Vector3 = blackback.global_position + Vector3(0.0, 0.0, 6.0)
		var north: Vector3 = blackback.global_position + Vector3(0.0, 0.0, -7.0)
		var straight_inside: bool = false
		for sample in _samples(PackedVector3Array([south, north])):
			if sample.distance_to(_flat(blackback.global_position)) < float(blackback.get("contact_radius")):
				straight_inside = true
		_expect(straight_inside, "The straight line through the pack enters the Blackback's zone")
		var through: PackedVector3Array = _field.call("plan_path", south, north, null, true)
		_expect(through.size() >= 3, "...the planned one bends round it (%d points)" % through.size())
		var entered: int = 0
		for sample in _samples(through):
			for enemy: Node3D in enemies:
				if sample.distance_to(_flat(enemy.global_position)) < float(enemy.get("contact_radius")):
					entered += 1
		_expect_eq(entered, 0, "...and never inside a contact zone")
	if blackback != null:
		var to_it: PackedVector3Array = _field.call("plan_path", spawn, blackback.global_position, blackback, true)
		_expect(to_it.size() >= 2 and _flat(to_it[to_it.size() - 1]).distance_to(_flat(blackback.global_position)) < float(blackback.get("contact_radius")), "To the Blackback: into its own zone")
	await _teardown()
	_completed += 1

# Floor 1: a click far out in the sea - the path ends at a reachable cell
# short of it, nearer than where it started, never in deep water.
func _check_unreachable() -> void:
	await _load(0)
	var nav: Object = _field.call("get_nav_grid")
	var spawn: Vector3 = _field.call("get_spawn_position")
	var exit_dir: Vector3 = _field.call("get_exit_direction")
	var sea: Vector3 = spawn - exit_dir * 20.0
	_expect(bool(nav.call("is_deep", nav.call("world_to_cell", _flat(sea)))), "20 m seaward of spawn is deep water")
	var path: PackedVector3Array = _field.call("plan_path", spawn, sea, null, false)
	_expect(path.size() >= 1, "A click there still gives a path")
	if path.size() >= 1:
		var end: Vector2 = _flat(path[path.size() - 1])
		_expect(not bool(nav.call("is_deep", nav.call("world_to_cell", end))) and bool(nav.call("is_open", nav.call("world_to_cell", end))), "...ending on a reachable cell")
		_expect(end.distance_to(_flat(sea)) < _flat(spawn).distance_to(_flat(sea)), "...nearer the click than spawn")
	await _teardown()
	_completed += 1

# Floor 2: the trough's island is reached by wading - the path is planned
# through shallow cells, each costing nav_shallows_cost, none blocked.
func _check_wade() -> void:
	await _load(1)
	var nav: Object = _field.call("get_nav_grid")
	var spawn: Vector3 = _field.call("get_spawn_position")
	var trough := _field.find_child("Trough0", true, false) as Node3D
	if trough == null:
		_fail("no trough on floor 2")
	else:
		var beside: Vector2 = nav.call("nearest_open_toward", _flat(trough.global_position), _flat(spawn))
		var path: PackedVector3Array = _field.call("plan_path", spawn, Vector3(beside.x, 0.0, beside.y), null, false)
		_expect(path.size() >= 2 and _flat(path[path.size() - 1]).distance_to(beside) < 0.5, "Spawn to the trough's island: reached")
		var shallow: int = 0
		var costed: bool = true
		for sample in _samples(path):
			var cell: Vector2i = nav.call("world_to_cell", sample)
			if int((nav.get("water") as PackedByteArray)[cell.y * int(nav.get("cols")) + cell.x]) == 1:
				shallow += 1
				if not is_equal_approx(float(nav.call("cost_at", cell)), float(_field.get("nav_shallows_cost"))):
					costed = false
		_expect(shallow > 0, "...wading on the way (%d shallow samples)" % shallow)
		_expect(costed, "...every shallow cell costing %.0f" % float(_field.get("nav_shallows_cost")))
	await _teardown()
	_completed += 1

# A grid of its own: a shallow band across the middle with a dry gap at
# its left end, near enough that going round costs less than wading. The
# plan goes round by the gap; smoothed, it never cuts the corner through
# the band.
func _check_smoothing_stays_dry() -> void:
	var nav: Object = (load(NAV_GRID_PATH) as GDScript).new()
	var cols: int = 40
	var rows: int = 30
	nav.set("cell_size", 1.0)
	nav.set("cols", cols)
	nav.set("rows", rows)
	nav.set("origin", Vector2.ZERO)
	var water := PackedByteArray()
	water.resize(cols * rows)
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for z in range(13, 17):
		for x in range(6, 40):
			water[z * cols + x] = 1
			astar.set_point_weight_scale(Vector2i(x, z), 6.0)
	nav.set("water", water)
	nav.set("heights", heights)
	nav.set("astar", astar)
	var path: PackedVector2Array = nav.call("find_path", Vector2(10.5, 2.5), Vector2(10.5, 27.5))
	_expect(path.size() >= 3, "Across the band: the path goes round by the gap (%d points)" % path.size())
	var wet: int = 0
	for i in range(1, path.size()):
		var a: Vector2 = path[i - 1]
		var b: Vector2 = path[i]
		var steps: int = maxi(int(ceil(a.distance_to(b) / STEP)), 1)
		for s in steps + 1:
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			if water[int(floor(p.y)) * cols + int(floor(p.x))] == 1:
				wet += 1
	_expect_eq(wet, 0, "...and smoothed, it never wades the band")
	_completed += 1

# Floor 2, its required fight standing: a planned walk past the exit line
# stops on it, as the hold line always has.
func _check_hold_line() -> void:
	await _load(1)
	var wanderer: Node3D = _field.get_node("Wanderer")
	_expect(bool(wanderer.call("has_hold_line")), "Floor 2 holds its exit line while its fight stands")
	var reached: Array = [false]
	wanderer.connect("hold_line_reached", func() -> void: reached[0] = true)
	var gate: Node3D = _field.get_node("ExitGate")
	var exit_dir: Vector3 = _field.call("get_exit_direction")
	var beyond: Vector3 = gate.global_position + exit_dir * 6.0
	# Round the fights, as a click would: walking into one starts it.
	var path: PackedVector3Array = _field.call("plan_path", wanderer.global_position, beyond, null, true)
	wanderer.call("set_move_path", path)
	await _walk(wanderer, 25.0)
	await create_timer(1.0).timeout
	var past: float = (wanderer.global_position - gate.global_position).dot(exit_dir)
	_expect(bool(reached[0]), "The planned walk reaches the line and stops (hold_line_reached)")
	_expect(past < 0.1, "...not past it (%.2f m)" % past)
	await _teardown()
	_completed += 1

# --- Helpers ---

func _load(floor_index: int) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	root.add_child(_field)
	for i in 40:
		await physics_frame

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

# Until he stops walking, or `limit` seconds.
func _walk(wanderer: Node3D, limit: float) -> void:
	var waited: float = 0.0
	while bool(wanderer.call("has_move_target")) and waited < limit:
		await physics_frame
		waited += 1.0 / 60.0

func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

# Every STEP along a path's segments, world XZ.
func _samples(path: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, path.size()):
		var a: Vector2 = _flat(path[i - 1])
		var b: Vector2 = _flat(path[i])
		var steps: int = maxi(int(ceil(a.distance_to(b) / STEP)), 1)
		for s in steps + 1:
			out.append(a.lerp(b, float(s) / float(steps)))
	return out

# Whether a polyline (spawn-relative XZ) crosses any of the floor's ledge
# lines (FloorData.ledges, spawn-relative).
func _crosses_ledges(line: PackedVector2Array, ledges: Array) -> bool:
	for ledge: PackedVector2Array in ledges:
		for i in range(1, ledge.size()):
			for j in range(1, line.size()):
				if Geometry2D.segment_intersects_segment(line[j - 1], line[j], ledge[i - 1], ledge[i]) != null:
					return true
	return false

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
