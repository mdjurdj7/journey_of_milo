extends SceneTree

# Headless probe for the belongings screen's choice: that a take grants
# exactly the taken pack's contents - and the Glassbone with it, where
# that pack holds it - and nothing from the other two, and that WALK ON
# grants nothing at all.
#
# Each case is a fresh run (RunState.new_run(), Bent Nail held or not)
# and a fresh BelongingsScreen, set up as RegionField.open_belongings_
# screen() sets it up - the case 45 gold, the pack a card, the bedroll a
# keepsake, Glassbone in one column or none - and added to the root. The
# probe then takes a column (or walks on) through the screen's own gate
# (_activate()) and asserts the run's gold, deck, keepsake and Glassbone
# against what that column holds. Also: a second activation during the
# result hold grants nothing more; the screen stays open through
# result_hold_time and closes after it, reporting the column taken (-1
# for WALK ON); and the bedroll's keepsake is noted offered only when the
# bedroll is taken.
#
# The bedroll with the slot full: the take grants its Glassbone (where it
# carried it) and nothing else, and the screen asks - open past the hold,
# no timeout, other columns and WALK ON ignored. REPLACE (_answer()) puts
# the new keepsake in the slot; KEEP grants nothing more. Either closes
# at once, reporting the bedroll - the take spent.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/belongings_choice_probe.gd
#
# Exit code 0 = passed, 1 = a failure (each printed as FAIL).
#
# Untyped against the project's own classes (get()/call() only), for the
# reason kill_order_probe.gd gives.

const SCREEN_SCENE_PATH := "res://battle/belongings_screen.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_PATH := "res://cards/data/endure.tres"
const OFFERED_PATH := "res://run/keepsakes/frayed_cord.tres"
const HELD_PATH := "res://run/keepsakes/bent_nail.tres"
const OBJECT_PATHS := [
	"res://assets/models/props/belongings/case.glb",
	"res://assets/models/props/belongings/pack.glb",
	"res://assets/models/props/belongings/bedroll.glb",
]
const GOLD := 45
const GLASSBONE := 1
# BelongingsScreen.Slot, and its WALK ON index.
const CASE := 0
const PACK := 1
const BEDROLL := 2
const WALK_ON := 3
# BelongingsScreen.Choice - the full-slot question's answers.
const REPLACE := 0
const KEEP := 1
# A shorter hold than the default, so the suite runs quickly; the closing
# assert still checks the screen waits it out.
const HOLD_SEC := 0.4
# Past the hold: the card's flight (card_flight_duration_sec 0.45) and slack.
const FLIGHT_ROOM_SEC := 0.8

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
	for held: bool in [false, true]:
		for glassbone_slot in [-1, CASE, PACK, BEDROLL]:
			for taken in [CASE, PACK, BEDROLL, WALK_ON]:
				if taken == BEDROLL and held:
					continue
				await _check_take(taken, glassbone_slot, held)
	for glassbone_slot in [-1, CASE, PACK, BEDROLL]:
		for answer in [REPLACE, KEEP]:
			await _check_full_slot(answer, glassbone_slot)
	await _check_second_activation()
	_finish()

func _new_run(held: bool) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if held:
		_run_state.call("equip_keepsake", load(HELD_PATH))

func _snapshot() -> Dictionary:
	return {
		"gold": _run_state.get("gold"),
		"deck": (_run_state.get("deck") as Array).size(),
		"keepsake": _run_state.get("keepsake"),
		"glassbone": _run_state.get("glassbone"),
	}

func _open(glassbone_slot: int) -> Node:
	var screen: Node = (load(SCREEN_SCENE_PATH) as PackedScene).instantiate()
	screen.call("setup", "Three packs.", GOLD, load(CARD_PATH), load(OFFERED_PATH), glassbone_slot, GLASSBONE, PackedStringArray(OBJECT_PATHS), PackedFloat32Array([0.6, 1.0, 1.0]), _deck_panel)
	screen.set("result_hold_time", HOLD_SEC)
	root.add_child(screen)
	return screen

func _check_take(taken: int, glassbone_slot: int, held: bool) -> void:
	_new_run(held)
	var label: String = "%s, Glassbone in %s, %s" % [["case", "pack", "bedroll", "WALK ON"][taken], "none" if glassbone_slot < 0 else str(glassbone_slot), "Bent Nail held" if held else "slot empty"]
	var before: Dictionary = _snapshot()
	var screen: Node = _open(glassbone_slot)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	screen.call("_activate", taken)

	var after: Dictionary = _snapshot()
	var expected: Dictionary = before.duplicate()
	if taken == CASE:
		expected["gold"] = int(before["gold"]) + GOLD
	elif taken == PACK:
		expected["deck"] = int(before["deck"]) + 1
	elif taken == BEDROLL:
		expected["keepsake"] = load(OFFERED_PATH)
	if taken != WALK_ON and taken == glassbone_slot:
		expected["glassbone"] = int(before["glassbone"]) + GLASSBONE
	for key: String in expected:
		_expect(after[key] == expected[key], "%s: %s %s, expected %s" % [label, key, after[key], expected[key]])
	if taken == PACK:
		var deck: Array = _run_state.get("deck")
		# add_card() keeps a copy, so the name, not the resource.
		_expect(not deck.is_empty() and deck.back().get("card_name") == load(CARD_PATH).get("card_name"), "%s: the pack's card is the one added" % label)
	var noted: bool = (_run_state.get("keepsakes_offered") as Array).has(load(OFFERED_PATH).get("id"))
	_expect(noted == (taken == BEDROLL), "%s: the bedroll's keepsake %s offered" % [label, "noted" if noted else "not noted"])

	if taken == WALK_ON:
		_expect(report == [-1], "%s: walking on closes at once, reporting -1 (got %s)" % [label, report])
		return
	await create_timer(HOLD_SEC * 0.5).timeout
	_expect(report.is_empty() and is_instance_valid(screen), "%s: still open halfway through the hold" % label)
	await create_timer(HOLD_SEC * 0.5 + FLIGHT_ROOM_SEC).timeout
	_expect(report == [taken], "%s: closed after the hold, reporting %d (got %s)" % [label, taken, report])
	if is_instance_valid(screen):
		screen.free()

# The bedroll taken with Bent Nail held: only its Glassbone at the take,
# the question held open past the hold with nothing else answering, then
# `answer` - REPLACE takes the new keepsake, KEEP nothing more - closing
# at once on the bedroll.
func _check_full_slot(answer: int, glassbone_slot: int) -> void:
	_new_run(true)
	var label: String = "bedroll, slot full, %s, Glassbone in %s" % [["REPLACE", "KEEP"][answer], "none" if glassbone_slot < 0 else str(glassbone_slot)]
	var before: Dictionary = _snapshot()
	var screen: Node = _open(glassbone_slot)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	screen.call("_activate", BEDROLL)

	var expected: Dictionary = before.duplicate()
	if glassbone_slot == BEDROLL:
		expected["glassbone"] = int(before["glassbone"]) + GLASSBONE
	var asked: Dictionary = _snapshot()
	for key: String in expected:
		_expect(asked[key] == expected[key], "%s: at the reveal, %s %s, expected %s" % [label, key, asked[key], expected[key]])
	_expect((_run_state.get("keepsakes_offered") as Array).has(load(OFFERED_PATH).get("id")), "%s: the bedroll's keepsake noted offered at the reveal" % label)
	_expect(bool(screen.get("_asking")), "%s: the question is open" % label)

	# No timeout, and nothing but an answer closes it.
	for other in [CASE, PACK, BEDROLL, WALK_ON]:
		screen.call("_activate", other)
	await create_timer(HOLD_SEC + FLIGHT_ROOM_SEC).timeout
	_expect(report.is_empty() and is_instance_valid(screen), "%s: still asking past the hold (got %s)" % [label, report])
	_expect(_snapshot() == asked, "%s: the other columns and WALK ON grant nothing while it asks" % label)

	screen.call("_answer", answer)
	if answer == REPLACE:
		expected["keepsake"] = load(OFFERED_PATH)
	var after: Dictionary = _snapshot()
	for key: String in expected:
		_expect(after[key] == expected[key], "%s: after the answer, %s %s, expected %s" % [label, key, after[key], expected[key]])
	_expect(report == [BEDROLL], "%s: the answer closes at once, reporting the bedroll (got %s)" % [label, report])
	screen.call("_answer", REPLACE if answer == KEEP else KEEP)
	_expect(_snapshot() == after, "%s: a second answer changes nothing" % label)
	if is_instance_valid(screen):
		screen.free()

# A take, then every other column and WALK ON pressed during its hold:
# nothing more is granted, and the screen still reports the first take.
func _check_second_activation() -> void:
	_new_run(false)
	var screen: Node = _open(PACK)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	screen.call("_activate", CASE)
	var after_take: Dictionary = _snapshot()
	for other in [PACK, BEDROLL, WALK_ON, CASE]:
		screen.call("_activate", other)
	var after_presses: Dictionary = _snapshot()
	_expect(after_presses == after_take, "presses during the hold grant nothing more (%s, then %s)" % [after_take, after_presses])
	await create_timer(HOLD_SEC + FLIGHT_ROOM_SEC).timeout
	_expect(report == [CASE], "the hold still closes on the first take (got %s)" % [report])
	if is_instance_valid(screen):
		screen.free()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	if _failures <= 30:
		print("FAIL: ", message)

func _finish() -> void:
	print("\nbelongings_choice_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)
