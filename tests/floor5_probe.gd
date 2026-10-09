extends SceneTree

# Headless probe for floor 5, Region 1's last floor - the climb north out
# of the dunes to the rocky crest: its data and its place in Region 1,
# then the floor walked for real - the Wanderer clicked from waypoint to
# waypoint (Wanderer.set_move_target()) through the physics, as a player
# would:
#
#   climb   - spawn up the S-bend, over the rock shelf, onto the crest
#             flat: every waypoint reached, the walk floor 3 m higher at
#             the top, and walking on meets the region-end fight
#   descent - from the crest flat back down over the shelf: walkable
#             both ways
#   exit    - past the region-end fight toward the exit while it stands:
#             he comes to rest on the gate line and the floor holds; won,
#             the line lifts and he walks out - the last floor, so the run
#             ends: run_end "won" logged, the end screen (RunEnd) shown,
#             and its NEW RUN a fresh run on floor 1
#   title   - the end screen's TITLE: a fresh run and the boot scene
#   loop    - loop_region_after_last_floor on: the old wrap to floor 1
#   pocket  - the side pocket off the climb's west side, where the
#             finding is reserved: reachable from the climb
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/floor5_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const CASES := 7
const REGION_PATH := "res://floors/region1.tres"
const FLOOR_4_PATH := "res://floors/region1_floor4.tres"
const FLOOR_5_PATH := "res://floors/region1_floor5.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const RUN_END_SCENE_PATH := "res://run/run_end.tscn"
const TITLE_SCENE_PATH := "res://run/title_screen.tscn"
# The exit case's run log, kept for a look afterwards.
const LOG_DIR := "user://floor5_probe_runs"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_INDEX := 4
const FIGHT_AT := Vector2(-0.567, -42.0)
const EXIT_DIRECTION := Vector2(-0.1022, -0.9948)
const GATE_DISTANCE_M := 12.0
const EXIT_AT := Vector2(-3.5, -60.0)
const FINDING_AT := Vector2(-7.167, -15.9)
# Spawn to the crest along the worn band's S-bend: the long climb, the
# foot of the shelf, its top, the crest flat - short of the fight.
const CLIMB: Array[Vector2] = [Vector2(1.5, -6), Vector2(2.47, -10), Vector2(3.5, -20), Vector2(2.9, -26), Vector2(2.47, -30), Vector2(1.9, -32.5), Vector2(1.4, -35), Vector2(0.6, -37.5)]
const DESCENT: Array[Vector2] = [Vector2(1.4, -35), Vector2(1.9, -32.5), Vector2(2.47, -30), Vector2(2.9, -26)]
# The descent starts on the crest flat, clear of the fight's contact area.
const DESCENT_FROM := Vector2(3.0, -36.5)
# From the climb across to the pocket.
const POCKET_FROM := Vector2(2.0, -14.0)
# Past the fight on the crest, toward the exit - outside its contact area,
# well short of the gate.
const PAST_FIGHT := Vector2(-1.5, -47.0)
# The walk floor's rise from spawn to the crest flat (0.4 m -> 3.45 m on
# the elevation mask), and how far the feet may read off it: the relief's
# own noise (relief_amplitude 0.28) rides on the mask at either end.
const CREST_RISE_M := 3.05
const RISE_TOLERANCE_M := 0.3
# Metres short of a waypoint that count as there.
const REACH_M := 1.0
const WAYPOINT_SECONDS := 12.0
const FIGHT_SECONDS := 8.0
const OVERSHOOT_LIMIT_M := 0.02
const SAFETY_SECONDS := 400.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0

# This process's log folder: run_probes.sh's per-process --runlog-dir
# (RunLogger.dir_override()) when it hands one over, so a second copy of
# this probe running at once never sees this one's files - else LOG_DIR.
var _log_dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
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
	await _check_climb()
	await _check_descent()
	await _check_exit()
	await _check_title()
	await _check_loop()
	await _check_pocket()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("floor5_probe: PASSED")
		quit(0)
	else:
		print("floor5_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var region: Resource = load(REGION_PATH)
	var floors: Array = region.get("floors")
	_expect_eq(floors.size(), 5, "Region 1 has five floors")
	_expect(floors.size() == 5 and floors[3].resource_path == FLOOR_4_PATH and floors[4].resource_path == FLOOR_5_PATH, "...floor 5 last, after floor 4")
	var data: Resource = load(FLOOR_5_PATH)
	_expect_eq(data.get("elevation_max_height"), 5.0, "Floor 5 reads its elevation at 5.0 m")
	_expect(is_equal_approx(float(data.get("rock_slope_min")), 10.0) and is_equal_approx(float(data.get("rock_slope_blend")), 6.0), "...stone from 10 degrees, full by 16: the shelf shows rock")
	_expect_eq(float(data.get("basin_tint_strength")), 0.0, "...no basin tint: the walk floor climbs")
	_expect_eq(float(data.get("slope_tint_fade_width")), 0.0, "...no slope-tint height fade")
	_expect_eq(float(data.get("ambience_sea_db")), -80.0, "...the sea muted")
	_expect_eq(int(data.get("exit_kind")), 1, "...a LINE gate")
	var enemies: Array = data.get("enemies")
	_expect_eq(enemies.size(), 1, "...one fight")
	if enemies.size() == 1:
		_expect(bool(enemies[0].get("required")) and enemies[0].get("position") == FIGHT_AT, "...the region-end fight, required, on the crest")
		_expect((enemies[0].get("enemy_data") as Resource).resource_path == GREYSHELF_PATH, "...the Greyshelf")
		_expect(is_equal_approx(float(enemies[0].get("yaw_degrees")), -90.0), "...lying across the crest, head east")
	_expect(data.get("exit_direction") == EXIT_DIRECTION and is_equal_approx(float(data.get("gate_distance_beyond_enemy")), GATE_DISTANCE_M), "...the gate 12 m on along the exit neck")
	_expect_eq((data.get("ledges") as Array).size(), 1, "...one ledge ring: the boundary")
	_expect_eq((data.get("wear_path_override") as PackedVector2Array).size(), 7, "...a 7-point worn band")
	_completed += 1

# Spawn to the crest: every waypoint of the climb and the shelf reached
# under real physics, the feet 3 m higher at the top, and walking on meets
# the region-end fight.
func _check_climb() -> void:
	await _load()
	var spawn_y: float = _wanderer.global_position.y
	for point in CLIMB:
		var reached: bool = await _walk_to(point)
		_expect(reached, "climb: reaches %s (stopped at %s)" % [point, _at()])
		if not reached:
			break
	var rise: float = _wanderer.global_position.y - spawn_y
	print("climb: %.2f m up from spawn on the crest flat" % rise)
	_expect(absf(rise - CREST_RISE_M) <= RISE_TOLERANCE_M, "climb: the crest flat stands %.2f m above spawn (%.2f)" % [CREST_RISE_M, rise])
	var fight: Node = _required_enemy()
	if fight != null:
		_wanderer.call("set_move_target_enemy", fight)
		var started: bool = false
		for i in int(FIGHT_SECONDS * 60.0):
			await physics_frame
			if _field.get_node("BattleLayer").get_child_count() > 0:
				started = true
				break
		_expect(started, "climb: walking on, he meets the region-end fight")
	await _unload()
	_completed += 1

# Back down from the crest flat over the shelf.
func _check_descent() -> void:
	await _load()
	await _place(DESCENT_FROM)
	for point in DESCENT:
		var reached: bool = await _walk_to(point)
		_expect(reached, "descent: reaches %s (stopped at %s)" % [point, _at()])
		if not reached:
			break
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "descent: no fight starts")
	await _unload()
	_completed += 1

# The exit held while the region-end fight stands, then open once it is
# won - and floor 5 is the last, so leaving it ends the run, won: run_end
# "won" logged with the run's tally, the end screen (RunEnd) shown over
# the fade, and its NEW RUN a fresh run on floor 1.
func _check_exit() -> void:
	_clear_log_dir()
	RunLogger.set_output_dir(_log_dir)
	await _load()
	var gate: Node3D = _field.get_node("ExitGate")
	var gate_at := Vector2(gate.global_position.x - _spawn.x, gate.global_position.z - _spawn.z)
	_expect(gate_at.distance_to(FIGHT_AT + EXIT_DIRECTION.normalized() * GATE_DISTANCE_M) < 0.01, "The gate stands 12 m past the fight (%s)" % gate_at)
	var forward: Vector3 = -gate.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var exited: Array[bool] = [false]
	gate.connect("floor_exited", func() -> void: exited[0] = true)
	_expect(bool(_wanderer.call("has_hold_line")), "Floor 5 holds a line while the region-end fight stands")
	var fight: Node3D = _required_enemy() as Node3D
	if fight != null:
		var clear: float = PAST_FIGHT.distance_to(FIGHT_AT) - float(fight.get("contact_radius"))
		_expect(clear > 0.5, "...the spot past it is outside its contact area (%.2f m clear)" % clear)
	await _place(PAST_FIGHT)
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...put past the fight, none starts")
	_wanderer.call("set_move_target", _world(EXIT_AT))
	var worst: float = -INF
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		worst = maxf(worst, (_wanderer.global_position - gate.global_position).dot(forward))
	_expect(worst <= OVERSHOOT_LIMIT_M, "...he never crosses the gate line (worst %+.3f m)" % worst)
	_expect(worst > -0.5, "...he comes to rest on it (%+.3f m)" % worst)
	_expect(not exited[0], "...and the floor doesn't exit")
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...nor does walking on from past it start the fight")
	if await _win_fight(fight):
		_expect(not bool(_wanderer.call("has_hold_line")), "Won: the line lifts")
		_expect_eq(int(_run_state.get("fights_won")), 1, "...one fight won")
		await _walk_out(exited)
		var end: Node = await _await_scene(RUN_END_SCENE_PATH)
		_expect(end != null, "The last floor left: the run ends on the end screen")
		_expect_eq(int(_run_state.get("current_floor_index")), FLOOR_INDEX, "...no wrap: the floor index stays on floor 5")
		_expect_eq(int(_run_state.get("region_lap")), 0, "...and no lap counted")
		_expect_eq(int(_run_state.get("floors_crossed")), 1, "...one floor crossed (this probe starts on floor 5)")
		var fade: Node = _root_fade()
		_expect(fade != null and bool(fade.call("is_opaque")), "...over the fade, still up")
		var run_end: Dictionary = _last_run_end()
		_expect_eq(str(run_end.get("cause")), "won", "run_end: won")
		_expect_eq([int(run_end.get("fights_won", -1)), int(run_end.get("floors_crossed", -1))], [1, 1], "...one fight won, one floor crossed")
		_expect_eq([int(run_end.get("hp", -1)), int(run_end.get("max_hp", -1)), int(run_end.get("deck_size", -1))], [int(_run_state.get("player_hp")), int(_run_state.get("player_max_hp")), (_run_state.get("deck") as Array).size()], "...HP, max HP and deck size as the run stands")
		if end != null:
			var rows: Array = end.call("stat_rows")
			var labels: Array[String] = []
			for row in rows:
				labels.append(str(row[0]))
			_expect_eq(labels, ["FLOORS CROSSED", "FIGHTS WON", "HP", "DECK", "KEEPSAKE"] as Array[String], "The end screen's stats")
			_expect_eq(str(rows[0][1]) + "|" + str(rows[1][1]), "1|1", "...floors crossed 1, fights won 1")
			_expect_eq(str(end.get_node("Column/LineLabel").get("text")), str(end.get("world_line")), "...under its world-voice line")
			# NEW RUN: a fresh run on floor 1.
			end.call("_activate", 0)
			var field: Node = await _await_scene(REGION_SCENE_PATH)
			_expect(field != null, "NEW RUN: the field loads")
			_expect_eq([int(_run_state.get("current_floor_index")), int(_run_state.get("floors_crossed")), int(_run_state.get("fights_won"))], [0, 0, 0], "...a fresh run on floor 1, its tally zeroed")
			_expect(_root_fade() == null or not bool(_root_fade().call("is_opaque")), "...the fade taken down")
			await _free_current_scene()
	RunLogger.set_output_dir("")
	await _unload()
	_completed += 1

# The end screen's TITLE: a fresh run, then the boot scene - the title
# held over the field, as at launch.
func _check_title() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_INDEX)
	var end: Node = (load(RUN_END_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(end)
	current_scene = end
	for i in 5:
		await process_frame
	end.call("_activate", 1)
	var title: Node = await _await_scene(TITLE_SCENE_PATH)
	_expect(title != null, "TITLE: the boot scene loads")
	_expect_eq(int(_run_state.get("current_floor_index")), 0, "...over a fresh run on floor 1")
	await _await_scene(REGION_SCENE_PATH)
	await _free_current_scene()
	_completed += 1

# With loop_region_after_last_floor on, the old wrap: floor 5's exit goes
# round to floor 1 and counts a lap.
func _check_loop() -> void:
	await _load()
	_field.set("loop_region_after_last_floor", true)
	var gate: Node3D = _field.get_node("ExitGate")
	var exited: Array[bool] = [false]
	gate.connect("floor_exited", func() -> void: exited[0] = true)
	await _place(PAST_FIGHT)
	if await _win_fight(_required_enemy()):
		var lap_before: int = int(_run_state.get("region_lap"))
		await _walk_out(exited)
		for i in 8 * 60:
			if int(_run_state.get("current_floor_index")) != FLOOR_INDEX:
				break
			await process_frame
		_expect_eq(int(_run_state.get("current_floor_index")), 0, "Looping: the last floor wraps to floor 1")
		_expect_eq(int(_run_state.get("region_lap")), lap_before + 1, "...a lap of the region counted")
		for i in 10:
			await process_frame
		var reloaded: Node = current_scene
		if reloaded != null and reloaded != _field:
			reloaded.queue_free()
		current_scene = null
	await _unload()
	_completed += 1

# The required fight started and won outright; false when it never starts.
func _win_fight(fight: Node) -> bool:
	_field.call_deferred("_on_enemy_contacted", fight)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("the region-end fight didn't start")
		return false
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
	return true

# On to the exit and through it.
func _walk_out(exited: Array[bool]) -> void:
	_wanderer.call("set_move_target", _world(EXIT_AT))
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		if exited[0]:
			break
	_expect(exited[0], "...he walks out through the exit neck")

# The current scene once it is `path` (null if it never is): the look up
# and the fade come first (RegionField._on_floor_exited()).
func _await_scene(path: String) -> Node:
	for i in 8 * 60:
		if current_scene != null and current_scene.scene_file_path == path:
			return current_scene
		await process_frame
	return null

func _free_current_scene() -> void:
	var scene: Node = current_scene
	current_scene = null
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	for i in 5:
		await process_frame

# The transition's fade (FloorFade), on the tree's root.
func _root_fade() -> Node:
	for child in root.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("floor_fade.gd"):
			return child
	return null

func _clear_log_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_log_dir)
	for name in DirAccess.get_files_at(_log_dir):
		DirAccess.remove_absolute(_log_dir.path_join(name))

# The last run_end in the probe's log folder.
func _last_run_end() -> Dictionary:
	var found: Dictionary = {}
	for name in DirAccess.get_files_at(_log_dir):
		for raw in FileAccess.get_file_as_string(_log_dir.path_join(name)).split("\n", false):
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary and str((parsed as Dictionary).get("ev")) == "run_end":
				found = parsed
	return found

# The side pocket off the climb's west side: the finding's spot reached.
func _check_pocket() -> void:
	await _load()
	await _place(POCKET_FROM)
	var reached: bool = await _walk_to(FINDING_AT)
	_expect(reached, "The pocket is reachable from the climb: the finding's spot %s (stopped at %s)" % [FINDING_AT, _at()])
	_expect(_field.get_node("BattleLayer").get_child_count() == 0, "...and no fight starts on the way")
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
	var x: float = _spawn.x + point.x
	var z: float = _spawn.z + point.y
	var ground: Node3D = _field.get_node("Ground")
	var local: Vector3 = ground.to_local(Vector3(x, 0.0, z))
	return Vector3(x, float(ground.call("get_height_at", Vector2(local.x, local.z))), z)

# The Wanderer's spawn-relative XZ.
func _at() -> Vector2:
	return Vector2(_wanderer.global_position.x - _spawn.x, _wanderer.global_position.z - _spawn.z)

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
		if _at().distance_to(point) <= REACH_M:
			return true
		if not bool(_wanderer.call("has_move_target")) and i > 10:
			break
	return _at().distance_to(point) <= REACH_M

func _required_enemy() -> Node:
	for node in get_nodes_in_group("enemies"):
		if bool(node.get("required")):
			return node
	_fail("no required enemy on floor 5")
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
