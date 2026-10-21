extends SceneTree

# Headless probe for Reckoning - 2 Energy, Uncommon Attack, Spent: deal
# damage equal to the Toll spent this fight (TOLL_SPENT_DAMAGE, reading
# Combatant.toll_spent_this_fight - every EffectContext.spend_toll() since
# the fight began, a replay's included). It spends none itself, so it
# hurries no Sentence. An Attack: the attack bonus lands on it (Self-Eater,
# Last Resort at Critical, Keen). Second Swing replays it for the tally as
# it stands then, its own 5 in it. Reckoning+ costs 1.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/reckoning_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants. The fight cases load the real region scene and play through
# BattleController: the face in hand reading the tally as Toll is spent,
# the blow, Spent; and a second fight starting its tally at 0. Untyped
# against anything that names the RunState autoload.

const CASES := 8
const CARD_PATH := "res://cards/data/reckoning.tres"
const TEMPERED_PATH := "res://cards/tempered/reckoning_tempered.tres"
const COME_DUE_PATH := "res://cards/data/come_due.tres"
const SETTLED_ACCOUNT_PATH := "res://cards/data/settled_account.tres"
const SECOND_SWING_PATH := "res://cards/data/second_swing.tres"
const SENTENCE_PATH := "res://cards/data/sentence.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const LAST_RESORT_PATH := "res://cards/data/last_resort.tres"
const KEEN_PATH := "res://battle/rules/statuses/keen.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const MAX_HP := 70
const ENEMY_HP := 999
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
	_check_tally()
	_check_replay()
	_check_sentence()
	_check_attack_bonus()
	await _check_face()
	await _check_fight()
	await _check_next_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("reckoning_probe: PASSED")
		quit(0)
	else:
		print("reckoning_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "Reckoning", "The card loads")
	_expect_eq(card.card_type, CardData.CardType.ATTACK, "...an Attack")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.offer, CardData.OfferScope.REWARDABLE, "...rewardable")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...Spent")
	_expect_eq(card.effects.size(), 1, "...one effect")
	if card.effects.size() == 1:
		_expect_eq(card.effects[0].effect_type, CardEffect.EffectType.TOLL_SPENT_DAMAGE, "...TOLL_SPENT_DAMAGE")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Reckoning+")
	_expect_eq([tempered.description, tempered.removal_scope, tempered.card_type], [card.description, card.removal_scope, card.card_type], "...otherwise the same card, Spent")
	_completed += 1

# --- Rules ---

# Come Due's 5 and Settled Account's 5 spent: Reckoning deals 10, and
# spends nothing - Toll held and the turn's spend flag as they were.
func _check_tally() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	_expect_eq(player.toll_spent_this_fight, 0, "A fresh player has spent nothing this fight")
	player.toll = 10
	_play(COME_DUE_PATH, player, enemy)
	_play(SETTLED_ACCOUNT_PATH, player, enemy)
	_expect_eq(player.toll_spent_this_fight, 10, "Come Due's 5 and Settled Account's 5: 10 spent")
	player.toll = 4
	player.toll_spent_this_turn = false
	var ctx: EffectContext = _play(CARD_PATH, player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 10, "Reckoning deals the 10")
	_expect_eq(player.toll, 4, "...spending none of the 4 held")
	_expect(not ctx.toll_spent_this_card and not player.toll_spent_this_turn, "...and marking no Toll spent")
	_expect_eq(player.toll_spent_this_fight, 10, "...the tally as it was")
	_play(CARD_PATH, player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 20, "A second Reckoning deals the same 10 again")
	_completed += 1

# Second Swing on Reckoning: its own 5 is spent first, so the replay deals
# the tally with it - 3 before, 8 now.
func _check_replay() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	player.toll_spent_this_fight = 3
	_play(CARD_PATH, player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 3, "Reckoning on 3 spent deals 3")
	player.record_attack(load(CARD_PATH), enemy, false)
	player.toll = 5
	var before: int = enemy.hp
	_play(SECOND_SWING_PATH, player, enemy)
	_expect_eq(player.toll_spent_this_fight, 8, "Second Swing's 5 spent: 8 in all")
	_expect_eq(before - enemy.hp, 8, "...and its replay of Reckoning deals the 8")
	_completed += 1

# A Sentence on the enemy: Reckoning takes nothing off it.
func _check_sentence() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	_play(SENTENCE_PATH, player, enemy)
	var label: String = _label_of(enemy, "sentence")
	player.toll = 9
	player.toll_spent_this_fight = 6
	_play(CARD_PATH, player, enemy)
	_expect_eq(_label_of(enemy, "sentence"), label, "Reckoning leaves the Sentence as it was (%s)" % label)
	_completed += 1

# The attack bonus lands once on the tally: Self-Eater's stance bonus,
# Last Resort's at Critical, Keen's charge.
func _check_attack_bonus() -> void:
	var player: Combatant = _player()
	_play(SELF_EATER_PATH, player, null)
	var bonus: int = Stance.attack_bonus(player.stance, false)
	_expect(bonus > 0, "Self-Eater gives an attack bonus (%d)" % bonus)
	player.toll_spent_this_fight = 5
	var enemy := Combatant.new(ENEMY_HP)
	_play(CARD_PATH, player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 5 + bonus, "Under Self-Eater: 5 + %d" % bonus)

	player = _player()
	player.hp = 20
	_play(LAST_RESORT_PATH, player, Combatant.new(ENEMY_HP))
	var critical_bonus: int = AttackBonus.for_player(player, player.hp)
	_expect(critical_bonus > 0, "Last Resort at Critical gives an attack bonus (%d)" % critical_bonus)
	player.toll_spent_this_fight = 4
	enemy = Combatant.new(ENEMY_HP)
	_play(CARD_PATH, player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 4 + critical_bonus, "Under Last Resort at Critical: 4 + %d" % critical_bonus)

	player = _player()
	var keen: StatusData = load(KEEN_PATH)
	Status.apply_to(player.statuses, keen)
	player.toll_spent_this_fight = 6
	enemy = Combatant.new(ENEMY_HP)
	_play(CARD_PATH, player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 6 + keen.attack_damage_bonus, "With Keen: 6 + %d" % keen.attack_damage_bonus)
	_completed += 1

# --- Face and fight ---

# Outside a fight: the rule. In a battle hand: the tally plus the attack
# bonus, read again as it moves.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Deal damage equal to the Toll you've spent this fight.\nSpent.", "The face outside a fight says its rule")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	var player: Combatant = _player()
	var ctx := EffectContext.new()
	ctx.player = player
	view.set_bonus_context(ctx)
	_expect_eq(view.rules_text.get_parsed_text(), "Deal 0 damage.\nSpent.", "In a battle hand with nothing spent: 0")
	player.toll_spent_this_fight = 23
	view.set_bonus_context(ctx)
	_expect_eq(view.rules_text.get_parsed_text(), "Deal 23 damage.\nSpent.", "...23 spent: 23")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	view.free()
	_completed += 1

# The real fight: Reckoning in hand reads 0; Come Due spends 5 and the
# face reads 5; played, it deals 5, spends nothing and is Spent.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.energy = 99
		var reckoning: CardData = await _deal(controller, CARD_PATH)
		_expect_eq(_face(controller, reckoning), "Deal 0 damage.\nSpent.", "In hand at the fight's start: 0")
		player.toll = 5
		controller.emit_signal("toll_changed", 5)
		await _play_real(controller, await _deal(controller, COME_DUE_PATH), null)
		_expect_eq(player.toll_spent_this_fight, 5, "Come Due spends 5: the tally 5")
		_expect_eq(_face(controller, reckoning), "Deal 5 damage.\nSpent.", "...and the face in hand reads 5")
		var enemy: Combatant = _enemy(controller)
		var before: int = enemy.hp + enemy.block
		var toll: int = player.toll
		await _play_real(controller, reckoning, _field_enemy(controller))
		_expect_eq(before - (enemy.hp + enemy.block), 5, "Played: 5 dealt")
		_expect_eq(player.toll, toll, "...no Toll spent")
		_expect((controller.get("deck").get("exhaust_pile") as Array).has(reckoning), "...and Spent")
	await _teardown()
	_completed += 1

# A new fight: the tally starts again at 0.
func _check_next_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect_eq(player.toll_spent_this_fight, 0, "The next fight's tally starts at 0")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = 50
	return player

func _play(path: String, player: Combatant, enemy: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	var enemies: Array[Combatant] = [enemy if enemy != null else Combatant.new(ENEMY_HP)]
	ctx.enemies = enemies
	_resolver.resolve_card(load(path), ctx)
	return ctx

func _label_of(combatant: Combatant, id: String) -> String:
	for active in combatant.statuses:
		if active.data != null and active.data.id == id:
			return active.label()
	return ""

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
	# Unkillable: the blows are read off its HP.
	for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
		combatant.max_hp = ENEMY_HP
		combatant.hp = ENEMY_HP
	return controller

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _enemy(controller: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).values()[0]

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

func _face(controller: Node, card: CardData) -> String:
	var view: CardView = _view(controller, card)
	return view.rules_text.get_parsed_text() if view != null else "no view"

# A real play; `target` for an enemy-targeted card, null otherwise.
func _play_real(controller: Node, card: CardData, target: Node) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if target != null:
		if not bool(controller.call("is_awaiting_target")):
			_fail("'%s' didn't ask for a target" % card.card_name)
			return
		controller.call("confirm_target", target)
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
