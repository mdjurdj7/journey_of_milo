extends SceneTree

# Headless probe for Leverage - the card, its status and the cost
# reduction behind them (StatusData.next_card_cost_reduction): it spends
# 5 Toll like Come Due (and can't be played on less), and the next card
# played - of any cost, on any later turn - costs 2 less Energy, never
# below 0. Two Leverages before another card give that card both. House
# Key's free card comes first and a cost replacement (Collateral) judges
# what's left, so a card Leverage takes below 2 leaves its charge.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/leverage_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases read the data; fight cases load the real region scene and
# start fights through RegionField's contact handler, as collateral_probe
# does, then play real cards through BattleController.request_play() /
# confirm_target() - so the commit-time spend and the faces are the
# game's own. Each case discards the hand and deals itself fresh copies
# of the cards it needs. Untyped against anything that names the
# RunState autoload.

const CASES := 10
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const LEVERAGE_PATH := "res://cards/data/leverage.tres"
const LEVERAGE_STATUS_PATH := "res://battle/rules/statuses/leverage.tres"
const COLLATERAL_PATH := "res://cards/data/collateral.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const RANSOM_PATH := "res://cards/data/ransom.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const HOUSE_KEY_PATH := "res://run/keepsakes/keeper/house_key.tres"
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

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
	await _check_toll()
	await _check_not_enough_toll()
	await _check_next_card_only()
	await _check_any_card_spends_it()
	await _check_persists_then_ends()
	await _check_two_stack()
	await _check_collateral_order()
	await _check_house_key_first()
	await _check_faces_and_sentence()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("leverage_probe: PASSED")
		quit(0)
	else:
		print("leverage_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(LEVERAGE_PATH)
	var status: StatusData = load(LEVERAGE_STATUS_PATH)
	_expect_eq(card.cost, 0, "Leverage costs 0")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...and Spent")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...with mipmapped art")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect_eq(card.effects.size(), 2, "Two effects")
	_expect_eq([card.effects[0].effect_type, card.effects[0].toll_cost], [CardEffect.EffectType.SPEND_TOLL, 5], "...Spend 5 Toll first")
	_expect_eq([card.effects[1].effect_type, card.effects[1].status_data], [CardEffect.EffectType.APPLY_STATUS, status], "...then the Leverage status")
	_expect_eq(card.description, "Spend %d Toll.\nYour next card costs %d less.\nSpent." % [card.effects[0].toll_cost, status.next_card_cost_reduction], "The card's text carries its own numbers")
	_expect_eq([status.next_card_cost_reduction, status.default_duration_turns, status.stack_rule], [2, StatusData.DURATION_UNTIL_REMOVED, StatusData.StackRule.IGNORE], "The status: 2 less, until spent, stacks by count")
	var statuses: Array[Status] = []
	Status.apply_to(statuses, status)
	_expect_eq(statuses[0].label(), "Leverage", "One play: the line reads Leverage")
	_expect_eq(statuses[0].describe(), "Your next card costs 2 less.", "...and the reveal")
	Status.apply_to(statuses, status)
	_expect_eq(statuses.size(), 1, "A second play adds to the same status")
	_expect_eq(statuses[0].label(), "Leverage ×2", "...Leverage ×2")
	_expect_eq(statuses[0].describe(), "Your next card costs 4 less.", "...and the reveal says 4")
	_completed += 1

# --- Fights ---

# Played on 7 Toll it spends exactly 5, costs no Energy, leaves the
# status and is Spent.
func _check_toll() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 7
		var leverage: CardData = await _deal(controller, LEVERAGE_PATH)
		await _play(controller, leverage)
		_expect_eq(player.toll, 2, "On 7 Toll, Leverage spends exactly 5")
		_expect_eq(player.energy, 3, "...costs no Energy")
		_expect_eq(_status_label(player), "Leverage", "...and leaves Leverage")
		var exhaust: Array = controller.get("deck").get("exhaust_pile")
		for i in 180:
			if exhaust.has(leverage):
				break
			await process_frame
		_expect(exhaust.has(leverage), "...and is Spent")
	await _teardown()
	_completed += 1

# On 4 Toll it can't be played, as Come Due can't: blocked, faded, and a
# play request does nothing at all.
func _check_not_enough_toll() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 4
		var leverage: CardData = await _deal(controller, LEVERAGE_PATH)
		_expect(EffectResolver.card_blocked(leverage, player), "On 4 Toll Leverage is blocked")
		_expect(not controller.get("_hand_container").call("_can_play", leverage, player.energy), "...and the hand fades it")
		controller.call("request_play", _view(controller, leverage))
		for i in 10:
			await process_frame
		_expect_eq(player.toll, 4, "...a play request spends no Toll")
		_expect_eq(player.energy, 3, "...nor Energy")
		_expect_eq(_status_label(player), "", "...applies nothing")
		_expect(_view(controller, leverage) != null, "...and it stays in the hand")
		player.toll = 5
		_expect(not EffectResolver.card_blocked(leverage, player), "On 5 it can be played")
	await _teardown()
	_completed += 1

# The next card costs 2 less, never below 0: Slash (1) costs 0, and the
# card after it pays full price.
func _check_next_card_only() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 5
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		var slash: CardData = await _deal(controller, SLASH_PATH)
		_expect_eq(player.energy_cost(slash), 0, "Under Leverage, Slash's 1 reads 0, not -1")
		await _play(controller, slash, _field_enemy(controller))
		_expect_eq(player.energy, 3, "...and costs no Energy")
		_expect_eq(_status_label(player), "", "...spending Leverage")
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 1, "The card after it costs its 2 again")
	await _teardown()
	_completed += 1

# Any other card spends it, a 0-cost one included - Collateral here, with
# nothing for the reduction to take off.
func _check_any_card_spends_it() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 5
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		_expect_eq(_status_label(player), "", "A 0-cost Collateral spends Leverage")
		_expect_eq(_collateral_label(player), "Collateral ×1", "...and its own charge waits")
	await _teardown()
	_completed += 1

# The reduction waits through a whole enemy turn for the next card, and
# the next fight starts without it.
func _check_persists_then_ends() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 5
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		await controller.call("end_turn")
		_expect_eq(_status_label(player), "Leverage", "Leverage is still there next turn")
		controller.get("deck").call("discard_hand")
		player.energy = 3
		await process_frame
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 3, "...and the turn's first card costs 2 less: Reckoning 0")
		_expect_eq(_status_label(player), "", "...spending it")
	await _teardown()
	controller = await _start_fight()
	if controller != null:
		_expect_eq(_status_label(controller.get("player")), "", "The next fight starts without it")
	await _teardown()
	_completed += 1

# Two Leverages, then a card: the second adds to the first rather than
# spending it, and one card takes all 4 off - Ransom's 3 to 0 - then it's
# gone.
func _check_two_stack() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 10
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		_expect_eq(player.toll, 0, "Two Leverages spend 10 Toll")
		_expect_eq(_status_label(player), "Leverage ×2", "...and read Leverage ×2")
		_expect_eq(Status.cost_reduction(player.statuses), 4, "...4 off the next card")
		var ransom: CardData = await _deal(controller, RANSOM_PATH)
		var blood_arc: CardData = await _deal(controller, BLOOD_ARC_PATH)
		_expect_eq(player.energy_cost(ransom), 0, "...Ransom's 3 reads 0")
		_expect_eq(player.energy_cost(blood_arc), 0, "...Blood Arc's 2 reads 0")
		await _play(controller, ransom)
		_expect_eq(player.energy, 3, "Ransom costs no Energy")
		_expect_eq(_status_label(player), "", "...and spends both")
		_expect_eq(player.energy_cost(blood_arc), 2, "Blood Arc reads 2 again")
	await _teardown()
	_completed += 1

# House Key -> Leverage -> Collateral: with a Collateral charge and
# Leverage waiting, Reckoning's 2 comes down to 0 before Collateral asks,
# so it costs 0 Energy, 0 HP, and the charge stays for the next one.
func _check_collateral_order() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 5
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		_expect_eq(_collateral_label(player), "Collateral ×1", "Leverage (0) passes Collateral's charge by")
		_expect_eq(_status_label(player), "Leverage", "...and Leverage waits")
		var hp_before: int = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 3, "Reckoning under Leverage and Collateral costs 0 Energy")
		_expect_eq(player.hp, hp_before, "...and 0 HP")
		_expect_eq(_collateral_label(player), "Collateral ×1", "...and the Collateral charge remains")
		_expect_eq(_status_label(player), "", "...while Leverage is spent")
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(hp_before - player.hp, 5, "The next Reckoning takes the charge: 5 HP")
	await _teardown()
	_completed += 1

# House Key's free first card is "the next card": it costs 0 before
# Leverage is asked, and spends a waiting Leverage all the same. (In play
# Leverage would itself be the free card - the status is applied directly
# here to reach the ordering.)
func _check_house_key_first() -> void:
	var controller: Node = await _start_fight(HOUSE_KEY_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
		Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
		var hp_before: int = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 3, "House Key's free Reckoning costs 0 Energy")
		_expect_eq(player.hp, hp_before, "...and no HP")
		_expect_eq(_status_label(player), "", "...and spends the waiting Leverage")
		_expect_eq(_collateral_label(player), "Collateral ×1", "...while Collateral keeps its charge")
	await _teardown()
	_completed += 1

# While Leverage waits every face in the hand reads its reduced cost, and
# affordability follows; the readout line says what it does; and its
# Toll spend brings a marked enemy's Sentence a turn closer.
func _check_faces_and_sentence() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var enemy: Combatant = _enemy(controller)
		Status.apply_to(enemy.statuses, load(SENTENCE_STATUS_PATH))
		_expect_eq(_sentence_label(enemy), "Sentence 4", "The enemy carries Sentence 4")
		player.toll = 5
		player.energy = 1
		var hand: Object = controller.get("_hand_container")
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var ransom: CardData = await _deal(controller, RANSOM_PATH)
		_expect_eq([_face(controller, reckoning), _face(controller, slash), _face(controller, ransom)], ["2", "1", "3"], "Before Leverage: 2, 1, 3")
		_expect(not hand.call("_can_play", reckoning, player.energy), "...and on 1 Energy Reckoning is out of reach")
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		_expect_eq(_sentence_label(enemy), "Sentence 3", "Leverage's Toll spend takes a turn off Sentence")
		_expect_eq([_face(controller, reckoning), _face(controller, slash), _face(controller, ransom)], ["0", "0", "1"], "While it waits: 0, 0, 1")
		_expect(hand.call("_can_play", reckoning, player.energy), "...and Reckoning is in reach")
		var line: Status = Status.find_in(player.statuses, load(LEVERAGE_STATUS_PATH))
		_expect(line != null and line.describe() == "Your next card costs 2 less.", "The readout: Your next card costs 2 less.")
		await _play(controller, slash, _field_enemy(controller))
		_expect_eq([_face(controller, reckoning), _face(controller, ransom)], ["2", "3"], "Once spent: 2 and 3 again")
	await _teardown()
	_completed += 1

# --- Helpers ---

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, with an empty hand and 3 Energy: holding the keepsake
# at `keepsake_path` when given.
func _start_fight(keepsake_path: String = "") -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if not keepsake_path.is_empty():
		_run_state.call("equip_keepsake", load(keepsake_path))
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
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	controller.get("deck").call("discard_hand")
	(controller.get("player") as Combatant).energy = 3
	await process_frame
	return controller

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand.
func _deal(controller: Node, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
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

# Plays `card` from the hand through the controller's own path, and waits
# for the play to resolve.
func _play(controller: Node, card: CardData, target: Node = null) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if target != null:
		controller.call("confirm_target", target)
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

func _face(controller: Node, card: CardData) -> String:
	var view: CardView = _view(controller, card)
	return view.cost_label.text if view != null else "missing"

func _status_label(player: Combatant) -> String:
	return _label_of(player, "leverage")

func _collateral_label(player: Combatant) -> String:
	return _label_of(player, "collateral")

func _sentence_label(enemy: Combatant) -> String:
	return _label_of(enemy, "sentence")

func _label_of(combatant: Combatant, id: String) -> String:
	for active in combatant.statuses:
		if active.data != null and active.data.id == id:
			return active.label()
	return ""

func _enemy(controller: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).values()[0]

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
