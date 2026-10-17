extends SceneTree

# Headless probe for rewards by encounter role (EncounterRewards): a
# required fight (floor 1's Sputter), an elite (floor 3's Wardling) and the
# region-end boss (floor 5's Greyshelf) each offer the one-of-three card
# choice; an optional basic fight (floor 2's Siltjaw) offers no cards and
# pays the floor's gold times the basic multiplier - and, with its extra
# roll forced, a Samphire to take. A card removal is never a fight's
# reward (the collector's alone): every extra the basic roll can draw is
# a Samphire. The run log matches: reward_cards only where cards were
# offered, reward_samphire.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/reward_roles_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Field cases load the real region scene and win fights through
# RegionField's contact handler, as elite_reward_probe does. The extra is
# forced on the loaded EncounterRewards - the same cached resource
# RegionField loads. Untyped against anything that names the RunState
# autoload: a SceneTree script compiles before the autoloads register.

const CASES := 6
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const REGION_PATH := "res://floors/region1.tres"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const REWARDS_PATH := "res://run/encounter_rewards.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const FLOOR_1 := 0
const FLOOR_2 := 1
const FLOOR_3 := 2
const FLOOR_5 := 4
# Where the log cases write, when run_probes.sh hands over no folder of
# this process's own (RunLogger.dir_override()).
const LOG_DIR := "user://reward_roles_probe"
const SAFETY_SECONDS := 400.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0
# A Samphire's flight to the deck readout, and a margin.
const FLIGHT_WAIT_SECONDS := 1.0

var _run_state: Node = null
var _field: Node = null
var _rewards: Resource = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	# Held for the whole run, so RegionField's load() returns this very
	# resource and the forced rolls below reach it.
	_rewards = load(REWARDS_PATH)
	await _check_offers(FLOOR_1, SPUTTER_PATH, "The required Sputter")
	await _check_offers(FLOOR_3, WARDLING_PATH, "The elite Wardling")
	await _check_offers(FLOOR_5, GREYSHELF_PATH, "The region-end Greyshelf")
	_check_data()
	await _check_basic_gold()
	await _check_samphire()
	RunLogger.set_output_dir("")
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("reward_roles_probe: PASSED")
		quit(0)
	else:
		print("reward_roles_probe: %d FAILED" % _failures)
		quit(1)

# Each fight that matters: a card line, three cards on CHOOSE, and the
# skip logged as reward_cards.
func _check_offers(floor_index: int, enemy_path: String, label: String) -> void:
	var log_dir: String = _open_log()
	var reward: Node = await _win(floor_index, enemy_path)
	if reward != null:
		var card_index: int = _line_ids(reward).find("card")
		_expect(card_index >= 0, "%s offers a card line (%s)" % [label, _line_ids(reward)])
		if card_index >= 0:
			reward.call("_take_line", card_index)
			_expect_eq((reward.get("_offered") as Array).size(), 3, "...three cards on CHOOSE")
			reward.call("_on_dismiss")
			var line: Dictionary = _log_line(log_dir, "reward_cards", "fight")
			_expect_eq((line.get("offered", []) as Array).size(), 3, "...the three logged as reward_cards")
		reward.call("close")
	await _teardown()
	_completed += 1

# The data as set: a basic fight offers no cards and pays 1.5x, its extra
# 30% and always a Samphire, never a removal; every other role offers
# cards, with no extra, the elite at 1.5x.
func _check_data() -> void:
	var basic: Resource = _rewards.get("basic")
	_expect(not bool(basic.get("offers_cards")), "A basic fight offers no cards")
	_expect(is_equal_approx(float(basic.get("gold_multiplier")), 1.5), "...pays 1.5x gold")
	_expect(is_equal_approx(float(basic.get("extra_chance")), 0.3), "...with a 30% extra")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var drawn: Dictionary = {}
	for i in 200:
		drawn[int(_rewards.call("roll_extra", basic, rng))] = true
	_expect_eq(drawn.keys().size(), 2, "...its extra drawn or not over 200 rolls (%s)" % str(drawn.keys()))
	_expect(drawn.has(int(EncounterRewards.Extra.NONE)) and drawn.has(int(EncounterRewards.Extra.SAMPHIRE)), "...and when drawn, always a Samphire (%s)" % str(drawn.keys()))
	_expect_eq(str((_rewards.get("samphire_card") as CardData).card_name), "Samphire", "...the Samphire the Samphire")
	for role in ["required", "elite", "region_end"]:
		var entry: Resource = _rewards.get(role)
		_expect(bool(entry.get("offers_cards")) and float(entry.get("extra_chance")) == 0.0, "%s offers cards and no extra" % role)
	_expect(is_equal_approx(float(_rewards.get("elite").get("gold_multiplier")), 1.5), "The elite pays 1.5x")
	_completed += 1

# The basic fight with no extra rolled: the gold line alone, at the floor's
# range times 1.5, and no card offer anywhere in the log.
func _check_basic_gold() -> void:
	var log_dir: String = _open_log()
	_force_extra(0.0)
	var reward: Node = await _win(FLOOR_2, SILTJAW_PATH)
	if reward != null:
		_expect_eq(_line_ids(reward), ["gold"] as Array[String], "The optional Siltjaw leaves gold alone")
		var span: Vector2i = _gold_range(FLOOR_2)
		var multiplier: float = float(_rewards.get("basic").get("gold_multiplier"))
		var low: int = roundi(span.x * multiplier)
		var high: int = roundi(span.y * multiplier)
		var gold: int = int(reward.get("_gold"))
		_expect(gold >= low and gold <= high, "...at the basic multiplier, %d-%d (got %d)" % [low, high, gold])
		reward.call("_on_dismiss")
		_expect(_log_lines(log_dir, "reward_cards").is_empty(), "...and no reward_cards in the log")
	_restore_extra()
	await _teardown()
	_completed += 1

# A Samphire: its own TAKE line; taken, one more Samphire in the deck,
# logged as reward_samphire; the screen closes once its flight and the
# gold are done.
func _check_samphire() -> void:
	var log_dir: String = _open_log()
	_force_extra(1.0)
	var reward: Node = await _win(FLOOR_2, SILTJAW_PATH)
	if reward != null:
		var ids: Array[String] = _line_ids(reward)
		_expect_eq(ids, ["gold", "samphire"] as Array[String], "A forced Samphire is its own line under the gold")
		var deck: Array = _run_state.get("deck")
		var before: int = _count(deck, "Samphire")
		reward.call("_take_line", ids.find("samphire"))
		_expect_eq(_count(_run_state.get("deck"), "Samphire"), before + 1, "...taken, a Samphire joins the deck")
		_expect(_line_taken(reward, "samphire"), "...the line struck")
		var line: Dictionary = _log_line(log_dir, "reward_samphire", "fight")
		_expect_eq(str(line.get("card")), "Samphire", "...logged as reward_samphire")
		await create_timer(FLIGHT_WAIT_SECONDS).timeout
		_expect(is_instance_valid(reward) and not reward.is_queued_for_deletion(), "...the screen still up with the gold to take")
		if is_instance_valid(reward):
			reward.call("_take_line", ids.find("gold"))
			await process_frame
			_expect(not is_instance_valid(reward) or reward.is_queued_for_deletion(), "...and closed once the gold is taken")
		_expect(_log_lines(log_dir, "reward_cards").is_empty(), "...no reward_cards in the log")
	_restore_extra()
	await _teardown()
	_completed += 1

# --- Helpers ---

func _force_extra(chance: float) -> void:
	_rewards.get("basic").set("extra_chance", chance)

func _restore_extra() -> void:
	_force_extra(0.3)

# A new run on the floor (or this run, `new_run` false), its first enemy
# whose data is `enemy_path` contacted: the fight's controller, or null.
func _start_fight(floor_index: int, enemy_path: String, new_run: bool = true) -> Node:
	if new_run:
		_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	# Floor 2's Siltjaw slot can roll empty: stood here.
	if floor_index == FLOOR_2:
		var forced: Dictionary[StringName, StringName] = {&"siltjaw": &"siltjaw"}
		_field.set("force_options", forced)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == enemy_path:
			target = node as Node3D
			break
	if target == null:
		_fail("no %s on floor %d" % [enemy_path, floor_index + 1])
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor %d" % (floor_index + 1))
		return null
	return overlay.get("battle_controller")

# The fight with `enemy_path` won, and the reward screen it opens - or
# null (a FAIL is recorded).
func _win(floor_index: int, enemy_path: String) -> Node:
	var controller: Node = await _start_fight(floor_index, enemy_path)
	if controller == null:
		return null
	_kill_all(controller)
	await _await_reward_screen()
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	if reward == null:
		_fail("winning on floor %d opened no reward screen" % (floor_index + 1))
	return reward

func _gold_range(floor_index: int) -> Vector2i:
	var region: Resource = load(REGION_PATH)
	var floor_data: Resource = (region.get("floors") as Array)[floor_index]
	return Vector2i(int(floor_data.get("gold_min")), int(floor_data.get("gold_max")))

# Every member to 0 through the controller's own damage path, then the
# end check - kill_order_probe's _kill().
func _kill_all(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: RefCounted = combatants.get(member)
		if combatant == null:
			continue
		combatant.set("hp", 0)
		controller.call("_report_damage", "player", combatant, 99, "card")
	controller.call("_check_battle_end")

func _line_ids(reward: Node) -> Array[String]:
	var ids: Array[String] = []
	for line in reward.get("_lines") as Array:
		ids.append(str((line as RefCounted).get("id")))
	return ids

func _line_taken(reward: Node, id: String) -> bool:
	for line in reward.get("_lines") as Array:
		if str((line as RefCounted).get("id")) == id:
			return bool((line as RefCounted).get("taken"))
	return false

func _count(cards: Array, card_name: String) -> int:
	var count: int = 0
	for card in cards:
		if card != null and (card as CardData).card_name == card_name:
			count += 1
	return count

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

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 2:
		await process_frame

# The run log into this process's folder - run_probes.sh's, else
# LOG_DIR - cleared first, so the next run's file is the only one. The
# last case's run is ended before the clear: left open, the next
# new_run() would end it then, writing its events back into the folder.
func _open_log() -> String:
	if RunLogger.is_run_open():
		_run_state.call("log_run_end", "abandoned")
	var dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	RunLogger.set_output_dir(dir)
	RunLogger.enabled = true
	return dir

# Every line of event `ev` in the folder's run logs.
func _log_lines(dir: String, ev: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file_name in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".jsonl"):
			continue
		for raw in FileAccess.get_file_as_string(dir.path_join(file_name)).split("\n", false):
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary and str((parsed as Dictionary).get("ev")) == ev:
				found.append(parsed)
	return found

# The last line of event `ev` from `source` - a FAIL when there is none.
func _log_line(dir: String, ev: String, source: String) -> Dictionary:
	var found: Dictionary = {}
	for line in _log_lines(dir, ev):
		if str(line.get("source")) == source:
			found = line
	if found.is_empty():
		_fail("no %s line from %s in the run log at %s" % [ev, source, ProjectSettings.globalize_path(dir)])
	return found

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: " + message)
