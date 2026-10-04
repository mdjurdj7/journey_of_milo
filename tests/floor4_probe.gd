extends SceneTree

# Headless probe for floor 4, the loop round the central dune: its data
# and its place in Region 1, then the loop walked for real - the
# Wanderer clicked from waypoint to waypoint (Wanderer.set_move_target())
# through the physics, as a player would:
#
#   west   - spawn, out of the entry neck, round the dune's west side, to
#            the required fight: contact starts it
#   east   - the same by the east side: the narrows, past the collector's
#            bay, the north arc
#   dune   - straight at the far side across the dune, from the west and
#            from the south: he never gets over it
#   exit   - from the west side toward the exit while the required fight
#            stands: he comes to rest on the gate line and the floor holds;
#            won, the line lifts and he walks out - the last floor, so the
#            run wraps to floor 1
#
# The routes keep clear of the optional fight (its contact area is 2 m;
# the west side passes it at 3 m), so the only fight either starts is the
# required one.
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/floor4_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const CASES := 5
const REGION_PATH := "res://floors/region1.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const FLOOR_4_PATH := "res://floors/region1_floor4.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_INDEX := 3
const REQUIRED_AT := Vector2(-13.5, -32.267)
const OPTIONAL_AT := Vector2(-17.267, -18.0)
const WEST: Array[Vector2] = [Vector2(0, -4.5), Vector2(-6, -9), Vector2(-11.5, -13), Vector2(-14.2, -18), Vector2(-15.5, -24), Vector2(-16.5, -28)]
const EAST: Array[Vector2] = [Vector2(0, -4.5), Vector2(7, -9), Vector2(14, -12.5), Vector2(17.5, -19), Vector2(17.5, -26), Vector2(14.5, -31.5), Vector2(7, -34), Vector2(0, -35), Vector2(-7, -34.5), Vector2(-10, -33.5)]
# Metres short of a waypoint that count as there.
const REACH_M := 1.0
const WAYPOINT_SECONDS := 12.0
const FIGHT_SECONDS := 8.0
const DUNE_SECONDS := 8.0
# How far onto the dune he may get: its walkable edge where each walk
# meets it (x -13.37 at z -21 from the west, z -11.43 at x 0 from the
# south) plus the ledge barrier's 0.4 m up its face and 0.1 m to spare.
const DUNE_WEST_LIMIT_X := -12.87
const DUNE_SOUTH_LIMIT_Z := -11.93
# The optional fight's contact area is 2 m; the narrow west side passes
# it at 3 m, the middle of the ring.
const OPTIONAL_CLEARANCE_M := 3.0
const OVERSHOOT_LIMIT_M := 0.02
const SAFETY_SECONDS := 400.0

var _run_state: Node = null
var _field: Node3D = null
var _wanderer: CharacterBody3D = null
# Where he spawned - RegionField.get_spawn_position() is his own position,
# so it is read once, at the load, before he moves.
var _spawn: Vector3 = Vector3.ZERO
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_check_data()
	await _check_route("west", WEST)
	await _check_route("east", EAST)
	await _check_dune()
	await _check_exit()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("floor4_probe: PASSED")
		quit(0)
	else:
		print("floor4_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var region: Resource = load(REGION_PATH)
	var floors: Array = region.get("floors")
	_expect_eq(floors.size(), 4, "Region 1 has four floors")
	_expect(floors.size() == 4 and floors[2].resource_path == FLOOR_3_PATH and floors[3].resource_path == FLOOR_4_PATH, "...floor 4 after floor 3")
	var data: Resource = load(FLOOR_4_PATH)
	_expect_eq(data.get("elevation_max_height"), 3.0, "Floor 4 reads its elevation at 3.0 m")
	_expect_eq(int(data.get("exit_kind")), 1, "...a LINE gate")
	var enemies: Array = data.get("enemies")
	_expect_eq(enemies.size(), 2, "...two fights")
	if enemies.size() == 2:
		_expect(bool(enemies[0].get("required")) and enemies[0].get("position") == REQUIRED_AT, "...the required one first, at the rejoin")
		_expect(not bool(enemies[1].get("required")) and enemies[1].get("position") == OPTIONAL_AT, "...the optional one on the west side")
		for entry in enemies:
			_expect((entry.get("enemy_data") as Resource).resource_path == SPUTTER_PATH, "...both the Sputter placeholder")
	_expect_eq((data.get("ledges") as Array).size(), 2, "...two ledge rings: the boundary and the dune")
	_expect_eq((data.get("wear_path_override") as PackedVector2Array).size(), 8, "...an 8-point worn band")
	_completed += 1

# Spawn to the required fight by one side: every waypoint reached, then
# the fight itself walked into.
func _check_route(label: String, waypoints: Array[Vector2]) -> void:
	await _load()
	for point in waypoints:
		_expect(_distance_2d(point, OPTIONAL_AT) >= OPTIONAL_CLEARANCE_M, "%s: waypoint %s keeps clear of the optional fight" % [label, point])
		var reached: bool = await _walk_to(point)
		_expect(reached, "%s: reaches %s (stopped at %s)" % [label, point, _at()])
		if not reached:
			break
	var required: Node = _required_enemy()
	if required != null:
		_wanderer.call("set_move_target_enemy", required)
		var started: bool = false
		for i in int(FIGHT_SECONDS * 60.0):
			await physics_frame
			if _field.get_node("BattleLayer").get_child_count() > 0:
				started = true
				break
		_expect(started, "%s: walking on, he meets the required fight" % label)
		if started:
			var overlay: Node = _field.get_node("BattleLayer").get_child(0)
			var members: Array = overlay.get("battle_controller").get("enemies")
			_expect(members.size() == 1 and members[0] == required, "%s: ...and only it" % label)
	await _unload()
	_completed += 1

# Straight across the dune from either side: he never gets over it.
func _check_dune() -> void:
	await _load()
	await _place(Vector2(-17.5, -21))
	_wanderer.call("set_move_target", _world(Vector2(17, -21)))
	var furthest_x: float = -INF
	for i in int(DUNE_SECONDS * 60.0):
		await physics_frame
		furthest_x = maxf(furthest_x, _at().x)
	_expect(furthest_x < DUNE_WEST_LIMIT_X, "From the west side straight east: held at the dune's foot (furthest x %.2f)" % furthest_x)
	await _place(Vector2(0, -6))
	_wanderer.call("set_move_target", _world(Vector2(0, -35)))
	var furthest_z: float = INF
	for i in int(DUNE_SECONDS * 60.0):
		await physics_frame
		furthest_z = minf(furthest_z, _at().y)
	print("dune: furthest x %.2f from the west, furthest z %.2f from the south" % [furthest_x, furthest_z])
	_expect(furthest_z > DUNE_SOUTH_LIMIT_Z, "From the south straight north: held at the dune's foot (furthest z %.2f)" % furthest_z)
	await _unload()
	_completed += 1

# The exit held while the required fight stands, then open once it is won.
func _check_exit() -> void:
	await _load()
	var gate: Node3D = _field.get_node("ExitGate")
	var forward: Vector3 = -gate.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var exited: Array[bool] = [false]
	gate.connect("floor_exited", func() -> void: exited[0] = true)
	_expect(bool(_wanderer.call("has_hold_line")), "Floor 4 holds a line while the required fight stands")
	await _place(Vector2(-16, -27.5))
	_expect(await _walk_to(Vector2(-17.5, -34)), "...walks to the mouth of the exit neck (stopped at %s)" % _at())
	_wanderer.call("set_move_target", _world(Vector2(-29.5, -38.5)))
	var worst: float = -INF
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		worst = maxf(worst, (_wanderer.global_position - gate.global_position).dot(forward))
	_expect(worst <= OVERSHOOT_LIMIT_M, "...he never crosses the gate line (worst %+.3f m)" % worst)
	_expect(worst > -0.5, "...he comes to rest on it (%+.3f m)" % worst)
	_expect(not exited[0], "...and the floor doesn't exit")
	# The fight, won.
	var required: Node = _required_enemy()
	_field.call_deferred("_on_enemy_contacted", required)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("the required fight didn't start")
	else:
		var controller: Node = layer.get_child(0).get("battle_controller")
		var combatants: Dictionary = controller.get("_combatants")
		for member in (controller.get("enemies") as Array).duplicate():
			var combatant: RefCounted = combatants.get(member)
			combatant.set("hp", 0)
			controller.call("_report_damage", "player", combatant, 99, "card")
		controller.call("_check_battle_end")
		await create_timer(1.6).timeout
		var reward: Node = _child_with_script(_field, "reward_screen.gd")
		if reward != null:
			reward.call("close")
		for i in 30:
			await physics_frame
		_expect(not bool(_wanderer.call("has_hold_line")), "Won: the line lifts")
		var floor_before: int = int(_run_state.get("current_floor_index"))
		_wanderer.call("set_move_target", _world(Vector2(-29.5, -38.5)))
		for i in int(WAYPOINT_SECONDS * 60.0):
			await physics_frame
			if exited[0]:
				break
		_expect(exited[0], "...and he walks out through the exit neck")
		_expect_eq(floor_before, FLOOR_INDEX, "...from floor 4")
		# The look up to the tower and the fade come first (RegionField._on_
		# floor_exited()), then the floor changes and the scene reloads.
		for i in 8 * 60:
			if int(_run_state.get("current_floor_index")) != FLOOR_INDEX:
				break
			await process_frame
		_expect_eq(int(_run_state.get("current_floor_index")), 0, "...the last floor: the run wraps to floor 1")
		for i in 10:
			await process_frame
		var reloaded: Node = current_scene
		if reloaded != null and reloaded != _field:
			reloaded.queue_free()
		current_scene = null
	await _unload()
	_completed += 1

# --- Helpers ---

func _load() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_INDEX)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_field)
	for i in 30:
		await physics_frame
	_wanderer = _field.get_node("Wanderer") as CharacterBody3D
	_spawn = _field.call("get_spawn_position")
	current_scene = _field

func _unload() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	_wanderer = null
	for i in 5:
		await physics_frame

# Spawn-relative XZ to world, on the ground.
func _world(point: Vector2) -> Vector3:
	var spawn: Vector3 = _spawn
	var x: float = spawn.x + point.x
	var z: float = spawn.z + point.y
	var ground: Node3D = _field.get_node("Ground")
	var local: Vector3 = ground.to_local(Vector3(x, 0.0, z))
	return Vector3(x, float(ground.call("get_height_at", Vector2(local.x, local.z))), z)

# The Wanderer's spawn-relative XZ.
func _at() -> Vector2:
	var spawn: Vector3 = _spawn
	return Vector2(_wanderer.global_position.x - spawn.x, _wanderer.global_position.z - spawn.z)

func _place(point: Vector2) -> void:
	_wanderer.call("clear_move_target")
	_wanderer.global_position = _world(point) + Vector3.UP * 0.05
	_wanderer.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame

func _walk_to(point: Vector2) -> bool:
	_wanderer.call("set_move_target", _world(point))
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		if _distance_2d(_at(), point) <= REACH_M:
			return true
		if not bool(_wanderer.call("has_move_target")) and i > 10:
			break
	return _distance_2d(_at(), point) <= REACH_M

func _required_enemy() -> Node:
	for node in get_nodes_in_group("enemies"):
		if bool(node.get("required")):
			return node
	_fail("no required enemy on floor 4")
	return null

func _distance_2d(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)

func _child_with_script(parent: Node, suffix: String) -> Node:
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
