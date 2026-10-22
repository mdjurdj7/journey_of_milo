extends SceneTree

# Core probe: every floor of the region (its FloorData) loads and can be
# walked. Per floor, the real region scene:
#
#   loads    - the field, its Wanderer, its exit gate and its walk grid
#   walkable - a planned path from spawn to the exit gate (short of its
#              centre, or of the nearest point along its line that the
#              grid reaches - a LINE gate spans the floor), reaching it and
#              never in deep water
#   grounded - every enemy's body stands where its own ground rule puts it
#              (the relief under it, less its model_ground_offset, plus its
#              height_offset - all read off the body), a seated rider at
#              its ride offset on its carrier; no prop floats: the
#              bottom of what it draws is at or under the ground at its
#              origin, within GROUND_TOLERANCE_M
#
# Nothing pinned: no positions, counts or composition. Run alone, once,
# for a change to floor data (FloorData/RegionData, masks, floor props); in
# the core set for code. A script error fails it too (tools/run_probes.sh).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/floor_smoke_probe.gd
#
# Exit code 0 = every floor passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const REGION_PATH := "res://floors/region1.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
# How far an enemy's body may stand off its ground rule, and a prop's
# drawn bottom over the ground, metres.
const BODY_TOLERANCE_M := 0.05
const GROUND_TOLERANCE_M := 0.15
# Short of the gate's centre, metres, toward spawn.
const GATE_SHORT_M := 2.0
# Sampling a path, metres.
const STEP := 0.1
const SAFETY_SECONDS := 240.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _floors_clean: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var floors: Array = (load(REGION_PATH) as Resource).get("floors")
	for floor_index in floors.size():
		await _check_floor(floor_index)
	print("floor_smoke_probe: %d of %d floors clean" % [_floors_clean, floors.size()])
	if _failures == 0:
		print("floor_smoke_probe: PASSED")
		quit(0)
	else:
		print("floor_smoke_probe: %d FAILED" % _failures)
		quit(1)

func _check_floor(floor_index: int) -> void:
	var label: String = "Floor %d" % (floor_index + 1)
	var failures_before: int = _failures
	print("\n=== %s" % label)
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	root.add_child(_field)
	for i in 40:
		await physics_frame
	# --- loads ---
	var wanderer: Node3D = _field.get_node_or_null("Wanderer") as Node3D
	var gate: Node3D = _field.get_node_or_null("ExitGate") as Node3D
	var ground: Node3D = _field.get_node_or_null("Ground") as Node3D
	var nav: Object = _field.call("get_nav_grid")
	_expect(wanderer != null and gate != null and ground != null and nav != null, "%s: loads with its Wanderer, exit gate, ground and walk grid" % label)
	if wanderer == null or gate == null or ground == null or nav == null:
		await _teardown()
		return
	# --- walkable ---
	var spawn: Vector3 = _field.call("get_spawn_position")
	var exit_dir: Vector3 = _field.call("get_exit_direction")
	var target: Vector3 = _short_of_gate(spawn, gate.global_position - exit_dir * GATE_SHORT_M, exit_dir)
	var path: PackedVector3Array = _field.call("plan_path", spawn, target, null, false)
	_expect(path.size() >= 2 and _flat(path[path.size() - 1]).distance_to(_flat(target)) < 0.5, "%s: a path from spawn reaches the exit" % label)
	var deep: int = 0
	for sample in _samples(path):
		if bool(nav.call("is_deep", nav.call("world_to_cell", sample))):
			deep += 1
	_expect(deep == 0, "%s: ...never in deep water (%d samples)" % [label, deep])
	# --- grounded ---
	var enemies: int = 0
	for node in get_nodes_in_group("enemies"):
		if not _field.is_ancestor_of(node):
			continue
		enemies += 1
		var body: Node3D = node as Node3D
		# A seated rider's ground is its carrier: it sits at its ride offset
		# on the carrier's body, which is checked on its own.
		if bool(body.call("is_seated")):
			var carrier: Node3D = body.call("get_carrier") as Node3D
			var seat: Vector3 = carrier.global_transform * (body.get("_ride_offset") as Vector3) if carrier != null else Vector3.INF
			_expect(carrier != null and body.global_position.distance_to(seat) <= BODY_TOLERANCE_M, "%s: %s sits on its carrier (%.2f m off its seat)" % [label, body.name, body.global_position.distance_to(seat) if carrier != null else INF])
			continue
		var local: Vector3 = ground.to_local(body.global_position)
		var expected: float = float(ground.call("get_height_at", Vector2(local.x, local.z))) - float(body.get("model_ground_offset")) + float(body.get("height_offset"))
		_expect(absf(body.global_position.y - expected) <= BODY_TOLERANCE_M, "%s: %s stands on its ground (%.2f m off)" % [label, body.name, body.global_position.y - expected])
	var props: int = 0
	var holder: Node = _field.get_node_or_null(^"Props")
	if holder != null:
		for child in holder.get_children():
			var prop: Node3D = child as Node3D
			if prop == null:
				continue
			var bounds: AABB = _drawn_bounds(prop)
			if not bounds.has_volume():
				continue
			props += 1
			var local: Vector3 = ground.to_local(prop.global_position)
			var under: float = float(ground.call("get_height_at", Vector2(local.x, local.z)))
			_expect(bounds.position.y <= under + GROUND_TOLERANCE_M, "%s: the prop %s doesn't float (its bottom %.2f m over the ground)" % [label, prop.name, bounds.position.y - under])
	print("%s: %d enemies, %d props checked" % [label, enemies, props])
	if _failures == failures_before:
		_floors_clean += 1
	await _teardown()

# Short of the gate's centre where the grid reaches it, else the nearest
# point along its line that it does.
func _short_of_gate(spawn: Vector3, centre: Vector3, exit_dir: Vector3) -> Vector3:
	var across := Vector3(-exit_dir.z, 0.0, exit_dir.x)
	for i in 161:
		var offset: float = ceilf(float(i) / 2.0) * 0.5 * (1.0 if i % 2 == 1 else -1.0)
		var point: Vector3 = centre + across * offset
		var path: PackedVector3Array = _field.call("plan_path", spawn, point, null, false)
		if path.size() >= 2 and _flat(path[path.size() - 1]).distance_to(_flat(point)) < 0.5:
			return point
	return centre

# Everything `node` draws, in world space - each mesh's own AABB through
# its global transform.
func _drawn_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first: bool = true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		stack.append_array(current.get_children())
		var visual := current as VisualInstance3D
		if visual == null or not visual.visible:
			continue
		var box: AABB = visual.global_transform * visual.get_aabb()
		if first:
			bounds = box
			first = false
		else:
			bounds = bounds.merge(box)
	return bounds

func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)

func _samples(path: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, path.size()):
		var a: Vector2 = _flat(path[i - 1])
		var b: Vector2 = _flat(path[i])
		var steps: int = maxi(int(ceil(a.distance_to(b) / STEP)), 1)
		for s in steps + 1:
			out.append(a.lerp(b, float(s) / float(steps)))
	return out

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
