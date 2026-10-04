extends SceneTree

# Headless probe for Dying Light in a fight: Critical at the start of a
# turn, the refill gives 1 Energy more (Combatant.turn_start_energy());
# not Critical, nothing; entering Critical mid-turn gives nothing that
# turn, only from the next. One at a time: while it's held a second copy
# fades like any unplayable card and can't be played. Its readout line
# matches the card, the Energy readout shows the extra, and it sits beside
# a stance and leaves rotation when played.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/dying_light_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fights load the real region scene and fight floor 1's Sputter through
# RegionField's contact handler, as collateral_probe does, playing real
# cards through BattleController.request_play() and end_turn(). The
# Wanderer keeps 70 max HP, so Critical is 21 and below. Untyped against
# anything that names the RunState autoload.

const CASES := 5
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const DYING_LIGHT_PATH := "res://cards/data/dying_light.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const CRITICAL_HP := 15
const SAFE_HP := 60
const ENEMY_HP := 999
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

	await _check_critical_turn_start()
	await _check_not_critical()
	await _check_mid_turn_entry()
	await _check_one_at_a_time()
	await _check_beside_a_stance()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("dying_light_probe: PASSED")
		quit(0)
	else:
		print("dying_light_probe: %d FAILED" % _failures)
		quit(1)

# Critical as the turn starts: 4 Energy, shown on the readout.
func _check_critical_turn_start() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play_dying_light(controller)
		player.hp = CRITICAL_HP
		await _end_turn(controller)
		_expect(player.is_critical(), "Still Critical at the turn's start (%d HP)" % player.hp)
		_expect_eq(player.energy, 4, "Critical at the turn's start: 3 + 1 Energy")
		var resources: Node = _overlay().get("_resources")
		_expect_eq(int(resources.get("_energy")), 4, "...and the Energy readout shows 4")
		var line: Dictionary = _readout_line("Dying Light")
		_expect_eq(String(line.get("rules", "")), "While Critical, gain 1 Energy at the start of your turn.", "The readout line matches the card")
	await _teardown()
	_completed += 1

func _check_not_critical() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play_dying_light(controller)
		player.hp = SAFE_HP
		await _end_turn(controller)
		_expect_eq(player.energy, 3, "Not Critical at the turn's start: 3, nothing more")
	await _teardown()
	_completed += 1

# Entering Critical mid-turn changes nothing until the next turn starts.
func _check_mid_turn_entry() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play_dying_light(controller)
		player.hp = SAFE_HP
		await _end_turn(controller)
		_expect_eq(player.energy, 3, "The turn starts above the line on 3")
		player.hp = CRITICAL_HP
		controller.emit_signal("hp_changed", player.hp, player.max_hp)
		await process_frame
		_expect_eq(player.energy, 3, "Entering Critical mid-turn: still 3")
		await _end_turn(controller)
		_expect_eq(player.energy, 4, "...the next turn, begun Critical, starts on 4")
	await _teardown()
	_completed += 1

# One at a time: a second copy fades and can't be played while it's held.
func _check_one_at_a_time() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Object = controller.get("deck")
		var first: CardData = await _deal(controller, DYING_LIGHT_PATH)
		var second: CardData = await _deal(controller, DYING_LIGHT_PATH)
		_expect(_view(controller, second).modulate.a >= 1.0, "Before it's held, a Dying Light reads playable")
		controller.call("request_play", _view(controller, first))
		await _settle(controller)
		var view: CardView = _view(controller, second)
		_expect(view != null and is_equal_approx(view.modulate.a, view.unplayable_alpha), "While held, a second copy fades")
		var energy: int = player.energy
		controller.call("request_play", view)
		await _settle(controller)
		_expect((deck.get("hand") as Array).has(second), "...and can't be played: it stays in hand")
		_expect_eq(player.energy, energy, "...nothing spent")
		var held: int = 0
		for active in player.statuses:
			if active.data != null and active.data.id == "dying_light":
				held += 1
		_expect_eq(held, 1, "...one Dying Light held")
	await _teardown()
	_completed += 1

# It sits beside a stance, and leaves rotation once played.
func _check_beside_a_stance() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Object = controller.get("deck")
		var power: CardData = await _deal(controller, DYING_LIGHT_PATH)
		var stance: CardData = await _deal(controller, SELF_EATER_PATH)
		controller.call("request_play", _view(controller, power))
		await _settle(controller)
		controller.call("request_play", _view(controller, stance))
		await _settle(controller)
		_expect(player.stance != null and player.stance.data.id == "self_eater", "Self-Eater taken beside it")
		_expect(Status.find_in(player.statuses, load("res://battle/rules/statuses/dying_light.tres")) != null, "...Dying Light still held")
		_expect((deck.get("exhaust_pile") as Array).has(power), "Dying Light left rotation once played")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _play_dying_light(controller: Node) -> void:
	var card: CardData = await _deal(controller, DYING_LIGHT_PATH)
	controller.call("request_play", _view(controller, card))
	await _settle(controller)

func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	if target == null:
		_fail("no enemy on floor 1")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var overlay: Node = _overlay()
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	(controller.get("player") as Combatant).energy = 3
	await process_frame
	return controller

func _overlay() -> Node:
	if _field == null or not is_instance_valid(_field):
		return null
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand - the first
# call of a case discards the opening hand.
func _deal(controller: Node, path: String) -> CardData:
	var deck: Object = controller.get("deck")
	if not bool(controller.get_meta("probe_dealt", false)):
		controller.set_meta("probe_dealt", true)
		deck.call("discard_hand")
		await process_frame
	var card: CardData = (load(path) as CardData).duplicate()
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _settle(controller: Node) -> void:
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.8).timeout

# The enemy turn and back, the Wanderer's HP held where the case set it
# (Block covers the Sputter's move) so Critical is the case's own.
func _end_turn(controller: Node) -> void:
	var player: Combatant = controller.get("player")
	var hp: int = player.hp
	player.block = 999
	controller.call("end_turn")
	for i in 3000:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame
	_expect_eq(player.hp, hp, "(the enemy turn left HP at %d)" % hp)

func _readout_line(name: String) -> Dictionary:
	var overlay: Node = _overlay()
	if overlay == null:
		return {}
	overlay.call("_refresh_standing_row")
	for item: Dictionary in (overlay.get("_field_hp_bar").get("_row_items") as Array):
		if item.get("name", "") == name:
			return item
	return {}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
