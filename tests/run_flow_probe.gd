extends SceneTree

# Core probe: a run, start to finish, the way a player goes through it -
# every step through the game's own paths, nothing pinned:
#
#   fight    - a new run on floor 1; its first enemy fought with the cards
#              the run's own deck deals, played from the hand (ProbePlay.
#              play_any()), until it falls; the fight closes and the field
#              takes over again, the enemy gone from it
#   reward   - the reward screen opens; its gold and a card are taken: the
#              run's gold up by the gold line, the deck up one
#   floor    - the floor's exit (RegionField._on_floor_exited()): the next
#              floor loads, the run carried on to it
#   death    - a fight there lost: the run ends died, the end screen for a
#              loss comes up, and NEW RUN starts a fresh run on floor 1
#   log      - the run's log, read back: every line JSON, every line in
#              the current format (RunLogger.FORMAT_VERSION), the run's
#              own events in order - run_start, floor_entered, fight_start,
#              fight_end (won), the reward lines, floor_entered, fight_
#              start, fight_end (lost), run_end (died) - and run_end's
#              tally agreeing with the run
#
# Any SCRIPT ERROR or engine ERROR fails it (tools/run_probes.sh).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/run_flow_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const LOG_DIR := "user://run_flow_probe"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const MAX_TURNS := 20
# Caps on waits, seconds - never waits of their own.
const SCENE_SECONDS := 15.0
const REWARD_WAIT_SECONDS := 8.0
const SAFETY_SECONDS := 240.0

var _log_dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _steps: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_clear_dir()
	RunLogger.set_output_dir(_log_dir)
	RunLogger.enabled = true
	await _run()
	_check_log()
	RunLogger.set_output_dir("")
	if _steps != 6:
		_fail("%d of 6 steps ran to their end" % _steps)
	if _failures == 0:
		print("run_flow_probe: PASSED")
		quit(0)
	else:
		print("run_flow_probe: %d FAILED" % _failures)
		quit(1)

func _run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", true)
	root.add_child(_field)
	current_scene = _field
	await _settle_field()

	# --- fight ---
	print("\n=== fight")
	var target: Node3D = _first_enemy()
	if target == null:
		_fail("fight: no enemy on floor 1")
		return
	var controller: Node = await ProbePlay.start_fight(self, _field, target)
	if controller == null:
		_fail("fight: contact opened no fight")
		return
	var turns: int = await _fight_to_the_end(controller)
	_expect(not _battle_open(), "fight: the enemy falls inside %d turns (%d)" % [MAX_TURNS, turns])
	_expect(int(_run_state.get("player_hp")) > 0, "fight: the run lives through it")
	if _battle_open():
		return
	_steps += 1

	# --- reward ---
	print("\n=== reward")
	var reward: Node = await _await_child("reward_screen.gd", REWARD_WAIT_SECONDS)
	_expect(reward != null, "reward: the win opens the reward screen")
	if reward == null:
		return
	var gold_before: int = int(_run_state.get("gold"))
	var deck_before: int = (_run_state.get("deck") as Array).size()
	var gold_line: int = -1
	var card_line: int = -1
	var lines: Array = reward.get("_lines")
	for index in lines.size():
		var id: String = str((lines[index] as RefCounted).get("id"))
		if id == "gold":
			gold_line = index
		elif id == "card":
			card_line = index
	_expect(gold_line >= 0 and card_line >= 0, "reward: a gold line and a card line")
	var gold_amount: int = int(reward.get("_gold"))
	if gold_line >= 0:
		reward.call("_take_line", gold_line)
		_expect_eq(int(_run_state.get("gold")), gold_before + gold_amount, "reward: the gold taken is the run's")
	if card_line >= 0:
		reward.call("_take_line", card_line)
		var views: Array = reward.get("_card_views")
		_expect(not views.is_empty(), "reward: its cards on offer")
		if not views.is_empty():
			var first: CardView = views[0]
			reward.call("_on_choice_clicked", first.card_data, first)
			await ProbePlay.wait_until(self, func() -> bool: return (_run_state.get("deck") as Array).size() > deck_before, 3.0)
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before + 1, "reward: the card taken joins the deck")
	var reward_ref: WeakRef = weakref(reward)
	await ProbePlay.wait_until(self, func() -> bool:
		var live: Node = reward_ref.get_ref() as Node
		return live == null or live.is_queued_for_deletion(), 5.0)
	# Anything the fight left besides (a keepsake offer) is left.
	var offer: Node = _child_with_script(_field, "keepsake_offer.gd")
	if offer != null:
		offer.call("_activate", 1)
	for i in 10:
		await physics_frame
	_steps += 1

	# --- floor ---
	print("\n=== floor")
	var floor_before: int = int(_run_state.get("current_floor_index"))
	var old_field: Node = _field
	_field.call("_on_floor_exited")
	var next: Node = await _await_scene(REGION_SCENE_PATH, old_field.get_instance_id())
	_expect(next != null, "floor: the exit loads the next floor")
	if next == null:
		return
	_field = next
	_expect_eq(int(_run_state.get("current_floor_index")), floor_before + 1, "floor: the run is on the next floor")
	_expect_eq(int(_run_state.get("floors_crossed")), 1, "floor: one floor crossed")
	var fade: Node = _root_fade()
	if fade != null:
		fade.call("clear")
	await _settle_field()
	_steps += 1

	# --- death ---
	print("\n=== death")
	target = _first_enemy()
	if target == null:
		_fail("death: no enemy on the next floor")
		return
	controller = await ProbePlay.start_fight(self, _field, target)
	if controller == null:
		_fail("death: contact opened no fight")
		return
	_run_state.call("lose_hp", int(_run_state.get("player_hp")))
	(controller.get("player") as Combatant).hp = 0
	controller.call("_check_battle_end")
	var end: Node = await _await_scene(RUN_OVER_SCENE_PATH, 0)
	_expect_eq(str(_run_state.get("end_cause")), "died", "death: the run ends died")
	_expect(end != null, "death: the end screen for a loss comes up")
	if end == null:
		return
	_steps += 1
	end.call("_activate", 0)
	var fresh: Node = await _await_scene(REGION_SCENE_PATH, 0)
	_expect(fresh != null, "restart: NEW RUN loads the field")
	_expect_eq([int(_run_state.get("current_floor_index")), str(_run_state.get("end_cause")), int(_run_state.get("floors_crossed"))], [0, "", 0], "restart: a fresh run on floor 1")
	_field = fresh
	_steps += 1
	await _free_scene()

# The fight played out with the cards the hand deals: every card that can
# be played, played; End Turn when none can; until it ends or MAX_TURNS.
func _fight_to_the_end(controller: Node) -> int:
	var turns: int = 1
	while _battle_open() and turns <= MAX_TURNS:
		var played: bool = true
		while played and _battle_open() and is_instance_valid(controller):
			played = false
			for view: CardView in ProbePlay.hand_views(controller):
				if not _battle_open() or not is_instance_valid(controller):
					break
				if not is_instance_valid(view) or not bool(controller.call("_is_playable", view.card_data)):
					continue
				if await ProbePlay.play_any(self, controller, view, func() -> bool: return not _battle_open()):
					played = true
					break
		if not _battle_open() or not is_instance_valid(controller):
			break
		var turn: int = int(controller.get("_player_turn"))
		controller.call("end_turn")
		var held: WeakRef = weakref(controller)
		await ProbePlay.wait_until(self, func() -> bool:
			var live: Node = held.get_ref() as Node
			return not _battle_open() or live == null or (int(live.get("_player_turn")) > turn and ProbePlay.is_settled(live)), 20.0)
		turns += 1
	await ProbePlay.wait_until(self, func() -> bool: return not _battle_open(), REWARD_WAIT_SECONDS)
	return turns

# --- The log ---

func _check_log() -> void:
	print("\n=== log")
	var path: String = ""
	for file in DirAccess.get_files_at(_log_dir):
		var text: String = FileAccess.get_file_as_string(_log_dir.path_join(file))
		if text.contains("\"run_end\""):
			path = _log_dir.path_join(file)
	_expect(not path.is_empty(), "log: the run wrote its file, ending on run_end")
	if path.is_empty():
		return
	var lines: Array[Dictionary] = []
	var bad: int = 0
	for raw in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			lines.append(parsed)
		else:
			bad += 1
	_expect_eq(bad, 0, "log: every line a JSON object")
	var off_format: int = 0
	var core: Array[String] = []
	for line in lines:
		if int(line.get("v", 0)) != RunLogger.FORMAT_VERSION:
			off_format += 1
		var ev: String = str(line.get("ev", ""))
		if not RunLogger._DETAIL_EVENTS.has(ev) and ev != "mechanic":
			core.append(ev)
	_expect_eq(off_format, 0, "log: every line in format %d" % RunLogger.FORMAT_VERSION)
	print("log: ", core)
	var expected: Array[String] = ["run_start", "floor_entered", "fight_start", "fight_end"]
	_expect_eq(core.slice(0, 4), expected, "log: the run opens run_start, floor_entered, fight_start, fight_end")
	_expect(core.has("reward_gold") and core.has("reward_cards"), "log: the reward's gold and card")
	var second: int = core.find("floor_entered", 1)
	var next_floor: Array[String] = ["floor_entered", "fight_start", "fight_end"]
	_expect(second > 0 and core.slice(second, second + 3) == next_floor, "log: then floor_entered, fight_start, fight_end on the next floor")
	_expect_eq(core.back() if not core.is_empty() else "", "run_end", "log: run_end last")
	var results: Array[String] = []
	for line in lines:
		if str(line.get("ev", "")) == "fight_end":
			results.append(str(line.get("result", "")))
	_expect_eq(results, ["win", "lose"] as Array[String], "log: the first fight won, the second lost")
	var end: Dictionary = {}
	for line in lines:
		if str(line.get("ev", "")) == "run_end":
			end = line
	_expect_eq([str(end.get("cause", "")), int(end.get("fights", -1)), int(end.get("fights_won", -1)), int(end.get("floors_crossed", -1))], ["died", 2, 1, 1], "log: run_end died, two fights, one won, one floor crossed")
	_steps += 1

# --- Helpers ---

func _first_enemy() -> Node3D:
	for node in get_nodes_in_group("enemies"):
		if is_instance_valid(node) and not node.is_queued_for_deletion() and _field.is_ancestor_of(node):
			return node as Node3D
	return null

func _battle_open() -> bool:
	return _field != null and is_instance_valid(_field) and bool(_field.get("_battle_open"))

# A field just loaded: its arrival hold over, so contact and clicks reach it.
func _settle_field() -> void:
	for i in 30:
		await physics_frame
	await ProbePlay.wait_until(self, func() -> bool: return not bool(_field.call("is_arrival_held")), SCENE_SECONDS)

# The current scene once it is `path` and not the node `not_this_id` (an
# instance id, 0 for none) - by id, so a scene already freed is never held.
func _await_scene(path: String, not_this_id: int) -> Node:
	var found: Array[Node] = [null]
	await ProbePlay.wait_until(self, func() -> bool:
		if not is_instance_valid(current_scene):
			return false
		var scene: Node = current_scene
		if scene.get_instance_id() != not_this_id and scene.scene_file_path == path and scene.is_inside_tree():
			found[0] = scene
			return true
		return false, SCENE_SECONDS)
	return found[0]

func _await_child(suffix: String, timeout_sec: float) -> Node:
	var found: Array[Node] = [null]
	await ProbePlay.wait_until(self, func() -> bool:
		found[0] = _child_with_script(_field, suffix)
		return found[0] != null, timeout_sec)
	return found[0]

func _child_with_script(parent: Node, suffix: String) -> Node:
	if parent == null or not is_instance_valid(parent):
		return null
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

func _root_fade() -> Node:
	for child in root.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("floor_fade.gd"):
			return child
	return null

func _free_scene() -> void:
	var scene: Node = current_scene
	current_scene = null
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	_field = null
	var fade: Node = _root_fade()
	if fade != null:
		fade.call("clear")
	for i in 5:
		await process_frame

func _clear_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_log_dir)
	for file in DirAccess.get_files_at(_log_dir):
		DirAccess.remove_absolute(_log_dir.path_join(file))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
