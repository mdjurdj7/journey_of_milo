extends SceneTree

# Headless probe for Blood Advance - 1 Energy, Uncommon Skill, Spent: lose
# 5 HP paid up front (the face's HP badge, not its text) and gain 20 Toll
# in TOTAL, as one SELF_DAMAGE_TOLL effect the way Down Payment does it -
# the 5 HP accrue their own 5 Toll and the effect tops up the other 15.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/blood_advance_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fight cases load the real region scene and start fights through
# RegionField's contact handler, then play the real card through
# BattleController.request_play(), as collateral_probe does: 1 Energy
# paid, 5 HP lost, Toll +20 in all, its own play sound, Spent - and the
# loss counted as self-damage, by The Return's counter and by entering
# Critical (Blue Fastener's Block). Untyped against anything that names
# the RunState autoload.

const CASES := 4
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_PATH := "res://cards/data/blood_advance.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Blood Advance.png"
const SOUND_PATH := "res://assets/audio/cards/Blood Advance/Blood Advance.mp3"
const THE_RETURN_STATUS_PATH := "res://battle/rules/statuses/the_return.tres"
const BLUE_FASTENER_PATH := "res://run/keepsakes/keeper/blue_fastener.tres"
const HP_LOSS := 5
const TOLL_TOTAL := 20
const SAFETY_SECONDS := 180.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	await _check_play()
	await _check_counts_for_the_return()
	await _check_enters_critical()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("blood_advance_probe: PASSED")
		quit(0)
	else:
		print("blood_advance_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "Blood Advance", "The card loads")
	_expect_eq(card.cost, 1, "...costs 1 Energy")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...and Spent")
	_expect_eq(card.description, "Gain 20 Toll.\nSpent.", "...its text: Gain 20 Toll. / Spent.")
	_expect_eq(card.effects.size(), 1, "...one effect")
	if card.effects.size() == 1:
		var effect: CardEffect = card.effects[0]
		_expect_eq([effect.effect_type, effect.value, effect.toll_gain], [CardEffect.EffectType.SELF_DAMAGE_TOLL, HP_LOSS, TOLL_TOTAL], "...SELF_DAMAGE_TOLL, 5 HP, 20 Toll in total (Down Payment's shape)")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...with its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its play sound")
	_expect(load(card.play_sound_path) is AudioStream, "...which loads")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_completed += 1

# --- Fights ---

# The play: the face shows 1 Energy and −5 HP; playing it pays 1 Energy,
# loses 5 HP, leaves Toll 20 up from 0, plays its own sound and goes to
# the Spent pile, not the discard.
func _check_play() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var card: CardData = await _deal(controller)
		var view: CardView = _view(controller, card)
		if view != null:
			_expect_eq(view.cost_label.text, "1", "The face: 1 Energy")
			_expect_eq(view.hp_cost_label.text if view.hp_cost_label.visible else "", "−5 HP", "...and −5 HP in the cost badge")
			_expect(not view.rules_text.get_parsed_text().contains("HP"), "...with no HP in its text")
		var energy_before: int = player.energy
		var hp_before: int = player.hp
		var toll_before: int = player.toll
		await _play(controller, card)
		_expect_eq(energy_before - player.energy, 1, "Playing it costs 1 Energy")
		_expect_eq(hp_before - player.hp, HP_LOSS, "...loses 5 HP")
		_expect_eq(hp_before - int(_run_state.get("player_hp")), HP_LOSS, "...from the run's HP too")
		_expect_eq(player.toll - toll_before, TOLL_TOTAL, "...and leaves Toll +20 in total (%d -> %d)" % [toll_before, player.toll])
		var sound: AudioStreamPlayer = _overlay.get("_card_override_player")
		_expect(sound != null and sound.stream != null and sound.stream.resource_path == SOUND_PATH, "...playing its own sound")
		var deck: Object = controller.get("deck")
		var exhaust: Array = deck.get("exhaust_pile")
		for i in 180:
			if exhaust.has(card):
				break
			await process_frame
		_expect(exhaust.has(card), "...and goes to Spent")
		_expect(not (deck.get("discard_pile") as Array).has(card), "...not the discard")
	await _teardown()
	_completed += 1

# The 5 HP is one self-inflicted loss: The Return's counter moves by one.
func _check_counts_for_the_return() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		Status.apply_to(player.statuses, load(THE_RETURN_STATUS_PATH))
		var counter: Status = _counter(player)
		_expect(counter != null and counter.progress == 0, "The Return's counter opens at 0")
		await _play(controller, await _deal(controller))
		counter = _counter(player)
		_expect(counter != null and counter.progress == 1, "Blood Advance moves it by one: a self-inflicted loss (%s)" % (counter.label() if counter != null else "none"))
		_expect_eq(player.toll, TOLL_TOTAL, "...and still makes exactly 20 Toll")
	await _teardown()
	_completed += 1

# From 25 HP the 5 crosses into Critical (21 and below at 70): Blue
# Fastener's Block for first entering it fires.
func _check_enters_critical() -> void:
	var controller: Node = await _start_fight(25, BLUE_FASTENER_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect(not player.is_critical(), "25 HP is not Critical")
		var block_before: int = player.block
		await _play(controller, await _deal(controller))
		_expect_eq(player.hp, 20, "Blood Advance takes them to 20")
		_expect(player.is_critical(), "...which is Critical")
		_expect_eq(player.block - block_before, 6, "...and Blue Fastener's 6 Block fires: the loss entered Critical")
		_expect_eq(player.toll, TOLL_TOTAL, "...Toll still 20")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _start_fight(hp: int = -1, keepsake_path: String = "") -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if not keepsake_path.is_empty():
		_run_state.call("equip_keepsake", load(keepsake_path))
	if hp > 0:
		_run_state.set("player_hp", hp)
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
	var layer: Node = _field.get_node("BattleLayer")
	_overlay = layer.get_child(0) if layer.get_child_count() > 0 else null
	if _overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = _overlay.get("battle_controller")
	controller.get("deck").call("discard_hand")
	return controller

func _deal(controller: Node) -> CardData:
	var card: CardData = (load(CARD_PATH) as CardData).duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _play(controller: Node, card: CardData) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

func _counter(player: Combatant) -> Status:
	for active: Status in player.statuses:
		if active.has_self_loss_counter():
			return active
	return null

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	_overlay = null
	for i in 3:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
