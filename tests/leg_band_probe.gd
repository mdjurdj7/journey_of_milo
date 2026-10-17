extends SceneTree

# Headless probe for Leg Band and a pack felled together.
#
# Leg Band (run/keepsakes/leg_band.tres, TrinketData.draw_on_multi_hit
# 1): the first card each turn that takes HP from two or more enemies
# draws 1 - a second such card that turn draws nothing, the next turn's
# first draws again, a card whose hits are all blocked but one draws
# nothing, and without the keepsake nothing is drawn at all.
#
# Felled together (BattleController.felled_together(), EncounterOption.
# felled_together_keepsake / felled_together_line): one card that kills
# the whole pack makes the win offer the option's keepsake and says its
# line over them; the pack killed across two turns does neither. And a
# status's gained_line is said over the enemy that gains it.
#
# The fights are floor 2's island dragonflies (three, one cluster) and a
# deck of Carves (6 to all, cost 1), through BattleController's own
# request_play() and end_turn(); the trio's option is given the keepsake
# and the line for the probe (the loaded FloorData, put back after).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/leg_band_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against what names the RunState autoload, as the other fight
# probes are.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_2_PATH := "res://floors/region1_floor2.tres"
const LEG_BAND_PATH := "res://run/keepsakes/leg_band.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const DRAGONFLY_PATH := "res://battle/rules/enemies/dragonfly.tres"
const ISLAND_SLOT := &"island"
const TRIO_OPTION := &"dragonfly_trio"
const LINE := "Probe: they fell in step."
const GAINED_LINE := "Probe: the other keeps dancing."
const FLOOR_2 := 1
const PLAYER_HP := 999
const SAFETY_SECONDS := 420.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var leg_band := load(LEG_BAND_PATH) as TrinketData
	_expect_eq(leg_band.display_name, "Leg Band", "The keepsake is the Leg Band")
	_expect_eq(leg_band.describe(), "The first time each turn a card damages two or more enemies, draw 1.", "...its rules line")
	var option: EncounterOption = _island_option()
	if option == null:
		_fail("no island option on floor 2")
		quit(1)
		return
	option.felled_together_keepsake = leg_band
	option.felled_together_line = LINE
	await _check_draws(leg_band)
	await _check_no_keepsake()
	await _check_one_through()
	await _check_felled_together(leg_band)
	await _check_felled_apart(leg_band)
	await _check_gained_line()
	option.felled_together_keepsake = null
	option.felled_together_line = ""
	if _failures == 0:
		print("leg_band_probe: PASSED")
		quit(0)
	else:
		print("leg_band_probe: %d FAILED" % _failures)
		quit(1)

# Held: the first Carve each turn draws 1 (the hand keeps its size), the
# second that turn draws nothing; the next turn's first draws again.
func _check_draws(leg_band: TrinketData) -> void:
	var controller: Node = await _start_fight(leg_band)
	if controller == null:
		return
	_toughen(controller)
	var deck: Deck = controller.get("deck")
	var hand: int = deck.hand.size()
	await _play_carve(controller)
	_expect_eq(deck.hand.size(), hand, "Leg Band: the turn's first Carve into three draws 1 (hand stays %d)" % hand)
	await _play_carve(controller)
	_expect_eq(deck.hand.size(), hand - 1, "...the second draws nothing")
	await controller.call("end_turn")
	_toughen(controller)
	hand = deck.hand.size()
	await _play_carve(controller)
	_expect_eq(deck.hand.size(), hand, "...and the next turn's first draws again")
	await _teardown()

# Without it, a Carve into three draws nothing.
func _check_no_keepsake() -> void:
	var controller: Node = await _start_fight(null)
	if controller == null:
		return
	_toughen(controller)
	var deck: Deck = controller.get("deck")
	var hand: int = deck.hand.size()
	await _play_carve(controller)
	_expect_eq(deck.hand.size(), hand - 1, "No keepsake: a Carve into three draws nothing")
	await _teardown()

# Held, but two of the three behind Block that takes the whole of it: one
# enemy loses HP, so nothing is drawn.
func _check_one_through() -> void:
	var controller: Node = await _start_fight(load(LEG_BAND_PATH) as TrinketData)
	if controller == null:
		return
	_toughen(controller)
	var members: Array = controller.get("enemies")
	for index in members.size():
		if index > 0:
			_combatant(controller, members[index]).block = 99
	var deck: Deck = controller.get("deck")
	var hand: int = deck.hand.size()
	await _play_carve(controller)
	_expect_eq(deck.hand.size(), hand - 1, "Two of three blocking it all: one loses HP, nothing drawn")
	await _teardown()

# One Carve kills all three: felled together - the line over them, and
# the win offers the option's keepsake.
func _check_felled_together(leg_band: TrinketData) -> void:
	var controller: Node = await _start_fight(null)
	if controller == null:
		return
	for member: Node in (controller.get("enemies") as Array):
		_combatant(controller, member).hp = 5
	await _play_carve(controller)
	_expect(bool(controller.call("felled_together")), "One Carve kills the three: felled together")
	_expect_eq(_line_text(), LINE, "...the option's line is said")
	await create_timer(4.0).timeout
	_expect(_field.get("_pending_keepsake") == leg_band, "...and the win offers its keepsake")
	await _teardown()

# One killed on the first turn, the other two on the second: not felled
# together - no line, no keepsake.
func _check_felled_apart(leg_band: TrinketData) -> void:
	var controller: Node = await _start_fight(null)
	if controller == null:
		return
	var members: Array = (controller.get("enemies") as Array).duplicate()
	_combatant(controller, members[0]).hp = 1
	await _play_carve(controller)
	for index in members.size():
		if index > 0:
			_combatant(controller, members[index]).hp = 99
	await controller.call("end_turn")
	for member: Node in (controller.get("enemies") as Array):
		_combatant(controller, member).hp = 5
	await _play_carve(controller)
	_expect_eq((controller.get("enemies") as Array).size(), 0, "Across two turns: all three dead")
	_expect(not bool(controller.call("felled_together")), "...not felled together")
	_expect(_line_text() != LINE, "...no line")
	await create_timer(4.0).timeout
	_expect(_field.get("_pending_keepsake") != leg_band, "...and no keepsake")
	await _teardown()

# A status with a gained_line, gained by an enemy: the line over it.
func _check_gained_line() -> void:
	var controller: Node = await _start_fight(null)
	if controller == null:
		return
	var status := StatusData.new()
	status.id = "probe_gained"
	status.display_name = "Probe"
	status.gained_line = GAINED_LINE
	var member: Node = (controller.get("enemies") as Array)[0]
	controller.emit_signal("enemy_status_gained", member, status)
	_expect_eq(_line_text(), GAINED_LINE, "A status gained with a line: said over its enemy")
	await _teardown()

# --- Helpers ---

func _island_option() -> EncounterOption:
	var floor_data := load(FLOOR_2_PATH) as FloorData
	for slot in floor_data.slots:
		if slot != null and slot.slot_id == ISLAND_SLOT:
			return slot.find_option(TRIO_OPTION)
	return null

# HP enough that the Carves kill no one.
func _toughen(controller: Node) -> void:
	for member: Node in (controller.get("enemies") as Array):
		_combatant(controller, member).hp = 99
		_combatant(controller, member).max_hp = 99

func _play_carve(controller: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 9
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	var members: Array = controller.get("enemies")
	if bool(controller.call("is_awaiting_target")) and not members.is_empty():
		controller.call("confirm_target", members[0])
	await create_timer(2.0).timeout

func _line_text() -> String:
	var hud: Node = _field.get_node_or_null(^"FieldHUD")
	if hud == null:
		return ""
	for child in hud.find_children("*", "Label", true, false):
		if child is WorldVoiceLine:
			return (child as Label).text
	return ""

func _start_fight(keepsake: TrinketData) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(CARVE_PATH) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	if keepsake != null:
		_run_state.call("equip_keepsake", keepsake)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_2)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	# The island stands its trio, whichever way the run's seed would roll.
	var force: Dictionary[StringName, StringName] = {ISLAND_SLOT: TRIO_OPTION}
	_field.set("force_options", force)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == DRAGONFLY_PATH and node.get("slot_id") == ISLAND_SLOT:
			target = node as Node3D
	if target == null:
		_fail("no island dragonfly on floor 2")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(0.0, 0.0, 1.5)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 2")
		return null
	await create_timer(2.5).timeout
	var controller: Node = overlay.get("battle_controller")
	_expect_eq((controller.get("enemies") as Array).size(), 3, "The island fight has the three")
	return controller

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
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
