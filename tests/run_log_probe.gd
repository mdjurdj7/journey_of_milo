extends SceneTree

# Headless probe for the run log (RunLogger): one short scripted run -
# floor 1, the Sputter fought with real cards through BattleController.
# request_play() / confirm_target(), the reward screen's gold and card
# taken - written to a folder of the probe's own, then read back and
# checked:
#
#   - the events in order: run_start, floor_entered, fight_start,
#     fight_end, the reward lines, run_end
#   - the fight's sums: turns, every card with its turn, Energy, hp_cost
#     (Collateral's swap) and hp_effect (Hold Fast's and Blood Arc's own
#     self-damage), damage dealt equal to the Sputter's HP, HP that
#     reconciles (start - taken + healed + reclaimed = end), block used,
#     Toll that reconciles
#   - the reward choice: the three offered, the one taken
#
# Then the same run again with the log switched off (RegionField.run_
# logging_enabled false): no file written, and the run's generator, the
# offer and the HP left exactly as they were with it on. And the headless
# guard: with no folder of its own, a headless instance writes nothing.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/run_log_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Run by hand, the log stays in user://run_log_probe/ for a look
# afterwards (each run of the probe clears it first); under
# tools/run_probes.sh it goes to the per-process --runlog-dir folder the
# script deletes after. Untyped against anything that names the
# RunState autoload.

const LOG_DIR := "user://run_log_probe"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const COLLATERAL_PATH := "res://cards/data/collateral.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const HOLD_FAST_PATH := "res://cards/data/hold_fast.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const ENDURE_PATH := "res://cards/neutral/endure.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const GLOBAL_SEED := 20261004
const RUN_SEED := 4242
const MAX_TURNS := 12
const SAFETY_SECONDS := 240.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0

# This process's log folder: run_probes.sh's per-process --runlog-dir
# (RunLogger.dir_override()) when it hands one over, so a second copy of
# this probe running at once never sees this one's files - else LOG_DIR.
var _log_dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
# What the scripted run did, as the probe saw it: [turn, card name].
var _played: Array = []
var _turns: int = 0
var _enemy_max_hp: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_clear_dir()

	_check_headless_guard()

	var on: Dictionary = await _scripted_run(true)
	var files: PackedStringArray = DirAccess.get_files_at(_log_dir)
	_expect_eq(files.size(), 1, "The logged run wrote one file")
	if files.size() == 1:
		_check_log(_log_dir.path_join(files[0]), on)

	var off: Dictionary = await _scripted_run(false)
	_expect_eq(DirAccess.get_files_at(_log_dir).size(), 1, "With the log off, no file is written")
	_expect_eq(off.get("rng_state"), on.get("rng_state"), "The run's generator ends in the same state, log on or off")
	_expect_eq(off.get("offered"), on.get("offered"), "...the reward offers the same cards")
	_expect_eq(off.get("hp_end"), on.get("hp_end"), "...and the fight leaves the same HP")
	_expect_eq(off.get("played"), on.get("played"), "...over the same plays")

	RunLogger.set_output_dir("")
	RunLogger.enabled = true
	if _failures == 0:
		print("run_log_probe: PASSED")
		quit(0)
	else:
		print("run_log_probe: %d FAILED" % _failures)
		quit(1)

# Headless with no folder of its own: a new run opens no file.
func _check_headless_guard() -> void:
	RunLogger.set_output_dir("")
	RunLogger.enabled = true
	_run_state.call("new_run", load(CHARACTER_PATH))
	_expect(not RunLogger.is_run_open(), "Headless, with no probe folder, the log stays shut")

# The run: new run, floor 1, the Sputter fought to a win with a fixed
# script of cards, the reward's gold and first card taken, then a quit.
# What it saw, for the on/off comparison.
func _scripted_run(logging: bool) -> Dictionary:
	print("\n=== run with logging %s" % ("on" if logging else "off"))
	RunLogger.set_output_dir(_log_dir)
	RunLogger.enabled = logging
	_played = []
	_turns = 0
	seed(GLOBAL_SEED)
	_run_state.call("new_run", load(CHARACTER_PATH))
	(_run_state.get("rng") as RandomNumberGenerator).seed = RUN_SEED
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", logging)
	root.add_child(_field)
	for i in 30:
		await physics_frame

	var seen: Dictionary = {}
	var controller: Node = await _start_fight()
	if controller == null:
		await _teardown()
		return seen

	# Turn 1: Collateral, then Reckoning on its swap (0 Energy, 5 HP);
	# Hold Fast (Block 5, 2 HP its own); Blood Arc (3 HP its own).
	_turns = 1
	_fresh_hand(controller)
	await _play(controller, await _deal(controller, COLLATERAL_PATH))
	await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
	await _play(controller, await _deal(controller, HOLD_FAST_PATH))
	await _play(controller, await _deal(controller, BLOOD_ARC_PATH))
	# Turn 2 on: Endure for Block on the second (the Sputter's strike
	# comes after it), then Slashes until it falls.
	while _battle_open() and _turns < MAX_TURNS:
		await controller.call("end_turn")
		for i in 3:
			await process_frame
		if not _battle_open():
			break
		_turns += 1
		_fresh_hand(controller)
		if _turns == 2:
			await _play(controller, await _deal(controller, ENDURE_PATH))
		while _battle_open() and int((controller.get("player") as Combatant).energy) >= 1:
			await _play(controller, await _deal(controller, SLASH_PATH), _field_enemy(controller))
	_expect(not _battle_open(), "The Sputter falls inside %d turns" % MAX_TURNS)
	seen["hp_end"] = int(_run_state.get("player_hp"))
	seen["played"] = _played.duplicate()

	# The reward screen, after the frame's return.
	await _await_reward_screen()
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	_expect(reward != null, "The win opens the reward screen")
	if reward != null:
		var ids: Array[String] = []
		for line in reward.get("_lines") as Array:
			ids.append(str((line as RefCounted).get("id")))
		if ids.has("gold"):
			reward.call("_take_line", ids.find("gold"))
		if ids.has("card"):
			reward.call("_take_line", ids.find("card"))
			var views: Array = reward.get("_card_views")
			var offered: Array = []
			for view: CardView in views:
				offered.append(view.card_data.card_name)
			seen["offered"] = offered
			if not views.is_empty():
				var first: CardView = views[0]
				reward.call("_on_choice_clicked", first.card_data, first)
		for i in 90:
			await process_frame
			if not is_instance_valid(reward) or reward.is_queued_for_deletion():
				break
	# A keepsake the Sputter left, if any, is left.
	var offer: Node = _child_with_script(_field, "keepsake_offer.gd")
	if offer != null:
		offer.call("_activate", 1)
		await process_frame
	seen["rng_state"] = (_run_state.get("rng") as RandomNumberGenerator).state
	seen["end_tally"] = [int(_run_state.get("player_hp")), int(_run_state.get("player_max_hp")), (_run_state.get("deck") as Array).size()]
	_run_state.call("log_run_end", "quit")
	await _teardown()
	return seen

# --- The log ---

func _check_log(path: String, seen: Dictionary) -> void:
	var lines: Array[Dictionary] = []
	var text: String = FileAccess.get_file_as_string(path)
	print("\n--- %s" % ProjectSettings.globalize_path(path))
	for raw in text.split("\n", false):
		print(raw)
		var parsed: Variant = JSON.parse_string(raw)
		_expect(parsed is Dictionary, "Every line is a JSON object")
		if parsed is Dictionary:
			lines.append(parsed)
	print("---")
	var events: Array[String] = []
	# The fight's detail lines (hits, self-losses, heals, mechanics) sit
	# between its start and its end; the run's own order is the rest.
	var core: Array[String] = []
	for line in lines:
		events.append(str(line.get("ev")))
		if not RunLogger._DETAIL_EVENTS.has(str(line.get("ev"))):
			core.append(str(line.get("ev")))
	print("events: ", events)
	_expect_eq(core.slice(0, 4), ["run_start", "floor_entered", "fight_start", "fight_end"] as Array[String], "The run opens: run_start, floor_entered, fight_start, fight_end")
	_expect(events.has("reward_gold"), "The gold taken is logged")
	_expect(events.has("reward_cards"), "The card choice is logged")
	_expect_eq(events.back(), "run_end", "run_end is the last line")
	for line in lines:
		_expect_eq(int(line.get("v", 0)), RunLogger.FORMAT_VERSION, "Every line carries the format version")

	var start: Dictionary = _first(lines, "run_start")
	_expect(str(start.get("version", "")) != "", "run_start records a version")
	_expect_eq(str(start.get("class")), "Wanderer", "run_start: the class")
	_expect(start.get("deck") is Dictionary and not (start.get("deck") as Dictionary).is_empty(), "run_start: the starting deck as counts")

	var fight_start: Dictionary = _first(lines, "fight_start")
	_expect_eq(str(fight_start.get("encounter")), "Sputter", "fight_start: the encounter")
	_expect_eq(fight_start.get("enemies"), ["sputter"], "...its enemies by file")
	_expect_eq(int(fight_start.get("floor", -1)), 0, "...on floor index 0")
	# Format 2: the encounter's members and role.
	var members: Array = fight_start.get("members", [])
	_expect_eq(members.size(), 1, "fight_start: one member")
	if not members.is_empty():
		var member: Dictionary = members[0]
		_expect_eq([str(member.get("id")), int(member.get("floor_index", -1)), member.get("required"), member.get("elite"), member.get("region_end")], ["sputter", 0, true, false, false], "...the Sputter: floor index 0, required, not elite, not region-end")
	_expect_eq(str(fight_start.get("role")), "required", "...a required fight")

	var fight: Dictionary = _first(lines, "fight_end")
	_expect_eq(str(fight.get("result")), "win", "fight_end: a win")
	_expect_eq(fight.get("debug"), false, "...not a debug one")
	_expect_eq(int(fight.get("turns", 0)), _turns, "...over the turns played")
	var cards: Array = fight.get("cards", [])
	_expect_eq(cards.size(), _played.size(), "...every card played listed")
	for index in mini(cards.size(), _played.size()):
		var card: Dictionary = cards[index]
		_expect_eq([int(card.get("turn")), str(card.get("card"))], _played[index], "Card %d: its turn and name" % index)
	if cards.size() >= 4:
		_expect_card(cards[0], "Collateral", 0, 0, 0)
		_expect_card(cards[1], "Reckoning", 0, 5, 0)
		_expect_card(cards[2], "Hold Fast", 1, 0, 2)
		_expect_card(cards[3], "Blood Arc", 2, 0, 3)
		_expect_eq(int((cards[2] as Dictionary).get("block")), 5, "Hold Fast: 5 Block gained")
		_expect(int((cards[3] as Dictionary).get("dealt")) > 0, "Blood Arc: damage dealt")
		_expect_eq((cards[3] as Dictionary).get("target"), null, "...with no target")
		_expect_eq(str((cards[1] as Dictionary).get("target")), "Sputter", "Reckoning: aimed at the Sputter")

	var taken: Dictionary = fight.get("damage_taken", {})
	var by_source: Dictionary = taken.get("by_source", {})
	var source_sum: int = 0
	for source in by_source:
		source_sum += int(by_source[source])
	_expect_eq(source_sum, int(taken.get("total", -1)), "Damage taken: the sources add up to the total")
	_expect_eq(int(by_source.get("self", 0)), 5 + 2 + 3, "...10 of it self-inflicted (5 + 2 + 3)")
	_expect(int(by_source.get("Sputter", 0)) > 0, "...and some from the Sputter")
	var grace: Dictionary = fight.get("grace", {})
	var hp_start: int = int(fight.get("hp_start", -1))
	var hp_end: int = int(fight.get("hp_end", -1))
	_expect_eq(hp_start, int(fight_start.get("hp", -2)), "hp_start is fight_start's HP")
	_expect_eq(hp_end, int(seen.get("hp_end", -1)), "hp_end is the run's HP when the fight ended")
	_expect_eq(hp_start - int(taken.get("total", 0)) + int(fight.get("healed", 0)) + int(grace.get("reclaimed", 0)), hp_end, "HP reconciles: start - taken + healed + reclaimed = end")
	var dealt: Dictionary = fight.get("damage_dealt", {})
	_expect_eq(int(dealt.get("total", -1)), _enemy_max_hp, "Damage dealt is the Sputter's whole HP, overkill apart")
	var card_dealt: int = 0
	for card: Dictionary in cards:
		card_dealt += int(card.get("dealt"))
	_expect_eq(card_dealt, int(dealt.get("total", -1)), "...all of it by the cards")
	var block: Dictionary = fight.get("block", {})
	_expect(int(block.get("gained", 0)) >= 5 + 8, "Block gained: Hold Fast's 5 and Endure's 8 at least")
	_expect(int(block.get("used", 0)) > 0 and int(block.get("used", 0)) <= int(block.get("gained", 0)), "Block used: some, never more than gained")
	var toll: Dictionary = fight.get("toll", {})
	_expect(int(toll.get("gained", 0)) >= 10, "Toll gained: the 10 HP self-inflicted at least")
	_expect(int(toll.get("spent", 0)) > 0, "Toll spent: Reckoning's")
	_expect_eq(int(toll.get("start", 0)) + int(toll.get("gained", 0)) - int(toll.get("spent", 0)), int(toll.get("end", -1)), "Toll reconciles: start + gained - spent = end")

	# Format 2: sources, hits, turns.
	var self_by: Dictionary = taken.get("self_by_source", {})
	var self_by_ints: Dictionary = {}
	for key in self_by:
		self_by_ints[key] = int(self_by[key])
	_expect_eq(self_by_ints, {"status:collateral": 5, "card:Hold Fast": 2, "card:Blood Arc": 3}, "Self-loss by source: Collateral's price, Hold Fast's and Blood Arc's HP")
	var self_lines: int = 0
	var attack_hp: int = 0
	for line in lines:
		if str(line.get("ev")) == "self_loss":
			self_lines += 1
		if str(line.get("ev")) == "enemy_attack":
			_expect_eq(str(line.get("enemy")), "sputter", "enemy_attack: the Sputter's")
			_expect(not str(line.get("intent")).is_empty(), "...naming its intent")
			var hits_hp: int = 0
			for hit: Dictionary in line.get("hits", []):
				hits_hp += int(hit.get("to_hp", 0))
			_expect_eq(hits_hp, int(line.get("to_hp", -1)), "...its hits adding up to its HP")
			attack_hp += int(line.get("to_hp", 0))
	_expect_eq(self_lines, 3, "A self_loss line per self-inflicted loss")
	_expect_eq(attack_hp, int(by_source.get("Sputter", -1)), "The Sputter's attack lines add up to what it took")
	var by_intent_sum: int = 0
	for key in (taken.get("by_intent", {}) as Dictionary):
		by_intent_sum += int(taken["by_intent"][key])
	_expect_eq(by_intent_sum, int(by_source.get("Sputter", -1)), "...and so do its intents")
	var toll_gained_by: Dictionary = toll.get("gained_by_source", {})
	var toll_gained_sum: int = 0
	for key in toll_gained_by:
		toll_gained_sum += int(toll_gained_by[key])
	_expect_eq(toll_gained_sum, int(toll.get("gained", -1)), "Toll gained by source adds up to the gain")
	_expect_eq((toll.get("spent_by_source", {}) as Dictionary).get("card:Reckoning"), toll.get("spent"), "...and all of the spend is Reckoning's")
	if cards.size() >= 2:
		_expect_eq(int((cards[1] as Dictionary).get("toll_spent", -1)), int(toll.get("spent", -2)), "Reckoning's entry: the Toll it spent")
	var turn_log: Array = fight.get("turn_log", [])
	_expect_eq(turn_log.size(), _turns, "turn_log: a line per turn")
	var spent_energy: int = 0
	for card: Dictionary in cards:
		spent_energy += int(card.get("energy"))
	var logged_energy: int = 0
	for turn: Dictionary in turn_log:
		logged_energy += int(turn.get("energy_spent", 0))
		_expect(turn.get("energy_start") != null and turn.get("energy_left") != null, "...turn %s: Energy at its start and left at its end" % turn.get("turn"))
		_expect(int(turn.get("drawn", 0)) > 0, "...turn %s: cards drawn" % turn.get("turn"))
	_expect_eq(logged_energy, spent_energy, "...the Energy it says was spent is the cards'")
	_expect_eq(fight.get("deaths"), ["sputter"], "deaths: the Sputter")

	var reward: Dictionary = _first(lines, "reward_cards")
	_expect_eq(str(reward.get("source")), "fight", "reward_cards: from the fight")
	_expect_eq(reward.get("offered"), seen.get("offered"), "...the cards offered")
	var offered: Array = seen.get("offered", [])
	_expect_eq(reward.get("taken"), offered[0] if not offered.is_empty() else null, "...and the one taken")

	var end: Dictionary = _first(lines, "run_end")
	_expect_eq(str(end.get("cause")), "quit", "run_end: quit")
	_expect_eq(end.get("debug_run"), false, "...not a debug run")
	_expect_eq(int(end.get("fights", 0)), 1, "...after one fight")
	_expect_eq([int(end.get("fights_won", -1)), int(end.get("floors_crossed", -1))], [1, 0], "...the tally: one fight won, no floor crossed")
	_expect_eq([int(end.get("hp", -1)), int(end.get("max_hp", -1)), int(end.get("deck_size", -1))], seen.get("end_tally"), "...HP, max HP and deck size as the run stood")

func _expect_card(card: Dictionary, card_name: String, energy: int, hp_cost: int, hp_effect: int) -> void:
	_expect_eq([str(card.get("card")), int(card.get("energy")), int(card.get("hp_cost")), int(card.get("hp_effect"))], [card_name, energy, hp_cost, hp_effect], "%s: Energy, hp_cost, hp_effect" % card_name)

func _first(lines: Array[Dictionary], ev: String) -> Dictionary:
	for line in lines:
		if str(line.get("ev")) == ev:
			return line
	return {}

# --- The fight ---

func _start_fight() -> Node:
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	if target == null:
		_fail("no enemy on floor 1")
		return null
	_enemy_max_hp = int(target.get("enemy_data").get("max_hp"))
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started")
		return null
	return overlay.get("battle_controller")

func _battle_open() -> bool:
	return _field != null and bool(_field.get("_battle_open"))

func _fresh_hand(controller: Node) -> void:
	controller.get("deck").call("discard_hand")

func _deal(controller: Node, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _play(controller: Node, card: CardData, target: Node = null) -> void:
	var view: CardView = null
	for candidate: CardView in controller.get("_hand_container").call("_card_views"):
		if candidate.card_data == card:
			view = candidate
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	_played.append([_turns, card.card_name])
	controller.call("request_play", view)
	if target != null:
		controller.call("confirm_target", target)
	for i in 600:
		await process_frame
		if not _battle_open() or not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

# --- Helpers ---

func _clear_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_log_dir)
	for file in DirAccess.get_files_at(_log_dir):
		DirAccess.remove_absolute(_log_dir.path_join(file))

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

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 3:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
