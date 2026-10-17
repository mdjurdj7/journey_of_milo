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
# The bedroll holding the Bedroll (offer_bedroll(), floor 2's cache): its
# kind is BEDROLL, the take puts one in the pack (RunState.has_bedroll)
# and no keepsake is offered or shown; a second screen with one carried
# names it "(carrying one)" and won't take it, the other columns still
# offered. Then the rest itself on the field (RegionField.open_bedroll_
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
const CARD_PATH := "res://cards/neutral/endure.tres"
const OFFERED_PATH := "res://run/keepsakes/frayed_cord.tres"
const BEDROLL_PATH := "res://run/data/bedroll.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
# The rest's whole night - in, hold, out - with slack: a cap on the wait,
# not a wait.
const REST_MAX_SEC := 8.0
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
	await _check_bedroll_take()
	await _check_bedroll_rest()
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
	var tiles: Array = screen.call("get_keepsake_tiles")
	if taken == BEDROLL:
		_expect(tiles.size() == 1 and tiles[0].call("get_keepsake") == load(OFFERED_PATH), "%s: the reveal shows the bedroll's keepsake as a tile" % label)
	else:
		_expect(tiles.is_empty(), "%s: no keepsake tile for another column" % label)

	if taken == WALK_ON:
		_expect(report == [-1], "%s: walking on closes at once, reporting -1 (got %s)" % [label, report])
		return
	await create_timer(HOLD_SEC * 0.5).timeout
	_expect(report.is_empty() and is_instance_valid(screen), "%s: still open halfway through the hold" % label)
	await ProbePlay.wait_until(self, func() -> bool: return not report.is_empty(), CLOSE_MAX_SEC)
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
	var tiles: Array = screen.call("get_keepsake_tiles")
	_expect(tiles.size() == 2, "%s: HELD and OFFERED tiles both shown (got %d)" % [label, tiles.size()])
	if tiles.size() == 2:
		var held_tile: Control = tiles[0]
		var offered_tile: Control = tiles[1]
		_expect(held_tile.call("get_keepsake") == load(HELD_PATH) and offered_tile.call("get_keepsake") == load(OFFERED_PATH), "%s: the held one first, the offered one second" % label)
		_expect(is_equal_approx(held_tile.position.y, offered_tile.position.y) and held_tile.position.x + held_tile.call("get_tile_size").x < offered_tile.position.x, "%s: side by side, apart" % label)
		_expect(float(screen.call("_choice_baseline", REPLACE)) > offered_tile.position.y + offered_tile.call("get_tile_size").y, "%s: the choices sit under the tiles" % label)

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
	await ProbePlay.wait_until(self, func() -> bool: return not report.is_empty(), CLOSE_MAX_SEC)
	_expect(report == [CASE], "the hold still closes on the first take (got %s)" % [report])
	if is_instance_valid(screen):
		screen.free()

# The Bedroll in the bedroll's place: BEDROLL under it, the take into the
# pack - no keepsake noted or shown - and the screen closing on the
# bedroll after its hold. Then, with one carried, "(carrying one)": the
# column can't be taken or focused, a press grants nothing, and the case
# is taken as ever.
func _check_bedroll_take() -> void:
	_new_run(false)
	var screen: Node = _open_bedroll(-1)
	var report: Array = []
	screen.connect("closed", func(column: int) -> void: report.append(column))
	await process_frame
	_expect(str(screen.call("kind_text", BEDROLL)) == "BEDROLL", "Bedroll offer: the column reads BEDROLL (got '%s')" % screen.call("kind_text", BEDROLL))
	_expect(bool(screen.call("can_take", BEDROLL)), "Bedroll offer: it can be taken with none carried")
	screen.call("_activate", BEDROLL)
	_expect(bool(_run_state.get("has_bedroll")), "Bedroll offer: taken, one is carried")
	_expect(_run_state.get("keepsake") == null, "Bedroll offer: no keepsake comes with it")
	_expect(not (_run_state.get("keepsakes_offered") as Array).has(load(OFFERED_PATH).get("id")), "Bedroll offer: no keepsake noted offered")
	_expect((screen.call("get_keepsake_tiles") as Array).is_empty(), "Bedroll offer: no keepsake tile in the reveal")
	await ProbePlay.wait_until(self, func() -> bool: return not report.is_empty(), CLOSE_MAX_SEC)
	_expect(report == [BEDROLL], "Bedroll offer: closed after the hold, reporting the bedroll (got %s)" % [report])
	if is_instance_valid(screen):
		screen.free()

	var second: Node = _open_bedroll(-1)
	var second_report: Array = []
	second.connect("closed", func(column: int) -> void: second_report.append(column))
	await process_frame
	_expect(str(second.call("kind_text", BEDROLL)).ends_with("(carrying one)"), "Carrying one: the offer says so (got '%s')" % second.call("kind_text", BEDROLL))
	_expect(not bool(second.call("can_take", BEDROLL)), "Carrying one: the second can't be taken")
	var before: Dictionary = _snapshot()
	second.call("_set_focus", -1)
	second.call("_activate", BEDROLL)
	_expect(_snapshot() == before and bool(_run_state.get("has_bedroll")), "Carrying one: pressing it grants nothing")
	_expect(not bool(second.get("_done")) and second_report.is_empty(), "Carrying one: the screen stays open for the other two")
	_expect(not (second.call("_takeable_slots") as Array).has(BEDROLL), "Carrying one: it can't be focused")
	second.call("_activate", CASE)
	_expect(int(_run_state.get("gold")) == int(before["gold"]) + GOLD, "Carrying one: the case is still taken")
	await ProbePlay.wait_until(self, func() -> bool: return not second_report.is_empty(), CLOSE_MAX_SEC)
	if is_instance_valid(second):
		second.free()

func _open_bedroll(glassbone_slot: int) -> Node:
	var screen: Node = (load(SCREEN_SCENE_PATH) as PackedScene).instantiate()
	screen.call("setup", "Three packs.", GOLD, load(CARD_PATH), load(OFFERED_PATH), glassbone_slot, GLASSBONE, PackedStringArray(OBJECT_PATHS), PackedFloat32Array([0.6, 1.0, 1.0]), _deck_panel)
	screen.call("offer_bedroll", load(BEDROLL_PATH))
	screen.set("result_hold_time", HOLD_SEC)
	root.add_child(screen)
	return screen

# The rest on the field: at 50 / 80, YES, and once the night is over 74 /
# 80, the Bedroll gone and the field running again; none at full HP; none
# in a fight.
func _check_bedroll_rest() -> void:
	_new_run(false)
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
