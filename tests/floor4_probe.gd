extends SceneTree

# Headless probe for floor 4, the loop round the central dune: its data
# and its place in Region 1, then the loop walked for real - the
# Wanderer clicked from waypoint to waypoint (Wanderer.set_move_target())
# through the physics, as a player would:
#
#   west   - spawn, out of the entry neck, round the dune's west side, to
#            the required fight - the Dunecur at the mouth of the exit neck,
#            over its bones: contact starts it
#   east   - the same by the east side: the narrows, past the optional
#            fight's bay, the north arc
#   dune   - straight at the far side across the dune, from the west and
#            from the south: he never gets over it
#   exit   - past the Dunecur (put there - his 3 m contact area all but
#            fills the neck) toward the exit while he stands: he comes to
#            rest on the gate line and the floor holds; won, the line lifts
#            and he walks out, on to floor 5
#   alcove - the collector's alcove off the west side, beside the worn
#            band: walked into from the route, he reaches the collector
#            and no fight starts
#
# The optional fight - the Adder, an elite - stands in the east bay, off
# the walking line: every leg of both routes passes its 2 m contact area
# at least 4 m clear, and it never fires - the only fight a route starts
# is the required one.
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/floor4_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const CASES := 7
const REGION_PATH := "res://floors/region1.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const FLOOR_4_PATH := "res://floors/region1_floor4.tres"
const FLOOR_5_PATH := "res://floors/region1_floor5.tres"
const ADDER_PATH := "res://battle/rules/enemies/adder.tres"
const DUNECUR_PATH := "res://battle/rules/enemies/dunecur.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_INDEX := 3
const REQUIRED_AT := Vector2(-18.5, -35.0)
const BONES_AT := Vector2(-19.73, -35.422)
const EXIT_DIRECTION := Vector2(-0.9459, -0.3245)
const GATE_DISTANCE_M := 7.0
# Past the Dunecur, 3.9 m on toward the gate - outside his contact area.
const PAST_REQUIRED := Vector2(-22.2, -36.3)
# Every bone this far short of the gate line, at least.
const BONES_GATE_CLEARANCE_M := 3.0
const OPTIONAL_AT := Vector2(11, -22.5)
# Facing east, out of the bay's mouth, away from the worn band.
const OPTIONAL_YAW := -90.0
# The collector, in the west alcove beside the worn band, facing north
# along it - its back to the approach.
const COLLECTOR_AT := Vector3(-24.4, 0, -21.6)
const COLLECTOR_YAW := -6.3
const WEST: Array[Vector2] = [Vector2(0, -4.5), Vector2(-6, -9), Vector2(-11.5, -13), Vector2(-16.5, -18), Vector2(-16.8, -24), Vector2(-16.5, -28)]
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
# The optional fight's contact area, and how far clear of it every leg of
# a route stays.
const CONTACT_RADIUS_M := 2.0
const OPTIONAL_CLEARANCE_M := 4.0
# From the west side into the alcove: its mouth, 3.4 m short of the
# collector.
const ALCOVE_FROM := Vector2(-16.8, -21)
const ALCOVE_MOUTH := Vector2(-21.0, -21.4)
const COLLECTOR_SECONDS := 8.0
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
	await _check_alcove()
	await _check_feeding_spot()
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
	_expect_eq(floors.size(), 5, "Region 1 has five floors")
	_expect(floors.size() == 5 and floors[2].resource_path == FLOOR_3_PATH and floors[3].resource_path == FLOOR_4_PATH and floors[4].resource_path == FLOOR_5_PATH, "...floor 4 after floor 3, before floor 5")
	var data: Resource = load(FLOOR_4_PATH)
	_expect_eq(data.get("elevation_max_height"), 3.0, "Floor 4 reads its elevation at 3.0 m")
	_expect_eq(int(data.get("exit_kind")), 1, "...a LINE gate")
	var enemies: Array = data.get("enemies")
	_expect_eq(enemies.size(), 2, "...two fights")
	if enemies.size() == 2:
		_expect(bool(enemies[0].get("required")) and enemies[0].get("position") == REQUIRED_AT, "...the required one first, at the mouth of the exit neck")
		_expect((enemies[0].get("enemy_data") as Resource).resource_path == DUNECUR_PATH, "...the Dunecur")
		_expect_eq(int(enemies[0].get("face_prop_index")), 0, "...facing the bones")
		_expect(not bool(enemies[1].get("required")) and enemies[1].get("position") == OPTIONAL_AT, "...the optional one in the east bay")
		_expect(is_equal_approx(float(enemies[1].get("yaw_degrees")), OPTIONAL_YAW), "...facing east, out of the bay's mouth")
		_expect((enemies[1].get("enemy_data") as Resource).resource_path == ADDER_PATH, "...the Adder")
		_expect(bool((enemies[1].get("enemy_data") as Resource).get("is_elite")), "...an elite")
		_expect(is_equal_approx(float((enemies[1].get("enemy_data") as Resource).get("contact_radius_m")), CONTACT_RADIUS_M), "...its contact area the 2 m the routes are measured against")
	var props: Array = data.get("props")
	_expect(props.size() == 2 and (props[0].get("scene") as Resource).resource_path == "res://field/bone_scatter.tscn", "...two props: the bones first (the Dunecur faces index 0)")
	_expect(props.size() == 2 and (props[1].get("scene") as Resource).resource_path == "res://field/collector.tscn", "...then the collector")
	_expect(props.size() == 2 and props[1].get("position") == COLLECTOR_AT, "...in the west alcove beside the worn band")
	_expect(props.size() == 2 and is_equal_approx(float(props[1].get("yaw_degrees")), COLLECTOR_YAW), "...facing north along it")
	_expect(data.get("exit_direction") == EXIT_DIRECTION and is_equal_approx(float(data.get("gate_distance_beyond_enemy")), GATE_DISTANCE_M), "...the gate 7 m on along the exit neck")
	_expect_eq((data.get("ledges") as Array).size(), 2, "...two ledge rings: the boundary and the dune")
	_expect_eq((data.get("wear_path_override") as PackedVector2Array).size(), 8, "...an 8-point worn band")
	_completed += 1

# Spawn to the required fight by one side: every waypoint reached, then
# the fight itself walked into.
func _check_route(label: String, waypoints: Array[Vector2]) -> void:
	await _load()
	var leg_start: Vector2 = Vector2.ZERO
	for point in waypoints:
		var clear: float = _segment_distance(OPTIONAL_AT, leg_start, point) - CONTACT_RADIUS_M
		_expect(clear >= OPTIONAL_CLEARANCE_M, "%s: the leg to %s passes the optional fight's contact area %.1f m clear (>= %.1f)" % [label, point, clear, OPTIONAL_CLEARANCE_M])
		leg_start = point
	var optional: Node = _optional_enemy()
	var fired: Array[bool] = [false]
	if optional != null:
		optional.connect("contacted", func(_enemy: Node) -> void: fired[0] = true)
	for point in waypoints:
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
	_expect(not fired[0], "%s: the optional fight never fires" % label)
	await _unload()
	_completed += 1

# The alcove is reachable: from the west side to its mouth, then on to
# the collector, in reach to open it, and no fight starts on the way.
func _check_alcove() -> void:
	await _load()
	await _place(ALCOVE_FROM)
	var reached: bool = await _walk_to(ALCOVE_MOUTH)
	_expect(reached, "The alcove's mouth is reachable from the west side (stopped at %s)" % _at())
	var collectors: Array[Node] = get_nodes_in_group("collectors")
	_expect_eq(collectors.size(), 1, "...one collector on floor 4")
	if collectors.size() == 1:
		var collector: Node3D = collectors[0] as Node3D
		_wanderer.call("set_move_target", _world(Vector2(COLLECTOR_AT.x, COLLECTOR_AT.z)))
		var in_reach: bool = false
		for i in int(COLLECTOR_SECONDS * 60.0):
			await physics_frame
			if bool(collector.call("can_open_from", _wanderer.global_position)):
				in_reach = true
				break
		_expect(in_reach, "...and walking on into the alcove reaches the collector (stopped at %s)" % _at())
		for i in 30:
			await physics_frame
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...and no fight starts")
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
	await _place(PAST_REQUIRED)
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...put past the Dunecur, no fight starts")
	_wanderer.call("set_move_target", _world(Vector2(-29.5, -38.5)))
	var worst: float = -INF
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		worst = maxf(worst, (_wanderer.global_position - gate.global_position).dot(forward))
	_expect(worst <= OVERSHOOT_LIMIT_M, "...he never crosses the gate line (worst %+.3f m)" % worst)
	_expect(worst > -0.5, "...he comes to rest on it (%+.3f m)" % worst)
	_expect(not exited[0], "...and the floor doesn't exit")
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...nor does walking on from past him start the fight")
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
		_expect_eq(int(_run_state.get("current_floor_index")), FLOOR_INDEX + 1, "...on to floor 5")
		for i in 10:
			await process_frame
		var reloaded: Node = current_scene
		if reloaded != null and reloaded != _field:
			reloaded.queue_free()
		current_scene = null
	await _unload()
	_completed += 1

# The Dunecur over his bones: where he stands, facing them (the exit
# neck's way, his back to the approach), his 3 m contact area; the gate
# 7 m on, the bones all on the near side of it.
func _check_feeding_spot() -> void:
	await _load()
	var required: Node3D = _required_enemy() as Node3D
	var gate: Node3D = _field.get_node("ExitGate")
	var bones: Array[Node] = _field.find_children("*", "BoneScatter", true, false)
	_expect_eq(bones.size(), 1, "One bone scatter on floor 4")
	if required != null and bones.size() == 1:
		var at: Vector2 = Vector2(required.global_position.x - _spawn.x, required.global_position.z - _spawn.z)
		_expect(at.distance_to(REQUIRED_AT) < 0.01, "The Dunecur stands at %s (%s)" % [REQUIRED_AT, at])
		var scatter: Node3D = bones[0] as Node3D
		var to_bones := Vector2(scatter.global_position.x - required.global_position.x, scatter.global_position.z - required.global_position.z).normalized()
		var facing: Vector3 = -required.global_transform.basis.z
		var forward := Vector2(facing.x, facing.z).normalized()
		_expect(forward.dot(to_bones) > 0.999, "...facing his bones (%s)" % forward)
		_expect(forward.dot(EXIT_DIRECTION.normalized()) > 0.99, "...down the exit neck, his back to the approach")
		_expect_eq(float(required.get("contact_radius")), 3.0, "...his contact area 3 m")
		var gate_at := Vector2(gate.global_position.x - _spawn.x, gate.global_position.z - _spawn.z)
		_expect(gate_at.distance_to(REQUIRED_AT + EXIT_DIRECTION.normalized() * GATE_DISTANCE_M) < 0.01, "The gate stands 7 m past him (%s)" % gate_at)
		var gate_forward: Vector3 = -gate.global_transform.basis.z
		var pieces: PackedVector3Array = scatter.call("get_piece_positions")
		_expect_eq(pieces.size(), 12, "...twelve bones")
		var nearest: float = INF
		for piece in pieces:
			nearest = minf(nearest, -(piece - gate.global_position).dot(Vector3(gate_forward.x, 0.0, gate_forward.z).normalized()))
		_expect(nearest >= BONES_GATE_CLEARANCE_M, "...all of them %.1f m or more short of the gate line (nearest %.2f)" % [BONES_GATE_CLEARANCE_M, nearest])
		var ground: Node3D = _field.get_node("Ground")
		var worst_sink: float = INF
		for piece in pieces:
			var local: Vector3 = ground.to_local(piece)
			worst_sink = minf(worst_sink, piece.y - float(ground.call("get_height_at", Vector2(local.x, local.z))))
		_expect(worst_sink > -0.05, "...each sunk only part way into the sand (lowest centre %+.3f m)" % worst_sink)
		var band: PackedVector2Array = (load(FLOOR_4_PATH) as Resource).get("wear_path_override")
		_expect(band.has(REQUIRED_AT), "The worn band runs through him")
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

func _optional_enemy() -> Node:
	for node in get_nodes_in_group("enemies"):
		if not bool(node.get("required")):
			return node
	_fail("no optional enemy on floor 4")
	return null

# Distance from `p` to the segment a-b.
func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)

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
