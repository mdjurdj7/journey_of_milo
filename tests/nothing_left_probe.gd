extends SceneTree

# Headless probe for Nothing Left - Rare Attack: deal 28, costing 3 Energy,
# or 0 whenever the player is Critical (CardData.critical_cost, read
# through Combatant.base_cost(), as Cornered+ does). Nothing Left+ deals
# 36. At 0 a "next card" discount (Leverage) passes it by; above the line
# Leverage makes it 1. Under Collateral, above the line it costs 3 HP per
# Energy short; Critical, nothing. A Countersign copy keeps its Critical
# cost. On the Brink at 31-50% makes it free for the turn.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/nothing_left_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases read the real cards on bare Combatants (80 max HP: the line
# at 24). The fight case reads the hand's live cost through BattleController
# on the real region scene: 3, then 0 under On the Brink at 40, then 3
# again at End Turn. Untyped against anything that names the RunState
# autoload.

const CASES := 6
const MAX_HP := 80
const BASE_FRACTION := 0.3
const CARD_PATH := "res://cards/data/nothing_left.tres"
const TEMPERED_PATH := "res://cards/tempered/nothing_left_tempered.tres"
const LEVERAGE_STATUS_PATH := "res://battle/rules/statuses/leverage.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const ON_THE_BRINK_PATH := "res://cards/data/on_the_brink.tres"
const TEETH_PATH := "res://battle/rules/statuses/teeth.tres"
const FILLER_PATH := "res://cards/data/slash.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 240.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	_check_cost_and_damage()
	_check_leverage()
	_check_collateral()
	_check_copy()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("nothing_left_probe: PASSED")
		quit(0)
	else:
		print("nothing_left_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq([card.card_name, card.cost, card.critical_cost, card.card_type, card.rarity, card.card_class], ["Nothing Left", 3, 0, CardData.CardType.ATTACK, CardData.CardRarity.RARE, &"wanderer"], "Nothing Left: 3 Energy, 0 while Critical, a Rare Attack")
	_expect_eq([card.target_type, card.offer, card.removal_scope], [CardData.TargetType.ENEMY, CardData.OfferScope.REWARDABLE, CardData.RemovalScope.NONE], "...at an enemy, rewardable, to the discard")
	_expect(card.art == null, "...no art yet")
	_expect_eq(card.description, "Deal {damage} damage.\nCritical: costs 0.", "...its text")
	_expect(card.effects.size() == 1 and card.effects[0].effect_type == CardEffect.EffectType.DAMAGE and card.effects[0].value == 28 and card.effects[0].condition == CardEffect.Condition.NONE, "...one blow of 28")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Nothing Left+")
	_expect_eq([tempered.card_name, tempered.cost, tempered.critical_cost, tempered.rarity, tempered.description], ["Nothing Left+", 3, 0, CardData.CardRarity.RARE, card.description], "Nothing Left+: the same costs and text")
	_expect(tempered.effects.size() == 1 and tempered.effects[0].value == 36, "...a blow of 36")
	for pool_path: String in [WANDERER_POOL_PATH, COLLECTOR_POOL_PATH]:
		_expect((load(pool_path) as RewardPool).entries.has(card), "In %s" % pool_path)
	_completed += 1

# --- Rules ---

# 3 above the line, 0 at or under it - Go Under's or On the Brink's line
# too; 28 either way, bonuses on top.
func _check_cost_and_damage() -> void:
	var card: CardData = load(CARD_PATH)
	var player: Combatant = _player(50)
	_expect_eq(player.energy_cost(card), 3, "At 50: costs 3")
	player.hp = 24
	_expect_eq(player.energy_cost(card), 0, "At 24, Critical: costs 0")
	player = _player(40)
	_play(load(ON_THE_BRINK_PATH), player)
	_expect_eq(player.energy_cost(card), 0, "At 40 under On the Brink: 0")
	Status.remove_at_turn_end(player.statuses)
	_expect_eq(player.energy_cost(card), 3, "...its turn over: 3 again")
	_expect_eq(_deal(card, _player(50)), 28, "Deals 28 above the line")
	_expect_eq(_deal(card, _player(20)), 28, "...and 28 Critical")
	_expect_eq(_deal(load(TEMPERED_PATH), _player(20)), 36, "Nothing Left+: 36")
	var teeth: Combatant = _player(50)
	Status.apply_to(teeth.statuses, load(TEETH_PATH))
	var bonus: int = AttackBonus.when_critical(teeth, false)
	_expect_eq(_deal(card, teeth), 28 + bonus, "Teeth on top: 28 + %d" % bonus)
	_completed += 1

# Leverage (2 off the next card costing at least 1): above the line it
# lands - 1 - and is spent; Critical, the card costs 0 and passes it by.
func _check_leverage() -> void:
	var card: CardData = load(CARD_PATH)
	var player: Combatant = _player(50)
	Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
	_expect(player.takes_next_card_discount(card), "Leverage at 50: lands on Nothing Left")
	_expect_eq(player.energy_cost(card), 1, "...3 - 2 = 1")
	player.hp = 20
	_expect(not player.takes_next_card_discount(card), "Critical: it costs 0 and Leverage waits")
	_expect_eq(player.energy_cost(card), 0, "...at 0")
	_completed += 1

# Collateral (3 HP per Energy short): on 0 Energy above the line, 9 HP;
# Critical, it costs nothing to cover.
func _check_collateral() -> void:
	var card: CardData = load(CARD_PATH)
	var player: Combatant = _player(50)
	player.energy = 0
	Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
	_expect_eq(player.replaced_cost_hp(card), 9, "Collateral on 0 Energy at 50: 9 HP")
	_expect(player.can_pay(card), "...and playable")
	player.hp = 20
	_expect_eq(player.replaced_cost_hp(card), 0, "Critical: no HP")
	_expect(player.can_pay(card), "...and free")
	_completed += 1

# A Countersign copy is the same card, Critical cost and all, and a fight-
# only one: gone once played.
func _check_copy() -> void:
	var cards: Array[CardData] = [load(CARD_PATH) as CardData]
	var deck := Deck.new(cards)
	deck.draw(1)
	var copy: CardData = deck.add_copy(deck.hand[0])
	_expect(copy != null and copy.battle_copy, "Countersign's copy: a fight-only card")
	if copy != null:
		_expect_eq([copy.cost, copy.critical_cost], [3, 0], "...3 Energy, 0 while Critical")
		var player: Combatant = _player(20)
		_expect_eq(player.energy_cost(copy), 0, "...free at 20")
		deck.discard(copy)
		_expect(not deck.discard_pile.has(copy) and not deck.hand.has(copy), "...and gone when it leaves the hand")
	_completed += 1

# --- Fight ---

# The hand's live cost: 3 at 40 of 80; On the Brink played - 0; End Turn,
# before any enemy acts - 3.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.energy = 3
		player.hp = 40
		_run_state.set("player_hp", 40)
		controller.emit_signal("hp_changed", 40, player.max_hp)
		for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
			combatant.max_hp = 999
			combatant.hp = 999
		var deck: Deck = controller.get("deck")
		for i in 5:
			deck.draw_pile.append((load(FILLER_PATH) as CardData).duplicate())
		var card: CardData = await _deal_card(controller, CARD_PATH)
		var brink: CardData = await _deal_card(controller, ON_THE_BRINK_PATH)
		var view: CardView = _view(controller, card)
		await process_frame
		_expect(view != null and view.cost_label.text == "3", "At 40: the face reads 3 (%s)" % (view.cost_label.text if view != null else "no view"))
		await _play_real(controller, brink)
		_expect(view != null and view.cost_label.text == "0", "On the Brink played: the face reads 0 (%s)" % (view.cost_label.text if view != null else "no view"))
		_expect(bool(controller.call("_is_playable", card)), "...and it's playable")
		controller.call("end_turn")
		_expect_eq(player.energy_cost(card), 3, "End Turn: 3 again before any enemy acts")
		await ProbePlay.wait_until(self, func() -> bool: return not bool(controller.get("_input_locked")), 30.0)
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.energy = 3
	player.critical_hp_fraction = BASE_FRACTION
	return player

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

# Plays `card` into a fresh 500 HP enemy; returns the damage it took.
func _deal(card: CardData, player: Combatant) -> int:
	var enemy := Combatant.new(500)
	_resolver.resolve_card(card, _ctx(player, enemy))
	return 500 - enemy.hp

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
	controller.get("deck").call("discard_hand")
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
