extends SceneTree

# Headless probe for Owed Time - Rare 3-Energy Skill, Spent: spend 20 Toll
# (Owed Time+ 16) and take another turn after this one. It applies the
# Owed Time status (StatusData.grants_extra_turn, a charge per play); when
# the player's turn ends with a charge up, one goes and the enemy turn is
# skipped (Status.take_extra_turn(), BattleController._finish_turn()): the
# turn ends as any does - hand discarded, this-turn statuses gone - the
# enemies don't act and their intents stand, and the next player turn
# starts in full - Energy refilled, Dying Light, Marrow, Venom, the draw.
# A Twice Over copy queues a second. Every play is Spent, original and
# copy: no chain past the cards and the Toll there are.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/owed_time_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants. The fight cases play them through BattleController on the
# real region scene, counting the enemies' actions (enemy_acting).
# Untyped against anything that names the RunState autoload.

const CASES := 6
const MAX_HP := 80
const CARD_PATH := "res://cards/data/owed_time.tres"
const TEMPERED_PATH := "res://cards/tempered/owed_time_tempered.tres"
const STATUS_PATH := "res://battle/rules/statuses/owed_time.tres"
const COUNTERSIGN_PATH := "res://cards/data/countersign.tres"
const SMALL_PRICE_PATH := "res://cards/data/small_price.tres"
const LEVERAGE_STATUS_PATH := "res://battle/rules/statuses/leverage.tres"
const DYING_LIGHT_STATUS_PATH := "res://battle/rules/statuses/dying_light.tres"
const MARROW_STATUS_PATH := "res://battle/rules/statuses/marrow.tres"
const VENOM_STATUS_PATH := "res://battle/rules/statuses/venom.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const FILLER_PATH := "res://cards/data/slash.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _enemy_actions: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	_check_rules()
	await _check_extra_turn()
	await _check_countersign()
	await _check_turn_start()
	_check_sentence()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("owed_time_probe: PASSED")
		quit(0)
	else:
		print("owed_time_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	var status: StatusData = load(STATUS_PATH)
	_expect_eq([card.card_name, card.cost, card.card_type, card.rarity, card.removal_scope, card.card_class], ["Owed Time", 3, CardData.CardType.SKILL, CardData.CardRarity.RARE, CardData.RemovalScope.SPENT, &"wanderer"], "Owed Time: 3 Energy, a Rare Spent Skill")
	_expect_eq([card.target_type, card.offer], [CardData.TargetType.SELF, CardData.OfferScope.REWARDABLE], "...no target, rewardable")
	_expect(card.art != null and card.art.resource_path == "res://cards/art/Wanderer/Owed Time.png", "...with its art")
	_expect_eq(card.description, "Spend {toll_cost} Toll.\nTake another turn after this.\nSpent.", "...its text")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[0].toll_cost == 20, "...spends 20 Toll")
	_expect(card.effects.size() == 2 and card.effects[1].effect_type == CardEffect.EffectType.APPLY_STATUS and card.effects[1].status_data == status, "...then owes a turn")
	_expect_eq([status.display_name, status.grants_extra_turn, status.stack_rule, status.default_charges, status.ends_at_turn_end], ["Owed Time", true, StatusData.StackRule.ADD_CHARGES, 1, false], "The status: a charge per play, kept past the turn's end")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Owed Time+")
	_expect_eq([tempered.card_name, tempered.cost, tempered.rarity, tempered.removal_scope, tempered.description], ["Owed Time+", 3, CardData.CardRarity.RARE, CardData.RemovalScope.SPENT, card.description], "Owed Time+: the same card")
	_expect(tempered.effects.size() == 2 and tempered.effects[0].toll_cost == 16 and tempered.effects[1].status_data == status, "...for 16 Toll")
	for pool_path: String in [WANDERER_POOL_PATH, COLLECTOR_POOL_PATH]:
		_expect((load(pool_path) as RewardPool).entries.has(card), "In %s" % pool_path)
	_completed += 1

# --- Rules ---

# Unplayable on 19 Toll, playable on 20 (Owed Time+ on 16); played: the
# Toll gone and a charge owed; a second play owes two; each turn's end
# takes one.
func _check_rules() -> void:
	var card: CardData = load(CARD_PATH)
	var status: StatusData = load(STATUS_PATH)
	var player := Combatant.new(MAX_HP)
	player.toll = 19
	_expect(EffectResolver.card_blocked(card, player), "On 19 Toll: unplayable")
	player.toll = 20
	_expect(not EffectResolver.card_blocked(card, player), "On 20: playable")
	var plus := Combatant.new(MAX_HP)
	plus.toll = 16
	_expect(not EffectResolver.card_blocked(load(TEMPERED_PATH), plus), "Owed Time+ on 16: playable")
	plus.toll = 15
	_expect(EffectResolver.card_blocked(load(TEMPERED_PATH), plus), "...on 15: not")
	_play(card, player)
	_expect_eq(player.toll, 0, "Played: 20 Toll spent")
	var owed: Status = Status.find_in(player.statuses, status)
	_expect(owed != null and owed.charges == 1, "...one turn owed")
	player.toll = 20
	_play(card, player)
	owed = Status.find_in(player.statuses, status)
	_expect(owed != null and owed.charges == 2, "A second play: two owed")
	if owed != null:
		_expect_eq(owed.label(), "Owed Time ×2", "...read as \"Owed Time ×2\"")
	_expect(Status.take_extra_turn(player.statuses), "A turn's end takes one")
	_expect(Status.take_extra_turn(player.statuses), "...the next, the other")
	_expect(Status.find_in(player.statuses, status) == null, "...and the status is gone")
	_expect(not Status.take_extra_turn(player.statuses), "None owed: the enemies' turn")
	_completed += 1

# --- Fight ---

# The real fight: Owed Time played on 20 Toll with Leverage up and Small
# Price's 1 HP taken this turn. End Turn: the hand discarded, Leverage
# gone, no enemy acts and its intent stands, the player's HP untouched by
# them; a new turn - Energy refilled, five drawn, the turn counter on by
# one, "took damage last turn" the turn just ended's. Owed Time Spent, the
# status gone. End Turn again: the enemies act.
func _check_extra_turn() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Deck = controller.get("deck")
		player.energy = 9
		player.toll = 20
		var enemy: Node = (controller.get("enemies") as Array)[0]
		var intent_before: Variant = controller.call("get_intent_preview", enemy)
		var price: CardData = await _deal_card(controller, SMALL_PRICE_PATH)
		var card: CardData = await _deal_card(controller, CARD_PATH)
		await _play_real(controller, price)
		await _play_real(controller, card)
		_expect_eq(player.toll, 1, "Owed Time played: 20 Toll spent (1 left of Small Price's)")
		_expect(deck.exhaust_pile.has(card), "...Spent")
		Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
		var turn: int = int(controller.get("_player_turn"))
		var hp: int = player.hp
		await _end_turn(controller)
		_expect_eq(_enemy_actions, 0, "End Turn: no enemy acts")
		_expect_eq(controller.call("get_intent_preview", enemy), intent_before, "...the enemy's intent stands")
		_expect_eq(player.hp, hp, "...the player's HP untouched")
		_expect_eq(int(controller.get("_player_turn")), turn + 1, "...a new player turn")
		_expect_eq(player.energy, player.max_energy, "...Energy refilled (%d)" % player.energy)
		_expect_eq(deck.hand.size(), int(controller.get("turn_draw_amount")), "...a fresh hand drawn")
		_expect(Status.find_in(player.statuses, load(LEVERAGE_STATUS_PATH)) == null, "...Leverage gone with the turn")
		_expect(Status.find_in(player.statuses, load(STATUS_PATH)) == null, "...the owed turn spent")
		_expect(player.took_damage_last_turn, "...'took damage last turn' the turn just ended's (Small Price)")
		_expect(not deck.draw_pile.has(card) and not deck.hand.has(card) and not deck.discard_pile.has(card), "...Owed Time out of the rotation")
		await _end_turn(controller)
		_expect(_enemy_actions > 0, "End Turn again: the enemies act (%d)" % _enemy_actions)
	await _teardown()
	_completed += 1

# Twice Over copies Owed Time: two turns owed, the copy Spent too; two
# End Turns pass with no enemy acting, the third lets them act.
func _check_countersign() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Deck = controller.get("deck")
		var countersign_toll: int = (load(COUNTERSIGN_PATH) as CardData).effects[0].toll_cost
		player.energy = 9
		player.toll = 40 + countersign_toll
		var card: CardData = await _deal_card(controller, CARD_PATH)
		var countersign: CardData = await _deal_card(controller, COUNTERSIGN_PATH)
		controller.call("request_play", _view(controller, countersign))
		controller.call("toggle_choice", _view(controller, card))
		await ProbePlay.settle(self, controller)
		var copy: CardData = null
		for held: CardData in deck.hand:
			if held.battle_copy:
				copy = held
		_expect(copy != null and copy.card_name == "Owed Time", "Twice Over: an Owed Time copy in the hand")
		await _play_real(controller, card)
		if copy != null:
			await _play_real(controller, copy)
		var owed: Status = Status.find_in(player.statuses, load(STATUS_PATH))
		_expect(owed != null and owed.charges == 2, "Both played: two turns owed")
		_expect_eq(player.toll, 0, "...for 20 + 20 + Twice Over's %d Toll" % countersign_toll)
		_expect(deck.exhaust_pile.has(card) and copy != null and not deck.hand.has(copy) and not deck.discard_pile.has(copy), "...both Spent")
		var turn: int = int(controller.get("_player_turn"))
		await _end_turn(controller)
		await _end_turn(controller)
		_expect_eq(_enemy_actions, 0, "Two End Turns: no enemy acts")
		_expect_eq(int(controller.get("_player_turn")), turn + 2, "...two new player turns")
		await _end_turn(controller)
		_expect(_enemy_actions > 0, "The third: the enemies act")
	await _teardown()
	_completed += 1

# The extra turn starts in full: Critical at 20 of 80 with Dying Light up -
# 4 Energy; Marrow's Block; Venom's tick.
func _check_turn_start() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.energy = 9
		player.toll = 20
		player.hp = 20
		_run_state.set("player_hp", 20)
		Status.apply_to(player.statuses, load(DYING_LIGHT_STATUS_PATH))
		var marrow: StatusData = load(MARROW_STATUS_PATH)
		Status.apply_to(player.statuses, marrow)
		var marrow_block: int = Status.turn_start_block(player.statuses)
		var venom: StatusData = load(VENOM_STATUS_PATH)
		Status.apply_to(player.statuses, venom)
		var venom_tick: int = Status.find_in(player.statuses, venom).magnitude
		var card: CardData = await _deal_card(controller, CARD_PATH)
		await _play_real(controller, card)
		await _end_turn(controller)
		_expect_eq(_enemy_actions, 0, "End Turn: no enemy acts")
		_expect_eq(player.energy, player.max_energy + 1, "Dying Light, Critical at the extra turn's start: %d Energy" % player.energy)
		_expect(marrow_block > 0 and player.block >= marrow_block, "...Marrow's %d Block (%d)" % [marrow_block, player.block])
		_expect_eq(player.hp, 20 - venom_tick, "...Venom ticks %d" % venom_tick)
	await _teardown()
	_completed += 1

# The spend hurries every Sentence by a turn, as any Toll spend does.
func _check_sentence() -> void:
	var player := Combatant.new(MAX_HP)
	player.toll = 20
	var enemy := Combatant.new(500)
	var sentence: StatusData = load(SENTENCE_STATUS_PATH)
	Status.apply_to(enemy.statuses, sentence)
	var before: int = Status.find_in(enemy.statuses, sentence).turns_remaining
	var ctx: EffectContext = _ctx(player, enemy)
	_resolver.resolve_card(load(CARD_PATH), ctx)
	var after: Status = Status.find_in(enemy.statuses, sentence)
	_expect(after != null and after.turns_remaining == before - 1, "Owed Time's spend hurries a Sentence by a turn (%d to %s)" % [before, str(after.turns_remaining) if after != null else "gone"])
	_completed += 1

# --- Helpers ---

func _ctx(player: Combatant, enemy: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	var enemies: Array[Combatant] = [enemy if enemy != null else Combatant.new(500)]
	ctx.enemies = enemies
	var cards: Array[CardData] = []
	for i in 10:
		cards.append(load(FILLER_PATH))
	ctx.deck = Deck.new(cards)
	return ctx

func _play(card: CardData, player: Combatant) -> void:
	_resolver.resolve_card(card, _ctx(player, null))

# End Turn, and back to the player's turn.
func _end_turn(controller: Node) -> void:
	controller.call("end_turn")
	await process_frame
	await ProbePlay.wait_until(self, func() -> bool: return not bool(controller.get("_input_locked")), 30.0)
	# The new hand lands card after card.
	var deck: Deck = controller.get("deck")
	var draw: int = int(controller.get("turn_draw_amount"))
	await ProbePlay.wait_until(self, func() -> bool: return deck.hand.size() >= draw, 5.0)

func _start_fight() -> Node:
	_enemy_actions = 0
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
	# The fight's opening hold (BattleController.lock_entry_input()).
	var entry_layer: Node = _field.get_node("BattleLayer")
	while entry_layer.get_child_count() > 0 and bool((entry_layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
	var layer: Node = _field.get_node("BattleLayer")
	_overlay = layer.get_child(0) if layer.get_child_count() > 0 else null
	if _overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = _overlay.get("battle_controller")
	controller.connect("enemy_acting", func(_enemy: Node) -> void: _enemy_actions += 1)
	for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
		combatant.max_hp = 999
		combatant.hp = 999
	controller.get("deck").call("discard_hand")
	var deck: Deck = controller.get("deck")
	for i in 20:
		deck.draw_pile.append((load(FILLER_PATH) as CardData).duplicate())
	return controller

func _deal_card(controller: Node, path: String) -> CardData:
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

func _play_real(controller: Node, card: CardData) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	await ProbePlay.settle(self, controller)

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
