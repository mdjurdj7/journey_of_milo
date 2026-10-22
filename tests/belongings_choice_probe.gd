extends SceneTree

# Headless probe for the belongings screen's choice: that a take grants
# exactly what the taken column holds - and the Glassbone riding with it,
# where the coin or the pack holds some - and nothing from the other two,
# and that WALK ON grants nothing at all.
#
# Each case is a fresh run (RunState.new_run()) and a fresh
# BelongingsScreen, set up as RegionField.open_belongings_screen() sets
# it up - the case's gold, the pack's distinct cards, the shard's
# Glassbone, Glassbone riding with the coin or the pack or none - and
# added to the root. The probe then takes a column (or walks on) through
# the screen's own gate (_activate()) and asserts the run's gold, deck
# and Glassbone against what that column holds; the coin and the shard
# close after result_hold_time, reporting their column, WALK ON at once
# (-1). A second activation during the hold grants nothing more.
#
# LOOK INSIDE commits: the pack opens (is_picking()), every card it holds
# shown as its own view, and the coin and the shard can no longer be
# taken. A card taken (_take_pick()) is the one added to the deck and the
# screen closes after the hold and the card's flight; TAKE NOTHING grants
# nothing and closes at once - both reporting the pack.
#
# Then the Bedroll's rest itself on the field (RegionField.open_bedroll_
# rest(), BedrollRest): at 50 / 80 HP YES brings 74 / 80 and the Bedroll
# is gone, the HUD in bone through the night and back after; it can't
# open at full HP, nor in a fight.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/belongings_choice_probe.gd
#
# Exit code 0 = passed, 1 = a failure (each printed as FAIL).
#
# Untyped against the project's own classes (get()/call() only), for the
# reason kill_order_probe.gd gives.

const SCREEN_SCENE_PATH := "res://battle/belongings_screen.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
# Any three distinct cards: what the pack holds is the cache's roll, not
# this probe's business.
const CARD_PATHS := ["res://cards/data/slash.tres", "res://cards/data/bite_down.tres", "res://cards/neutral/endure.tres"]
const CACHE_SCENE_PATH := "res://field/belongings_cache.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
# The rest's whole night - in, hold, out - with slack: a cap on the wait,
# not a wait.
const REST_MAX_SEC := 8.0
const GOLD := 45
const GLASSBONE_OFFER := 1
const GLASSBONE := 1
# BelongingsScreen.Slot, and its WALK ON index - TAKE NOTHING's too.
const CASE := 0
const PACK := 1
const SHARD := 2
const WALK_ON := 3
# How the pack is answered: a card's index, or TAKE NOTHING.
const NOTHING := -1
# A shorter hold than the default, so the suite runs quickly; the closing
# assert still checks the screen waits it out.
const HOLD_SEC := 0.4
# The most game time a take may take to close the screen, seconds - a cap
# on the wait for its report, not a wait.
const CLOSE_MAX_SEC := 3.0

var _run_state: Node = null
# Where a taken card flies - a stand-in for the field HUD's DeckPanel.
var _deck_panel: Control = null
var _failures: int = 0

func _initialize() -> void:
	_run()

func _run() -> void:
	_run_state = root.get_node("RunState")
	_deck_panel = Control.new()
	root.add_child(_deck_panel)
	for glassbone_slot in [-1, CASE, PACK]:
		for taken in [CASE, SHARD, WALK_ON]:
			await _check_take(taken, glassbone_slot)
		for answer in [0, CARD_PATHS.size() - 1, NOTHING]:
			await _check_pack(answer, glassbone_slot)
	await _check_second_activation()
	await _check_bedroll_rest()
	_finish()

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _snapshot() -> Dictionary:
	return {
		"gold": _run_state.get("gold"),
		"deck": (_run_state.get("deck") as Array).size(),
		"glassbone": _run_state.get("glassbone"),
	}

func _cards() -> Array[CardData]:
	var cards: Array[CardData] = []
	for path: String in CARD_PATHS:
		cards.append(load(path) as CardData)
	return cards

# The cache's own models, materials and scales, as RegionField hands them
# over.
func _open(glassbone_slot: int) -> Node:
	var cache: Node = (load(CACHE_SCENE_PATH) as PackedScene).instantiate()
	var screen: Node = (load(SCREEN_SCENE_PATH) as PackedScene).instantiate()
	screen.call("setup", "Three packs.", GOLD, _cards(), GLASSBONE_OFFER, glassbone_slot, GLASSBONE, cache.get("object_scene_paths"), cache.get("object_scales"), cache.get("object_material_paths"), _deck_panel)
	cache.free()
	screen.set("result_hold_time", HOLD_SEC)
	root.add_child(screen)
	return screen

func _label(column: String, glassbone_slot: int) -> String:
	return "%s, Glassbone riding with %s" % [column, "none" if glassbone_slot < 0 else ["the coin", "the pack"][glassbone_slot]]

# The coin, the shard or WALK ON.
func _check_take(taken: int, glassbone_slot: int) -> void:
	_new_run()
	var label: String = _label(["case", "pack", "shard", "WALK ON"][taken], glassbone_slot)
	var before: Dictionary = _snapshot()
	var screen: Node = _open(glassbone_slot)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	_expect((screen.call("_takeable_slots") as Array) == [CASE, PACK, SHARD], "%s: all three columns offered" % label)
	screen.call("_activate", taken)

	var after: Dictionary = _snapshot()
	var expected: Dictionary = before.duplicate()
	if taken == CASE:
		expected["gold"] = int(before["gold"]) + GOLD
	elif taken == SHARD:
		expected["glassbone"] = int(before["glassbone"]) + GLASSBONE_OFFER
	if taken != WALK_ON and taken == glassbone_slot:
		expected["glassbone"] = int(expected["glassbone"]) + GLASSBONE
	for key: String in expected:
		_expect(after[key] == expected[key], "%s: %s %s, expected %s" % [label, key, after[key], expected[key]])
	_expect(not bool(screen.call("is_picking")), "%s: the pack stays shut" % label)

	if taken == WALK_ON:
		_expect(report == [-1], "%s: walking on closes at once, reporting -1 (got %s)" % [label, report])
		return
	await create_timer(HOLD_SEC * 0.5).timeout
	_expect(report.is_empty() and is_instance_valid(screen), "%s: still open halfway through the hold" % label)
	await ProbePlay.wait_until(self, func() -> bool: return not report.is_empty(), CLOSE_MAX_SEC)
	_expect(report == [taken], "%s: closed after the hold, reporting %d (got %s)" % [label, taken, report])
	if is_instance_valid(screen):
		screen.free()

# LOOK INSIDE, then `answer`: a card's index, or TAKE NOTHING.
func _check_pack(answer: int, glassbone_slot: int) -> void:
	_new_run()
	var label: String = _label("pack, %s" % ("take nothing" if answer == NOTHING else "take card %d" % answer), glassbone_slot)
	var before: Dictionary = _snapshot()
	var screen: Node = _open(glassbone_slot)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	screen.call("_activate", PACK)

	var expected: Dictionary = before.duplicate()
	if glassbone_slot == PACK:
		expected["glassbone"] = int(before["glassbone"]) + GLASSBONE
	var opened: Dictionary = _snapshot()
	for key: String in expected:
		_expect(opened[key] == expected[key], "%s: opened, %s %s, expected %s" % [label, key, opened[key], expected[key]])
	_expect(bool(screen.call("is_picking")), "%s: the pack is open" % label)
	var views: Array = screen.call("get_pick_views")
	_expect(views.size() == CARD_PATHS.size(), "%s: every card shown (%d of %d)" % [label, views.size(), CARD_PATHS.size()])
	var shown: Array[String] = []
	for view: Control in views:
		shown.append(str((view.get("card_data") as CardData).card_name))
	for card in _cards():
		_expect(shown.has(card.card_name), "%s: %s shown" % [label, card.card_name])
	# Committed: the coin and the shard are gone, WALK ON too.
	for other in [CASE, SHARD, WALK_ON]:
		screen.call("_activate", other)
	_expect(_snapshot() == opened and report.is_empty(), "%s: the coin, the shard and WALK ON grant nothing once it's open" % label)

	screen.call("_take_pick", WALK_ON if answer == NOTHING else answer)
	if answer != NOTHING:
		expected["deck"] = int(before["deck"]) + 1
	var after: Dictionary = _snapshot()
	for key: String in expected:
		_expect(after[key] == expected[key], "%s: %s %s, expected %s" % [label, key, after[key], expected[key]])
	if answer == NOTHING:
		_expect(report == [PACK], "%s: closes at once, reporting the pack (got %s)" % [label, report])
		return
	var deck: Array = _run_state.get("deck")
	# add_card() keeps a copy, so the name, not the resource.
	_expect(not deck.is_empty() and deck.back().get("card_name") == _cards()[answer].card_name, "%s: the card taken is the one added" % label)
	_expect((screen.call("get_pick_views") as Array).size() == 1, "%s: only the card taken is left up" % label)
	screen.call("_take_pick", 0)
	screen.call("_take_pick", WALK_ON)
	_expect(_snapshot() == after, "%s: a second answer changes nothing" % label)
	await create_timer(HOLD_SEC * 0.5).timeout
	_expect(report.is_empty() and is_instance_valid(screen), "%s: still open halfway through the hold" % label)
	await ProbePlay.wait_until(self, func() -> bool: return not report.is_empty(), CLOSE_MAX_SEC)
	_expect(report == [PACK], "%s: closed after the hold and the flight, reporting the pack (got %s)" % [label, report])
	if is_instance_valid(screen):
		screen.free()

# A take, then every other column and WALK ON pressed during its hold:
# nothing more is granted, and the screen still reports the first take.
func _check_second_activation() -> void:
	_new_run()
	var screen: Node = _open(PACK)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	screen.call("_activate", CASE)
	var after_take: Dictionary = _snapshot()
	for other in [PACK, SHARD, WALK_ON, CASE]:
		screen.call("_activate", other)
	var after_presses: Dictionary = _snapshot()
	_expect(after_presses == after_take, "presses during the hold grant nothing more (%s, then %s)" % [after_take, after_presses])
	_expect(not bool(screen.call("is_picking")), "...and the pack stays shut")
	await ProbePlay.wait_until(self, func() -> bool: return not report.is_empty(), CLOSE_MAX_SEC)
	_expect(report == [CASE], "the hold still closes on the first take (got %s)" % [report])
	if is_instance_valid(screen):
		screen.free()

# The rest on the field: at 50 / 80, YES, and once the night is over 74 /
# 80, the Bedroll gone and the field running again; none at full HP; none
# in a fight.
func _check_bedroll_rest() -> void:
	_new_run()
	var field: Node = await _load_field()
	_run_state.call("take_bedroll")
	_run_state.call("set_max_hp", 80)
	_run_state.call("heal", 80)
	_expect(not bool(field.call("open_bedroll_rest")), "Rest: not at full HP")
	_expect(field.call("get_bedroll_rest") == null, "Rest: nothing opened at full HP")
	_run_state.call("lose_hp", 30)
	_expect(int(_run_state.get("player_hp")) == 50, "Rest: set up at 50 / 80 (got %d)" % int(_run_state.get("player_hp")))
	_expect(bool(field.call("open_bedroll_rest")), "Rest: opens at 50 / 80")
	var rest: Node = field.call("get_bedroll_rest")
	_expect(rest != null and not field.can_process(), "Rest: the confirm is up over a frozen field")
	if rest != null:
		await process_frame
		# The Bedroll stands bottom-right: its confirm ends on screen.
		var confirm_right: float = (rest.call("_confirm_origin") as Vector2).x + float(rest.call("_confirm_width"))
		_expect(confirm_right <= field.get_viewport().get_visible_rect().size.x, "Rest: the confirm ends on screen (right edge %.0f)" % confirm_right)
		var hp_line: Control = field.get_node("FieldHUD/HPLine")
		var day_ink: Color = hp_line.get_theme_color("ink", "Battle")
		rest.call("answer_confirm", true)
		# The hold: the Bedroll spent, the HUD in its on-dark (bone) set.
		await ProbePlay.wait_until(self, func() -> bool: return not bool(_run_state.get("has_bedroll")), REST_MAX_SEC)
		var night_ink: Color = hp_line.get_theme_color("ink", "Battle")
		_expect(night_ink != day_ink and night_ink.get_luminance() > day_ink.get_luminance(), "Rest: the HUD goes to bone through the night (%s from %s)" % [night_ink, day_ink])
		await ProbePlay.wait_until(self, func() -> bool: return field.call("get_bedroll_rest") == null, REST_MAX_SEC)
		_expect(hp_line.get_theme_color("ink", "Battle") == day_ink, "Rest: and back to the day's ink after")
	_expect(field.call("get_bedroll_rest") == null, "Rest: the night ends")
	_expect(int(_run_state.get("player_hp")) == 74 and int(_run_state.get("player_max_hp")) == 80, "Rest: 50 / 80 rests to 74 / 80 (got %d / %d)" % [int(_run_state.get("player_hp")), int(_run_state.get("player_max_hp"))])
	_expect(not bool(_run_state.get("has_bedroll")), "Rest: the Bedroll is used up")
	_expect(field.can_process(), "Rest: the field runs again")
	_expect(not bool(field.call("open_bedroll_rest")), "Rest: none left to rest on")

	# In a fight: carried and hurt, still no rest.
	_run_state.call("take_bedroll")
	_run_state.call("lose_hp", 10)
	var started: bool = await _start_fight(field)
	_expect(started, "Rest: a fight starts for the in-fight check")
	if started:
		_expect(not bool(field.call("can_rest")) and not bool(field.call("open_bedroll_rest")), "Rest: not in a fight")
		_expect(bool(_run_state.get("has_bedroll")), "Rest: the Bedroll is kept through the refusal")
	field.queue_free()
	for i in 2:
		await process_frame

# Floor 1, no zone intro, settled.
func _load_field() -> Node:
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	var field: Node = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(field)
	for i in 30:
		await physics_frame
	return field

# The floor's Sputter contacted through RegionField's own handler: true
# once a fight is open.
func _start_fight(field: Node) -> bool:
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == SPUTTER_PATH:
			target = node as Node3D
			break
	if target == null:
		return false
	var wanderer: Node3D = field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	field.call_deferred("_on_enemy_contacted", target)
	await ProbePlay.wait_until(self, func() -> bool: return bool(field.get("_battle_open")), 3.0)
	return bool(field.get("_battle_open"))

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	if _failures <= 30:
		print("FAIL: ", message)

func _finish() -> void:
	print("\nbelongings_choice_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)
