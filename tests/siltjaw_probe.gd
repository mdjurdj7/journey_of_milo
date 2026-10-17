extends SceneTree

# Headless probe for the Siltjaw: its Snap -> Charge -> Dig loop (the
# Charge a plain hit, nothing to break); the Dig's three mounds, under one
# drawn at random; under the sand its Bite, then its Erupt, surfacing on
# its own; the intent preview's pips toward the eruption, never a mound;
# found at its own mound - up, Exposed (50% more) until its next move,
# the eruption off; a wrong mound collapsing with a bite from below; a
# Denied Dig lost. The rules cases drive EnemyTurn on the real .tres; the
# fight cases load floor 2 and play real cards through BattleController -
# the mounds standing in a row with the body's node at the middle one
# whichever it is under, a rect for each and none for the body, a wrong
# mound's card wasted and bitten back, the right one's card at +50%, a
# Carve finding it, and the eruption coming up at its mound.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/siltjaw_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 11
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const EXPOSED_PATH := "res://battle/rules/statuses/exposed.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const FLOOR_2 := 1
const HP := 42
const SNAP := 6
const CHARGE := 14
const BITE := 5
const ERUPT := 13
const MOUNDS := 3
const SLASH := 6
const CARVE := 6
const EXPOSED_SCALE := 1.5
const DIG_INDEX := 2
const PLAYER_HP := 999
# The least the mounds' screen centres stand apart across the screen.
const MIN_SCREEN_GAP_PX := 40.0
const SAFETY_SECONDS := 400.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_check_data()
	_check_never_found()
	_check_preview()
	_check_found()
	_check_wrong_mound()
	_check_denied_dig()
	await _check_fight_dig()
	await _check_fight_wrong()
	await _check_fight_right()
	await _check_fight_carve()
	await _check_fight_erupt()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("siltjaw_probe: PASSED")
		quit(0)
	else:
		print("siltjaw_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var data: EnemyData = _siltjaw()
	_expect_eq(data.max_hp, HP, "The Siltjaw has %d HP" % HP)
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect_eq(data.intents.size(), 3, "...of three moves")
	if data.intents.size() == 3:
		var snap: EnemyIntent = data.intents[0]
		var charge: EnemyIntent = data.intents[1]
		var dig: EnemyIntent = data.intents[2]
		_expect(snap.intent_name == "Snap" and snap.type == EnemyIntent.IntentType.ATTACK and snap.value == SNAP, "Snap first, %d" % SNAP)
		_expect(charge.intent_name == "Charge" and charge.value == CHARGE and charge.interrupt_threshold == 0 and charge.on_interrupt == null, "...then Charge %d, nothing to break" % CHARGE)
		_expect(dig.intent_name == "Dig" and dig.type == EnemyIntent.IntentType.DIG and dig.mound_count == MOUNDS, "...then Dig, %d mounds" % MOUNDS)
		_expect(dig.under_moves.size() == 2 and dig.under_moves[0].value == BITE and dig.under_moves[1].value == ERUPT, "...under the sand Bite %d, then Erupt %d" % [BITE, ERUPT])
		_expect(dig.found_status != null and dig.found_status.resource_path == EXPOSED_PATH, "...found, Exposed")
	_completed += 1

# Nothing played: Snap 6, Charge 14, Dig (nothing), Bite 5, Erupt 13 and
# up, then Snap again - under one of its three mounds while down.
func _check_never_found() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var lost: Array[int] = []
	var dug: Array[bool] = []
	for turn in 6:
		var before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		lost.append(before - player.hp)
		dug.append(enemy.dug_in)
		if turn == 2:
			_expect(enemy.mounds.size() == MOUNDS and enemy.true_mound >= 0 and enemy.true_mound < MOUNDS, "Dug: %d mounds, under number %d" % [enemy.mounds.size(), enemy.true_mound])
	_expect_eq(lost, [SNAP, CHARGE, 0, BITE, ERUPT, SNAP] as Array[int], "Snap, Charge, Dig, Bite, Erupt, Snap")
	_expect_eq(dug, [false, false, true, true, false, false] as Array[bool], "...under the sand from the Dig until the Erupt")
	var seen: Dictionary = {}
	for trial in 60:
		var other: Combatant = _enemy(data)
		other.current_intent_index = DIG_INDEX
		EnemyTurn.take_turn(other, data, player)
		seen[other.true_mound] = true
	_expect_eq(seen.size(), MOUNDS, "Across 60 digs it is under each mound in turn (%d seen)" % seen.size())
	_completed += 1

# Under the sand, the preview shows the move and its pips toward the
# eruption - 1 of 2, then 2 of 2 - and nothing that names a mound.
func _check_preview() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_expect(not EnemyTurn.preview_intent(enemy, data, player).has("threshold"), "The Snap has no threshold")
	enemy.current_intent_index = 1
	_expect(not EnemyTurn.preview_intent(enemy, data, player).has("threshold"), "...nor the Charge")
	enemy.current_intent_index = DIG_INDEX
	EnemyTurn.take_turn(enemy, data, player)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(preview["per_hit"]), int(preview["dig_stage"]), int(preview["dig_stages"])], [BITE, 0, 2], "Dug: Bite %d, the first of two turns under" % BITE)
	for key: String in preview:
		_expect(not key.contains("mound"), "...nothing in it names a mound (%s)" % key)
	EnemyTurn.take_turn(enemy, data, player)
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(preview["per_hit"]), int(preview["dig_stage"]), int(preview["dig_stages"])], [ERUPT, 1, 2], "Then Erupt %d, the second" % ERUPT)
	_completed += 1

# Found: up, Exposed - 10 lands 15 - the eruption off; its next move is
# the Snap, and Exposed goes with it.
func _check_found() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	enemy.current_intent_index = DIG_INDEX
	EnemyTurn.take_turn(enemy, data, player)
	_expect(EnemyTurn.unearth(enemy, data), "Its mound found: up")
	_expect(not enemy.dug_in and enemy.mounds.is_empty(), "...out of the sand")
	_expect(_has(enemy, EXPOSED_PATH), "...Exposed")
	_expect_eq(Status.apply_modifiers(10, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE), 15, "...10 lands 15")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Snap", "...the Snap next, no eruption")
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, SNAP, "The Snap lands %d" % SNAP)
	_expect(not _has(enemy, EXPOSED_PATH), "...and Exposed is gone with it")
	_completed += 1

# A wrong mound collapses - once - and it bites from below for 5; its own
# mound never collapses; three mounds go to two.
func _check_wrong_mound() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	enemy.current_intent_index = DIG_INDEX
	EnemyTurn.take_turn(enemy, data, player)
	var wrong: int = (enemy.true_mound + 1) % MOUNDS
	_expect(EnemyTurn.collapse_mound(enemy, wrong), "A wrong mound collapses")
	_expect_eq(enemy.mounds.size(), MOUNDS - 1, "...%d left" % (MOUNDS - 1))
	_expect(not EnemyTurn.collapse_mound(enemy, wrong), "...not twice")
	_expect(not EnemyTurn.collapse_mound(enemy, enemy.true_mound), "Its own never collapses")
	var before: int = player.hp
	var bite: Dictionary = EnemyTurn.strike_from_below(enemy, data, player)
	_expect(bool(bite.get("attacked", false)) and before - player.hp == BITE, "...and it bites from below for %d" % BITE)
	_expect(enemy.dug_in, "...still under")
	_completed += 1

# A Denied Dig is lost: nothing digs, the Snap is next.
func _check_denied_dig() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	enemy.current_intent_index = DIG_INDEX
	Status.apply_to(enemy.statuses, load(DENIED_PATH) as StatusData)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, _player())
	_expect(bool(result["denied"]) and not enemy.dug_in, "A Denied Dig digs nothing")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Snap", "...the Snap next")
	_completed += 1

# --- Fights ---

# The Dig in a fight: three mounds in a row, left to right on screen and
# each its own click; the body's node at the middle one whichever it is
# under; a rect for each mound and none for the body; the intent's pips.
func _check_fight_dig() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		await _dig(controller, combatant)
		_expect(bool(siltjaw.call("is_dug_in")) and combatant.dug_in, "Dug in")
		var at: Vector3 = siltjaw.global_position
		var middle: Vector3 = siltjaw.call("get_mound_position", 1)
		_expect(Vector2(at.x - middle.x, at.z - middle.z).length() < 0.05, "...its node at the middle mound, under number %d" % combatant.true_mound)
		var spread: float = (siltjaw.call("get_mound_position", 0) as Vector3).distance_to(siltjaw.call("get_mound_position", 2))
		_expect(spread > 3.0, "...the row spread %.2f m end to end" % spread)
		await _arm(controller)
		controller.call("_refresh_enemy_rects")
		var rects: Array = controller.get("_mound_rects")
		_expect_eq(rects.size(), MOUNDS, "Armed: a rect for each mound")
		_expect(not (controller.get("_enemy_rects") as Dictionary).has(siltjaw), "...none for the body")
		# Each its own click: no mound's rect holds another's centre.
		for entry: Dictionary in rects:
			for other: Dictionary in rects:
				if entry != other and (entry["rect"] as Rect2).has_point((other["rect"] as Rect2).get_center()):
					_fail("Mound %d's rect covers mound %d's centre" % [int(entry["mound"]), int(other["mound"])])
		var xs: Array[float] = []
		for entry: Dictionary in rects:
			xs.append((entry["rect"] as Rect2).get_center().x)
		xs.sort()
		_expect(xs.size() == MOUNDS and xs[1] - xs[0] > MIN_SCREEN_GAP_PX and xs[2] - xs[1] > MIN_SCREEN_GAP_PX, "...left to right on screen (%s)" % str(xs))
		var preview: Dictionary = controller.call("get_intent_preview", siltjaw)
		_expect_eq([int(preview.get("dig_stage", -1)), int(preview.get("dig_stages", -1))], [0, 2], "...its intent's pips 1 of 2")
		controller.call("cancel_target")
	await _teardown()
	_completed += 1

# A Slash at a wrong mound: the Siltjaw untouched, that mound collapsed,
# a bite of 5 back.
func _check_fight_wrong() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		var player: Combatant = controller.get("player")
		await _dig(controller, combatant)
		var hp: int = combatant.hp
		var before: int = player.hp
		var wrong: int = (combatant.true_mound + 1) % MOUNDS
		await _play_at(controller, siltjaw, wrong)
		_expect_eq(combatant.hp, hp, "A Slash at a wrong mound: the Siltjaw untouched")
		_expect(combatant.dug_in and combatant.mounds.size() == MOUNDS - 1, "...that mound collapsed, %d left, still under" % combatant.mounds.size())
		_expect_eq(before - player.hp, BITE, "...and it bites from below for %d" % BITE)
	await _teardown()
	_completed += 1

# A Slash at its own mound: up there, Exposed, the Slash landing 9; the
# node at that mound.
func _check_fight_right() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		await _dig(controller, combatant)
		var spot: Vector3 = siltjaw.call("get_mound_position", combatant.true_mound)
		var hp: int = combatant.hp
		await _play_at(controller, siltjaw, combatant.true_mound)
		_expect(not combatant.dug_in and not bool(siltjaw.call("is_dug_in")), "A Slash at its own mound: found, up")
		_expect(_has(combatant, EXPOSED_PATH), "...Exposed")
		_expect_eq(hp - combatant.hp, int(SLASH * EXPOSED_SCALE), "...the Slash landing %d" % int(SLASH * EXPOSED_SCALE))
		var at: Vector3 = siltjaw.global_position
		_expect(Vector2(at.x - spot.x, at.z - spot.z).length() < 0.05, "...up at that mound")
	await _teardown()
	_completed += 1

# A Carve finds it, whichever mound: up, the Carve landing 9.
func _check_fight_carve() -> void:
	var controller: Node = await _start_fight(CARVE_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		await _dig(controller, combatant)
		var hp: int = combatant.hp
		await _play_first(controller)
		_expect(not combatant.dug_in, "A Carve finds it")
		_expect_eq(hp - combatant.hp, int(CARVE * EXPOSED_SCALE), "...landing %d" % int(CARVE * EXPOSED_SCALE))
	await _teardown()
	_completed += 1

# Never found: the Bite, then the Erupt - up at its own mound, 13.
func _check_fight_erupt() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		var player: Combatant = controller.get("player")
		await _dig(controller, combatant)
		var spot: Vector3 = siltjaw.call("get_mound_position", combatant.true_mound)
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, BITE, "Unfound: the Bite, %d" % BITE)
		before = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, ERUPT, "...then the Erupt, %d" % ERUPT)
		_expect(not combatant.dug_in and not bool(siltjaw.call("is_dug_in")), "...and it is up")
		var at: Vector3 = siltjaw.global_position
		_expect(Vector2(at.x - spot.x, at.z - spot.z).length() < 0.05, "...at its own mound")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _siltjaw() -> EnemyData:
	return load(SILTJAW_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _player() -> Combatant:
	return Combatant.new(500)

func _has(combatant: Combatant, path: String) -> bool:
	for active: Status in combatant.statuses:
		if active.data != null and active.data.resource_path == path:
			return true
	return false

# A new run on floor 2, the fight started on its Siltjaw with a deck of
# `card_path` alone. The controller, or null (a FAIL is recorded).
func _start_fight(card_path: String) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(card_path) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_2)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == SILTJAW_PATH:
			target = node as Node3D
	if target == null:
		_fail("no Siltjaw on floor 2")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 2")
		return null
	await ProbePlay.settle_fight(self, _field, overlay.get("battle_controller"))
	var controller: Node = overlay.get("battle_controller")
	var members: Array = controller.get("enemies")
	_expect(members.size() == 1 and members[0] == target, "The fight is the Siltjaw alone")
	return controller

# Its Dig queued and the turn ended: under the sand, its mounds up.
func _dig(controller: Node, combatant: Combatant) -> void:
	combatant.current_intent_index = DIG_INDEX
	await _end_turn(controller)
	await create_timer(1.0).timeout

func _end_turn(controller: Node) -> void:
	await controller.call("end_turn")
	await create_timer(0.8).timeout

# The first card in hand armed, Energy topped up.
func _arm(controller: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	await process_frame

# The first card in hand at mound `mound`, waited out - a bite from below
# included.
func _play_at(controller: Node, siltjaw: Node, mound: int) -> void:
	await _arm(controller)
	controller.call("confirm_target", siltjaw, mound)
	await _settle(controller)

# The first card in hand, at no one (a Carve).
func _play_first(controller: Node) -> void:
	await _arm(controller)
	await _settle(controller)

func _settle(controller: Node) -> void:
	for i in 180:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(1.0).timeout

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
