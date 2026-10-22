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
#   exit    - walked past the region-end fight on either side, clear of
#             its contact area, toward the exit while it stands: the fight
#             starts as he passes it (FloorData.engage_line_enabled) and
#             he never reaches the gate line; won, the line lifts, the
#             Greyshelf's Tail is offered over the frozen field and LEFT,
#             and he walks out - the last floor, so the run ends: run_end "won"
#             logged, the end screen (RunEnd) shown, and its NEW RUN a
#             fresh run on floor 1
#   title   - the end screen's TITLE: a fresh run and the boot scene
#   loop    - loop_region_after_last_floor on: the old wrap to floor 1,
#             the Tail TAKEN on the way
#   pocket  - the side pocket off the climb's west side, where the
#             finding is reserved: reachable from the climb
#   stance  - contact with the Greyshelf from in front of it, its side
#             and its back: he never passes through its rock on the way
#             to his stance, and ends there, in front of it; each prints
#             the frame's pitch and whether the camera warned
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/floor5_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const CASES := 8
const REGION_PATH := "res://floors/region1.tres"
const FLOOR_4_PATH := "res://floors/region1_floor4.tres"
const FLOOR_5_PATH := "res://floors/region1_floor5.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const TAIL_ID := &"greyshelfs_tail"
const BLADE_ID := &"rusted_blade"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const RUN_END_SCENE_PATH := "res://run/run_end.tscn"
const TITLE_SCENE_PATH := "res://run/title_screen.tscn"
# The exit case's run log, kept for a look afterwards.
const LOG_DIR := "user://floor5_probe_runs"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_INDEX := 4
const EXIT_AT := Vector2(-3.5, -60.0)
const FINDING_AT := Vector2(-7.167, -15.9)
# Spawn to the crest along the worn band's S-bend: the long climb, the
# foot of the shelf, its top, the crest flat - short of the fight, outside
# its contact area and east of the crest rock's foot.
const CLIMB: Array[Vector2] = [Vector2(1.5, -6), Vector2(2.47, -10), Vector2(3.5, -20), Vector2(2.9, -26), Vector2(2.47, -30), Vector2(1.9, -32.5), Vector2(1.4, -35), Vector2(2.4, -35.5)]
const DESCENT: Array[Vector2] = [Vector2(1.4, -35), Vector2(1.9, -32.5), Vector2(2.47, -30), Vector2(2.9, -26)]
# The descent starts on the crest flat, clear of the fight's contact area.
const DESCENT_FROM := Vector2(3.0, -36.5)
# From the climb across to the pocket.
const POCKET_FROM := Vector2(2.0, -14.0)
# Past the fight, toward the exit: this far short of the gate line, back
# along the exit - outside the fight's contact area, short of the gate.
const PAST_GATE_BACK_M := 3.0
# The exit case's walk past the fight: from this far short of it along
# the exit, and this far clear of its contact area to either side.
const PASS_BACK_M := 2.0
const PASS_CLEAR_M := 1.0
# Starting as he passes it: when the fight opens he is within this of the
# fight's own line, along the exit (the stance move may already have
# begun taking him back).
const PASS_LATE_M := 1.0
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
const SAFETY_SECONDS := 460.0
# How long a contact's move to the stance is watched - the walk round the
# rock, the settle, the frame's ease.
const STANCE_SECONDS := 5.0
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
	await _check_stance_sides()
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
	var slots: Array = data.get("slots")
	_expect_eq(slots.size(), 1, "...one fight")
	if slots.size() == 1:
		var slot: Resource = slots[0]
		var entry: Resource = ((slot.get("options") as Array)[0].get("members") as Array)[0]
		_expect(bool(slot.get("required")), "...the region-end fight, required")
		_expect((entry.get("enemy_data") as Resource).resource_path == GREYSHELF_PATH, "...the Greyshelf")
	_expect_eq((data.get("ledges") as Array).size(), 1, "...one ledge ring: the boundary")
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

# No way past the region-end fight while it stands - walking past it on
# either side starts it (_check_walk_past()) - then the exit open once it
# is won - and floor 5 is the last, so leaving it ends the run, won: run_end
# "won" logged with the run's tally, the end screen (RunEnd) shown over
# the fade, and its NEW RUN a fresh run on floor 1.
func _check_exit() -> void:
	_clear_log_dir()
	RunLogger.set_output_dir(_log_dir)
	await _load()
	var gate: Node3D = _field.get_node("ExitGate")
	var forward: Vector3 = -gate.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var exited: Array[bool] = [false]
	gate.connect("floor_exited", func() -> void: exited[0] = true)
	_expect(bool(_wanderer.call("has_hold_line")), "Floor 5 holds a line while the region-end fight stands")
	var fight: Node3D = _required_enemy() as Node3D
	# Each side in turn, the first on a fresh floor of its own: the walk
	# past, its fight starting; the second side's fight is the one won.
	for side in [-1.0, 1.0]:
		if side > 0.0:
			await _unload()
			await _load()
			gate = _field.get_node("ExitGate")
			gate.connect("floor_exited", func() -> void: exited[0] = true)
			fight = _required_enemy() as Node3D
		await _check_walk_past(fight, gate, forward, side, exited)
	if await _win_fight(fight):
		await _answer_weapon_offer(false)
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

# Floor 5's walk past the region-end fight on one side (`side` along the
# gate's right): from PASS_BACK_M short of it, PASS_CLEAR_M clear of its
# contact area, clicked on toward the exit. The fight starts as he passes
# it - within PASS_LATE_M of its own line - and he never comes
# near the gate line or out.
func _check_walk_past(fight: Node3D, gate: Node3D, forward: Vector3, side: float, exited: Array[bool]) -> void:
	if fight == null:
		return
	var label: String = "west" if side < 0.0 else "east"
	var right := Vector3(-forward.z, 0.0, forward.x)
	var reach: float = float(fight.get("contact_radius")) + PASS_CLEAR_M
	var start: Vector3 = fight.global_position - forward * PASS_BACK_M + right * side * reach
	await _place(Vector2(start.x - _spawn.x, start.z - _spawn.z))
	var layer: Node = _field.get_node("BattleLayer")
	_expect(layer.get_child_count() == 0, "%s: beside the fight, clear of it, none starts" % label)
	var aim: Vector3 = start + forward * 8.0
	_wanderer.call("set_move_target", _world(Vector2(aim.x - _spawn.x, aim.z - _spawn.z)))
	var started_at: float = INF
	var nearest_gate: float = -INF
	for i in int(WAYPOINT_SECONDS * 60.0):
		await physics_frame
		nearest_gate = maxf(nearest_gate, (_wanderer.global_position - gate.global_position).dot(forward))
		if layer.get_child_count() > 0:
			var offset := _wanderer.global_position - fight.global_position
			started_at = Vector3(offset.x, 0.0, offset.z).dot(forward)
			break
	_expect(started_at < INF, "%s: walked past it, the fight starts" % label)
	if started_at < INF:
		_expect(absf(started_at) <= PASS_LATE_M, "%s: ...as he passes it (%+.2f m along the exit from it)" % [label, started_at])
	_expect(nearest_gate < -1.0, "%s: ...he never nears the gate line (%+.2f m)" % [label, nearest_gate])
	_expect(not exited[0], "%s: ...and the floor doesn't exit" % label)
	_wanderer.call("clear_move_target")

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
	await _place(_past_fight())
	if await _win_fight(_required_enemy()):
		await _answer_weapon_offer(true)
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

# Past the fight: PAST_GATE_BACK_M short of the gate line, back along the
# exit, as an offset from spawn.
func _past_fight() -> Vector2:
	var gate: Node3D = _field.get_node("ExitGate")
	var forward: Vector3 = -gate.global_transform.basis.z
	var exit := Vector2(forward.x, forward.z).normalized()
	return Vector2(gate.global_position.x - _spawn.x, gate.global_position.z - _spawn.z) - exit * PAST_GATE_BACK_M

# The required fight started and won outright, its reward screen up;
# false when it never starts.
func _win_fight(fight: Node) -> bool:
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_field.call_deferred("_on_enemy_contacted", fight)
	for i in 10:
		await physics_frame
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
	return true

# The Greyshelf won: its Tail a line on the reward screen (RewardScreen.
# offer_weapon()), its CHOOSE opening the plate over the screen and the
# frozen field - then answered the player's way, TAKE or LEAVE on its
# plate, the line struck, and the screen closed with the field live again,
# the weapon carried as chosen.
func _answer_weapon_offer(take: bool) -> void:
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	_expect(reward != null, "Won: the reward screen is up")
	if reward == null:
		return
	var lines: Array = reward.get("_lines")
	var index: int = -1
	for i in lines.size():
		if str((lines[i] as RefCounted).get("id")) == "weapon":
			index = i
	_expect(index >= 0, "...the Greyshelf's Tail a line on it")
	if index < 0:
		reward.call("close")
		return
	reward.call("_take_line", index)
	var offer: Node = reward.call("get_weapon_offer")
	_expect(offer != null, "...its CHOOSE opens the Tail's plate")
	if offer == null:
		reward.call("close")
		return
	var plate: Node = offer.call("get_plate")
	_expect_eq(str((plate.call("get_weapon") as Resource).get("id")), str(TAIL_ID), "...its plate the Tail's")
	_expect(int(offer.get("layer")) > int(reward.get("layer")), "...over the screen")
	_expect(not _field.can_process(), "...over a frozen field")
	plate.call("activate", 0 if take else 1)
	for i in 60:
		if not is_instance_valid(offer):
			break
		await physics_frame
	_expect(not is_instance_valid(offer) and bool((lines[index] as RefCounted).get("taken")), "...%s closes it, the line struck" % ("TAKE" if take else "LEAVE"))
	if is_instance_valid(reward):
		reward.call("close")
	for i in 60:
		if _field.can_process():
			break
		await physics_frame
	_expect(_field.can_process(), "...the screen closed, the field live again")
	var carried: Resource = _run_state.get("weapon")
	_expect_eq(str(carried.get("id")) if carried != null else "", str(TAIL_ID if take else BLADE_ID), "...the weapon carried %s" % ("the Tail" if take else "still the Rusted Blade"))

# On to the exit and through it, as a click walks him (RegionField.
# walk_to()): round what stands in the way - the Greyshelf's rock, when
# the fight left him at its foot.
func _walk_out(exited: Array[bool]) -> void:
	_field.call("walk_to", _world(EXIT_AT))
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

# Contact from in front of the Greyshelf, its side and its back - put just
# outside its contact area that way (or clear of its rock, behind it):
# every frame of the move to his stance his feet stay out of the rock's
# collision box (his own half width in, so a brush passes), and he ends
# at the stance in front of it.
func _check_stance_sides() -> void:
	for side in ["front", "side", "back"]:
		await _load()
		var fight: Node3D = _required_enemy() as Node3D
		var rock: Node3D = _child_with_script(_field.get_node("Props"), "basking_slab.gd") as Node3D
		var box: CollisionShape3D = rock.get_node_or_null("Collision").get_child(0) as CollisionShape3D if rock != null and rock.get_node_or_null("Collision") != null else null
		if fight == null or box == null:
			_fail("stance %s: no Greyshelf or no rock collision" % side)
			await _unload()
			continue
		var facing: Vector3 = -fight.global_transform.basis.z
		facing = Vector3(facing.x, 0.0, facing.z).normalized()
		var across: Vector3 = facing.cross(Vector3.UP).normalized()
		var size: Vector3 = (box.shape as BoxShape3D).size
		var reach: float = float(fight.get("contact_radius")) + 0.3
		var from: Vector3 = fight.global_position + facing * reach
		if side == "side":
			from = fight.global_position + across * reach
		elif side == "back":
			from = fight.global_position - facing * maxf(reach, size.x * 0.5 + 1.2)
		await _place(Vector2(from.x - _spawn.x, from.z - _spawn.z))
		_field.call_deferred("_on_enemy_contacted", fight)
		var camera: Node = _field.get_node("CameraPivot")
		var deepest: float = -INF
		var top_pitch: float = 0.0
		for i in int(STANCE_SECONDS * 60.0):
			await physics_frame
			var local: Vector3 = box.global_transform.affine_inverse() * _wanderer.global_position
			var inside: float = minf(size.x * 0.5 - absf(local.x), size.z * 0.5 - absf(local.z))
			deepest = maxf(deepest, inside)
			top_pitch = maxf(top_pitch, float(camera.get("_battle_pitch_now")))
		var half: float = float(_wanderer.call("get_half_width"))
		_expect(deepest < half, "stance %s: never into the rock (deepest %+.2f m past its face, %.2f allowed)" % [side, deepest, half])
		var to_him: Vector3 = _wanderer.global_position - fight.global_position
		to_him.y = 0.0
		_expect(to_him.normalized().dot(facing) > 0.99, "stance %s: he ends in front of it (%s)" % [side, to_him])
		print("INFO: stance %s: battle pitch %.0f now, %.0f at most; the 20 degree warning %s" % [side, float(camera.get("_battle_pitch_now")), top_pitch, "given" if bool(camera.get("_battle_pitch_warned")) else "not given"])
		await _unload()
	_completed += 1

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
	var start: int = ProbePlay.cap_msec()
	while _child_with_script(_field, "reward_screen.gd") == null and ProbePlay.cap_msec() - start < int(REWARD_WAIT_SECONDS * 1000.0):
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
