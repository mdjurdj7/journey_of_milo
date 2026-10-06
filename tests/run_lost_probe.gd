extends SceneTree

# Headless probe for a lost run's end, both ways it can come - each played
# for real on floor 1, then the end screen for a loss (run_over.tscn, a
# RunEnd) checked:
#
#   died    - a fight lost (the player's HP at 0, the controller's own
#             end check): run_end died, the field frozen and the frame
#             faded to the fog, then the screen over the fade - its line
#             "The walk ends here.", the run's tally, and NEW RUN a fresh
#             run on floor 1 with the fade taken down
#   drowned - wading with 1 HP and the wade drain on (no floor has it on
#             yet): run_end drowned, the same fade, the same screen with
#             the drowning's own line "The water took him."
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/run_lost_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const CASES := 2
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const DIED_LINE := "The walk ends here."
const DROWNED_LINE := "The water took him."
# How far out from the shore the drowning is walked to: deep enough that
# the drain runs (wade_depth_threshold over wade_slope_per_metre is 0.33 m).
const WADE_DEPTH_M := 4.0
const SCENE_SECONDS := 10.0
const SAFETY_SECONDS := 120.0

var _run_state: Node = null
var _field: Node3D = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	await _check_died()
	await _check_drowned()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("run_lost_probe: PASSED")
		quit(0)
	else:
		print("run_lost_probe: %d FAILED" % _failures)
		quit(1)

# A fight lost: its end screen, then NEW RUN.
func _check_died() -> void:
	await _load()
	var enemy: Node = null
	for node in get_nodes_in_group("enemies"):
		enemy = node
		break
	_field.call_deferred("_on_enemy_contacted", enemy)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("died: the fight didn't start")
	else:
		var controller: Node = layer.get_child(0).get("battle_controller")
		# Every hit lands on RunState too (lose_hp()); the last one, all of it.
		_run_state.call("lose_hp", int(_run_state.get("player_hp")))
		(controller.get("player") as RefCounted).set("hp", 0)
		controller.call("_check_battle_end")
		var end: Node = await _check_lost_end("died", DIED_LINE)
		if end != null:
			end.call("_activate", 0)
			var field: Node = await _await_scene(REGION_SCENE_PATH)
			_expect(field != null, "died: NEW RUN loads the field")
			_expect_eq([int(_run_state.get("current_floor_index")), str(_run_state.get("end_cause"))], [0, ""], "...a fresh run on floor 1")
			var fade: Node = _root_fade()
			_expect(fade == null or not bool(fade.call("is_opaque")), "...the fade taken down")
	await _free_current_scene()
	_completed += 1

# Drowned wading: the same screen with the drowning's line.
func _check_drowned() -> void:
	await _load()
	_field.set("wade_drain_enabled", true)
	_run_state.call("lose_hp", int(_run_state.get("player_hp")) - 1)
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	var ground: Node3D = _field.get_node("Ground")
	# Out to sea straight back from the exit, until the water is deep enough.
	var away: Vector3 = -(_field.call("get_exit_direction") as Vector3)
	var point: Vector3 = wanderer.global_position
	for i in 400:
		var local: Vector3 = ground.to_local(point)
		if float(ground.call("get_landmass_distance", Vector2(local.x, local.z))) >= WADE_DEPTH_M:
			break
		point += away * 0.25
	wanderer.call("clear_move_target")
	wanderer.global_position = point + Vector3.UP * 0.5
	await _check_lost_end("drowned", DROWNED_LINE)
	await _free_current_scene()
	_completed += 1

# The lost end as both causes share it: the cause logged, the field frozen
# under the fade, then the end screen over it saying `line`.
func _check_lost_end(cause: String, line: String) -> Node:
	var faded: bool = false
	var frozen: bool = false
	for i in int(SCENE_SECONDS * 60.0):
		await process_frame
		if current_scene != null and current_scene.scene_file_path == RUN_OVER_SCENE_PATH:
			break
		if str(_run_state.get("end_cause")) == cause and is_instance_valid(_field):
			frozen = frozen or _field.process_mode == Node.PROCESS_MODE_DISABLED
			var fade: Node = _root_fade()
			faded = faded or (fade != null and bool(fade.call("is_opaque")))
	_expect_eq(str(_run_state.get("end_cause")), cause, "%s: run_end %s logged" % [cause, cause])
	_expect(frozen, "%s: the field freezes" % cause)
	_expect(faded, "%s: the frame fades to the fog first" % cause)
	var end: Node = current_scene if current_scene != null and current_scene.scene_file_path == RUN_OVER_SCENE_PATH else null
	_expect(end != null, "%s: then the end screen for a loss" % cause)
	if end == null:
		return null
	for i in 3:
		await process_frame
	var fade: Node = _root_fade()
	_expect(fade != null and bool(fade.call("is_opaque")), "%s: ...over the fade, still up" % cause)
	_expect_eq(str(end.get_node("Column/LineLabel").get("text")), line, "%s: ...saying \"%s\"" % [cause, line])
	var rows: Array = end.call("stat_rows")
	var labels: Array[String] = []
	for row in rows:
		labels.append(str(row[0]))
	_expect_eq(labels, ["FLOORS CROSSED", "FIGHTS WON", "HP", "DECK", "KEEPSAKE"] as Array[String], "%s: ...the run's tally" % cause)
	_expect_eq(str(rows[2][1]), "0 / %d" % int(_run_state.get("player_max_hp")), "%s: ...HP at 0" % cause)
	_expect_eq([str(end.get_node("Column/NewRunItem/Label").get("text")), str(end.get_node("Column/TitleItem/Label").get("text"))], ["NEW RUN", "TITLE"], "%s: ...NEW RUN and TITLE" % cause)
	return end

# --- Helpers ---

func _load() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_field)
	current_scene = _field
	for i in 30:
		await physics_frame

func _await_scene(path: String) -> Node:
	for i in int(SCENE_SECONDS * 60.0):
		if current_scene != null and current_scene.scene_file_path == path:
			return current_scene
		await process_frame
	return null

func _free_current_scene() -> void:
	var scene: Node = current_scene
	current_scene = null
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	var fade: Node = _root_fade()
	if fade != null:
		fade.call("clear")
	for i in 5:
		await process_frame

# The transition's fade (FloorFade), on the tree's root.
func _root_fade() -> Node:
	for child in root.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("floor_fade.gd"):
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
