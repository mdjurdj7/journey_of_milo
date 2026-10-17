extends SceneTree

# Headless probe for the walk grid against the ledge walls (NavGrid.
# footprint_cells(), LedgeBarrier, FloorData.ledges): the grid must stop
# him wherever the walls do, or a planned or clicked path routes through
# a wall the body then can't pass.
#
# Per floor:
# - Flooded from spawn over the open cells (8-way, a diagonal only past
#   no obstacle, as AStarGrid2D walks), no reached cell lies outside the
#   mainland: outside the ledge loops that hold spawn, or inside one that
#   doesn't (floor 4's central dune). A floor with no ledges has nothing
#   to leak through; its check is only that no reached cell is deep water.
# - A click from one side of a ledge to a point behind it: the straight
#   line crosses a ledge, the planned path crosses none and still gets
#   there - it goes round.
# - A click on ground outside the walls: the planned path crosses no
#   ledge and ends on the mainland.
# One of the round-the-wall walks is walked for real, so the body agrees.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/ledge_nav_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# NavGrid through Ground, the Wanderer).

const CASES := 6
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 300.0
# Sampling a path's segments, metres.
const STEP := 0.1

# Spawn-relative XZ. "behind": [from, to] - the straight line between them
# crosses a ledge, both on the mainland. "outside": a point past the walls.
const BEHIND := {
	2: [[Vector2(13.0, -14.0), Vector2(22.0, -30.0)], [Vector2(0.0, -3.0), Vector2(12.0, -13.0)]],
	3: [[Vector2(-4.0, -5.0), Vector2(-4.0, -21.0)], [Vector2(10.0, -14.0), Vector2(18.5, -7.5)]],
	4: [[Vector2(-8.0, -15.0), Vector2(-8.0, 2.0)]],
}
const OUTSIDE := {
	2: [Vector2(11.0, -6.0), Vector2(30.0, 0.0)],
	3: [Vector2(-3.0, -13.0), Vector2(30.0, 0.0)],
	4: [Vector2(20.0, -20.0), Vector2(-20.0, -30.0)],
}
# The walk walked for real: floor 4, round the central dune.
const WALK_FLOOR := 3

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
	for floor_index in 5:
		await _check_floor(floor_index)
	await _check_walk_round()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("ledge_nav_probe: PASSED")
		quit(0)
	else:
		print("ledge_nav_probe: %d FAILED" % _failures)
		quit(1)

func _check_floor(floor_index: int) -> void:
	await _load(floor_index)
	var label: String = "Floor %d" % (floor_index + 1)
	var nav: Object = _field.call("get_nav_grid")
	_expect(nav != null, "%s has its walk grid" % label)
	if nav == null:
		await _teardown()
		return
	var spawn: Vector2 = _flat(_field.call("get_spawn_position"))
	var loops: Array = _ledge_loops(spawn)
	var reached: PackedByteArray = _flood(nav, nav.call("world_to_cell", spawn))
	var cols: int = nav.get("cols")
	var count: int = 0
	var outside: int = 0
	var deep: int = 0
	var first_out: Vector2 = Vector2.INF
	for i in reached.size():
		if reached[i] == 0:
			continue
		count += 1
		var cell := Vector2i(i % cols, i / cols)
		var centre: Vector2 = nav.call("cell_centre", cell)
		if bool(nav.call("is_deep", cell)):
			deep += 1
		if not loops.is_empty() and not _on_mainland(centre, loops, spawn):
			outside += 1
			if first_out == Vector2.INF:
				first_out = centre - spawn
	_expect(count > 100, "%s: spawn reaches the floor (%d cells)" % [label, count])
	_expect_eq(deep, 0, "%s: no reached cell is deep water" % label)
	if loops.is_empty():
		print("%s: no ledges - %d cells reached from spawn" % [label, count])
	else:
		_expect_eq(outside, 0, "%s: no reached cell off the mainland (first at %s)" % [label, str(first_out)])
		print("%s: %d cells reached from spawn, %d off the mainland" % [label, count, outside])
	var ledges: Array = (_field.call("get_floor_data") as Resource).get("ledges")
	for pair: Array in BEHIND.get(floor_index, []):
		var from_rel: Vector2 = pair[0]
		var to_rel: Vector2 = pair[1]
		_expect(_crosses_ledges(PackedVector2Array([from_rel, to_rel]), ledges), "%s: the straight line %s -> %s crosses a ledge" % [label, str(from_rel), str(to_rel)])
		var path: PackedVector3Array = _plan(spawn + from_rel, spawn + to_rel)
		_expect(path.size() >= 2 and _flat(path[path.size() - 1]).distance_to(spawn + to_rel) < 0.5, "...the click path gets there")
		_expect(not _crosses_ledges(_relative(path, spawn), ledges), "...across no ledge line")
	for to_rel: Vector2 in OUTSIDE.get(floor_index, []):
		_expect(not _on_mainland(spawn + to_rel, loops, spawn), "%s: %s is off the mainland" % [label, str(to_rel)])
		var path: PackedVector3Array = _plan(spawn, spawn + to_rel)
		_expect(path.size() >= 1, "...a click there still gives a path")
		if path.size() >= 1:
			_expect(_on_mainland(_flat(path[path.size() - 1]), loops, spawn), "...ending on the mainland")
		_expect(not _crosses_ledges(_relative(path, spawn), ledges), "...across no ledge line")
	await _teardown()
	_completed += 1

# Floor 4, round the central dune on foot: walked from the first BEHIND
# start to its target, he gets there.
func _check_walk_round() -> void:
	await _load(WALK_FLOOR)
	var spawn: Vector2 = _flat(_field.call("get_spawn_position"))
	var wanderer: Node3D = _field.get_node("Wanderer")
	var pair: Array = BEHIND[WALK_FLOOR][0]
	var from_rel: Vector2 = pair[0]
	var to_rel: Vector2 = pair[1]
	var start: Vector2 = spawn + from_rel
	var nav: Object = _field.call("get_nav_grid")
	var height: float = float(nav.call("height_at_cell", nav.call("world_to_cell", start)))
	wanderer.global_position = Vector3(start.x, height + 0.1, start.y)
	for i in 10:
		await physics_frame
	var goal := Vector3(spawn.x + to_rel.x, 0.0, spawn.y + to_rel.y)
	_field.call("walk_to", goal)
	await _walk(wanderer, 30.0)
	var off: float = _flat(wanderer.global_position).distance_to(_flat(goal))
	_expect(off < 0.6, "Floor %d: walked round the dune, he gets there (%.2f m off)" % [WALK_FLOOR + 1, off])
	await _teardown()
	_completed += 1

# --- Helpers ---

func _plan(from: Vector2, to: Vector2) -> PackedVector3Array:
	var nav: Object = _field.call("get_nav_grid")
	var height: float = float(nav.call("height_at_cell", nav.call("world_to_cell", from)))
	# With the enemies' zones, as a click plans it.
	return _field.call("plan_path", Vector3(from.x, height, from.y), Vector3(to.x, 0.0, to.y), null, true)

# Every cell reachable from `start` over open cells: 8-way, a diagonal
# only when both cells beside it are open (DIAGONAL_MODE_ONLY_IF_NO_
# OBSTACLES). 1 = reached.
func _flood(nav: Object, start: Vector2i) -> PackedByteArray:
	var cols: int = nav.get("cols")
	var rows: int = nav.get("rows")
	var open := PackedByteArray()
	open.resize(cols * rows)
	for z in rows:
		for x in cols:
			open[z * cols + x] = 1 if bool(nav.call("is_open", Vector2i(x, z))) else 0
	var reached := PackedByteArray()
	reached.resize(cols * rows)
	if open[start.y * cols + start.x] == 0:
		return reached
	var queue: Array[int] = [start.y * cols + start.x]
	reached[queue[0]] = 1
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x: int = i % cols
		var z: int = i / cols
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var nx: int = x + dx
				var nz: int = z + dz
				if nx < 0 or nz < 0 or nx >= cols or nz >= rows:
					continue
				var n: int = nz * cols + nx
				if open[n] == 0 or reached[n] == 1:
					continue
				if dx != 0 and dz != 0 and (open[z * cols + nx] == 0 or open[nz * cols + x] == 0):
					continue
				reached[n] = 1
				queue.append(n)
	return reached

# The floor's ledge lines as closed world-XZ loops.
func _ledge_loops(spawn: Vector2) -> Array:
	var loops: Array = []
	for ledge: PackedVector2Array in (_field.call("get_floor_data") as Resource).get("ledges"):
		var loop := PackedVector2Array()
		for point in ledge:
			loop.append(point + spawn)
		loops.append(loop)
	return loops

# Inside every loop that holds spawn, and outside every loop that doesn't.
func _on_mainland(point: Vector2, loops: Array, spawn: Vector2) -> bool:
	for loop: PackedVector2Array in loops:
		if Geometry2D.is_point_in_polygon(spawn, loop) != Geometry2D.is_point_in_polygon(point, loop):
			return false
	return true

func _relative(path: PackedVector3Array, spawn: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in path:
		out.append(_flat(point) - spawn)
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

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
