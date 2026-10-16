extends SceneTree

# Headless probe for floor 4: its place in Region 1, its encounters and
# props inside its ledge lines, and the floor played - the Wanderer
# moved through the physics, as a player would:
#
#   exit     - past the required fight (put there, just outside its
#              contact area, along the exit) toward the exit while it
#              stands: he comes to rest on the gate line and the floor
#              holds; won, the line lifts and he walks out, on to floor 5
#   collector - walked to from spawn on a planned path: he reaches the
#              collector, in reach to open it, and no fight starts
#   feeding  - the Dunecur faces its bones; the gate stands
#              gate_distance_beyond_enemy past him along exit_direction;
#              every bone on the near side of the gate line, each sunk
#              only part way into the sand
#
# Where anything stands is not this probe's to say - only that it stands
# on the floor: inside the outer ledge line and outside every other.
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/floor4_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const CASES := 4
const REGION_PATH := "res://floors/region1.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const FLOOR_4_PATH := "res://floors/region1_floor4.tres"
const FLOOR_5_PATH := "res://floors/region1_floor5.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_INDEX := 3
# Put past the required fight: this far beyond its contact area's edge,
# along the exit.
const PAST_CONTACT_M := 0.9
# Walked toward: this far past the gate line.
const BEYOND_GATE_M := 4.0
const WAYPOINT_SECONDS := 12.0
const COLLECTOR_SECONDS := 20.0
const OVERSHOOT_LIMIT_M := 0.02
const SAFETY_SECONDS := 400.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0

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
	await _check_exit()
	await _check_collector()
	await _check_feeding_spot()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("floor4_probe: PASSED")
		quit(0)
	else:
		print("floor4_probe: %d FAILED" % _failures)
		quit(1)

# Floor 4 in Region 1's order; a required fight and an optional elite;
# every member, encounter prop and floor prop on the floor.
func _check_data() -> void:
	var region: Resource = load(REGION_PATH)
	var floors: Array = region.get("floors")
	_expect(floors.size() == 5 and floors[2].resource_path == FLOOR_3_PATH and floors[3].resource_path == FLOOR_4_PATH and floors[4].resource_path == FLOOR_5_PATH, "Floor 4 after floor 3, before floor 5")
	var data: Resource = load(FLOOR_4_PATH)
	var ledges: Array = data.get("ledges")
	var required: int = 0
	var elites: int = 0
	for slot: Resource in data.get("slots"):
		for option: Resource in slot.get("options"):
			for member: Resource in option.get("members"):
				var at: Vector2 = slot.call("to_floor", member.get("position"))
				_expect(_on_floor(at, ledges), "%s stands on the floor (%s)" % [(member.get("enemy_data") as Resource).get("enemy_name"), at])
				if bool(slot.get("required")):
					required += 1
				elif bool((member.get("enemy_data") as Resource).get("is_elite")):
					elites += 1
			for prop: Resource in option.get("props"):
				var prop_at: Vector3 = prop.get("position")
				var prop_floor: Vector2 = slot.call("to_floor", Vector2(prop_at.x, prop_at.z))
				_expect(_on_floor(prop_floor, ledges), "Slot %s's prop stands on the floor (%s)" % [slot.get("slot_id"), prop_floor])
	_expect(required >= 1, "Floor 4 has a required fight")
	_expect(elites >= 1, "...and an optional elite")
	for prop: Resource in data.get("props"):
		var floor_at: Vector3 = prop.get("position")
		_expect(_on_floor(Vector2(floor_at.x, floor_at.z), ledges), "A floor prop stands on the floor (%s)" % Vector2(floor_at.x, floor_at.z))
	_completed += 1

# The exit held while the required fight stands, then open once it is won.
func _check_exit() -> void:
	await _load()
	var gate: Node3D = _field.get_node("ExitGate")
	var forward: Vector3 = -gate.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var beyond: Vector3 = gate.global_position + forward * BEYOND_GATE_M
	var exited: Array[bool] = [false]
	gate.connect("floor_exited", func() -> void: exited[0] = true)
	_expect(bool(_wanderer.call("has_hold_line")), "Floor 4 holds a line while the required fight stands")
	var required: Node3D = _required_enemy() as Node3D
	if required != null:
		var past: Vector3 = required.global_position + forward * (float(required.get("contact_radius")) + PAST_CONTACT_M)
		await _place(Vector2(past.x - _spawn.x, past.z - _spawn.z))
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...put past the required fight, no fight starts")
	_wanderer.call("set_move_target", beyond)
	var worst: float = -INF
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		worst = maxf(worst, (_wanderer.global_position - gate.global_position).dot(forward))
	_expect(worst <= OVERSHOOT_LIMIT_M, "...he never crosses the gate line (worst %+.3f m)" % worst)
	_expect(worst > -0.5, "...he comes to rest on it (%+.3f m)" % worst)
	_expect(not exited[0], "...and the floor doesn't exit")
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...nor does walking on from past it start the fight")
	# The fight, won.
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
		await _await_reward_screen()
		var reward: Node = _child_with_script(_field, "reward_screen.gd")
		if reward != null:
			reward.call("close")
		for i in 30:
			await physics_frame
		_expect(not bool(_wanderer.call("has_hold_line")), "Won: the line lifts")
		var floor_before: int = int(_run_state.get("current_floor_index"))
		_wanderer.call("set_move_target", beyond)
		for i in int(WAYPOINT_SECONDS * 60.0):
			await physics_frame
			if exited[0]:
				break
		_expect(exited[0], "...and he walks out")
		_expect_eq(floor_before, FLOOR_INDEX, "...from floor 4")
		# The look up to the tower and the fade come first (RegionField._on_
		# floor_exited()), then the floor changes and the scene reloads.
		for i in 8 * 60:
			if int(_run_state.get("current_floor_index")) != FLOOR_INDEX:
				break
			await process_frame
		_expect_eq(int(_run_state.get("current_floor_index")), FLOOR_INDEX + 1, "...on to floor 5")
		for i in 10:
			await process_frame
		var reloaded: Node = current_scene
		if reloaded != null and reloaded != _field:
			reloaded.queue_free()
		current_scene = null
	await _unload()
	_completed += 1

# The collector reachable: walked to from spawn on a planned path
# (RegionField.plan_path()), he comes in reach to open it, and no fight
# starts on the way.
func _check_collector() -> void:
	await _load()
	var collectors: Array[Node] = get_nodes_in_group("collectors")
	_expect_eq(collectors.size(), 1, "One collector on floor 4")
	if collectors.size() == 1:
		var collector: Node3D = collectors[0] as Node3D
		var path: PackedVector3Array = _field.call("plan_path", _wanderer.global_position, collector.global_position, null, true)
		_expect(not path.is_empty(), "...a path to it from spawn")
		_wanderer.call("set_move_path", path)
		var in_reach: bool = false
		for i in int(COLLECTOR_SECONDS * 60.0):
			await physics_frame
			if bool(collector.call("can_open_from", _wanderer.global_position)):
				in_reach = true
				break
		_expect(in_reach, "...walked to from spawn, he comes in reach to open it (stopped at %s)" % _at())
		for i in 30:
			await physics_frame
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...and no fight starts")
	await _unload()
	_completed += 1

# The Dunecur over his bones: facing them; the gate gate_distance_beyond_
# enemy past him along exit_direction, every bone on the near side of
# its line, each sunk only part way into the sand.
func _check_feeding_spot() -> void:
	await _load()
	var required: Node3D = _required_enemy() as Node3D
	var gate: Node3D = _field.get_node("ExitGate")
	var bones: Array[Node] = _field.find_children("*", "BoneScatter", true, false)
	_expect_eq(bones.size(), 1, "One bone scatter on floor 4")
	if required != null and bones.size() == 1:
		var data: Resource = load(FLOOR_4_PATH)
		var scatter: Node3D = bones[0] as Node3D
		var to_bones := Vector2(scatter.global_position.x - required.global_position.x, scatter.global_position.z - required.global_position.z).normalized()
		var facing: Vector3 = -required.global_transform.basis.z
		var forward := Vector2(facing.x, facing.z).normalized()
		_expect(forward.dot(to_bones) > 0.999, "The Dunecur faces his bones (%s)" % forward)
		var exit_direction: Vector2 = (data.get("exit_direction") as Vector2).normalized()
		var expected_gate: Vector2 = Vector2(required.global_position.x, required.global_position.z) + exit_direction * float(data.get("gate_distance_beyond_enemy"))
		var gate_xz := Vector2(gate.global_position.x, gate.global_position.z)
		_expect(gate_xz.distance_to(expected_gate) < 0.01, "The gate stands gate_distance_beyond_enemy past him along the exit (%s)" % gate_xz)
		var gate_forward: Vector3 = -gate.global_transform.basis.z
		var pieces: PackedVector3Array = scatter.call("get_piece_positions")
		_expect(pieces.size() > 0, "...bones in the scatter")
		var nearest: float = INF
		for piece in pieces:
			nearest = minf(nearest, -(piece - gate.global_position).dot(Vector3(gate_forward.x, 0.0, gate_forward.z).normalized()))
		_expect(nearest > 0.0, "...every one on the near side of the gate line (nearest %.2f m)" % nearest)
		var ground: Node3D = _field.get_node("Ground")
		var worst_sink: float = INF
		for piece in pieces:
			var local: Vector3 = ground.to_local(piece)
			worst_sink = minf(worst_sink, piece.y - float(ground.call("get_height_at", Vector2(local.x, local.z))))
		_expect(worst_sink > -0.05, "...each sunk only part way into the sand (lowest centre %+.3f m)" % worst_sink)
	await _unload()
	_completed += 1

# --- Helpers ---

# On the floor: inside the first ledge line (its boundary) and outside
# every other (what stands up out of it - the dune).
func _on_floor(point: Vector2, ledges: Array) -> bool:
	if ledges.is_empty():
		return true
	if not Geometry2D.is_point_in_polygon(point, ledges[0]):
		return false
	for i in range(1, ledges.size()):
		if Geometry2D.is_point_in_polygon(point, ledges[i]):
			return false
	return true

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

func _required_enemy() -> Node:
	for node in get_nodes_in_group("enemies"):
		if bool(node.get("required")):
			return node
	_fail("no required enemy on floor 4")
	return null

# A fight just won: until its reward screen is up - the killing blow and
# the last death play out first - or REWARD_WAIT_SECONDS have gone.
func _await_reward_screen() -> void:
	var start: int = Time.get_ticks_msec()
	while _child_with_script(_field, "reward_screen.gd") == null and Time.get_ticks_msec() - start < int(REWARD_WAIT_SECONDS * 1000.0):
		await process_frame

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
