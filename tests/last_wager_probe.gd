extends SceneTree

# Headless probe for Last Wager - 2 Energy, Uncommon Attack: lose 8 HP,
# then deal 12, or 32 if that loss took the player into Critical (above
# the line in force before every HP the card costs - Collateral's, the
# stance's, its own 8 - at or under it after: Condition.ENTERED_CRITICAL).
# Already Critical: 12. The 8 is self-inflicted (Toll), and at 8 HP or
# less it kills like any self-damage card: the blow still lands, then the
# fight is lost. Last Wager+ deals 16 or 40.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/last_wager_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants (80 max HP: the line at 24). The fight case plays it through
# BattleController on the real region scene: the face's -8 HP badge and
# its live clause, and a lethal play losing the fight. Untyped against
# anything that names the RunState autoload.

const CASES := 7
const MAX_HP := 80
const BASE_FRACTION := 0.3
const CARD_PATH := "res://cards/data/last_wager.tres"
const TEMPERED_PATH := "res://cards/tempered/last_wager_tempered.tres"
const ART_PATH := "res://cards/art/Wanderer/Last Wager.png"
const GO_UNDER_PATH := "res://cards/data/go_under.tres"
const ON_THE_BRINK_PATH := "res://cards/data/on_the_brink.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const LAST_RESORT_PATH := "res://cards/data/last_resort.tres"
const SECOND_SWING_PATH := "res://cards/data/second_swing.tres"
const TEETH_PATH := "res://battle/rules/statuses/teeth.tres"
const FILLER_PATH := "res://cards/data/slash.tres"
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
	_check_base_line()
	_check_raised_lines()
	_check_already_critical()
	_check_bonuses()
	_check_replay()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("last_wager_probe: PASSED")
		quit(0)
	else:
		print("last_wager_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq([card.card_name, card.cost, card.card_type, card.rarity, card.card_class], ["Last Wager", 2, CardData.CardType.ATTACK, CardData.CardRarity.UNCOMMON, &"wanderer"], "Last Wager: 2 Energy, an Uncommon Attack")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...at an enemy")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...keeping its art")
	_expect_eq(card.description, "{else}Deal {damage} damage.{/else} {if}If this makes you Critical, deal {alt_damage}.{/if}", "...its text")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SELF_DAMAGE and card.effects[0].value == 8, "...first it loses 8 HP")
	_expect(card.effects.size() == 2 and card.effects[1].effect_type == CardEffect.EffectType.DAMAGE and card.effects[1].condition == CardEffect.Condition.ENTERED_CRITICAL and [card.effects[1].value, card.effects[1].alt_value] == [12, 32], "...then deals 12, or 32 into Critical")
	_expect_eq(CardBonus.upfront_hp_cost(card, null, 0), 8, "...its 8 the badge's, paid up front")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Last Wager+")
	_expect_eq([tempered.card_name, tempered.cost, tempered.rarity, tempered.description], ["Last Wager+", 2, CardData.CardRarity.UNCOMMON, card.description], "Last Wager+: 2 Energy, the same text")
	_expect(tempered.effects.size() == 2 and tempered.effects[0].value == 8 and [tempered.effects[1].value, tempered.effects[1].alt_value] == [16, 40], "...8 HP, then 16 or 40")
	_completed += 1

# --- Rules ---

# The line at 30% (24 of 80): 30 to 22 crosses it - 32; 33 to 25 doesn't
# - 12. The loss makes 8 Toll either way.
func _check_base_line() -> void:
	var player: Combatant = _player(30)
	_expect_eq(_deal(load(CARD_PATH), player), 32, "At 30 (22 after): into Critical, 32")
	_expect_eq([player.hp, player.toll], [22, 8], "...8 HP lost, 8 Toll made")
	player = _player(33)
	_expect_eq(_deal(load(CARD_PATH), player), 12, "At 33 (25 after): above the line, 12")
	player = _player(32)
	_expect_eq(_deal(load(CARD_PATH), player), 32, "At 32 (24 after, on the line): 32")
	_expect_eq(_deal(load(TEMPERED_PATH), _player(30)), 40, "Last Wager+ at 30: 40")
	_expect_eq(_deal(load(TEMPERED_PATH), _player(33)), 16, "...at 33: 16")
	_completed += 1

# The line in force when it's played: Go Under's 50% (40 of 80) - 45 to
# 37 crosses, 49 to 41 doesn't; On the Brink's 50% the same, and once its
# turn has ended the line is 24 again.
func _check_raised_lines() -> void:
	var player: Combatant = _player(45)
	_play(load(GO_UNDER_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 32, "Under Go Under at 45 (37 after): 32")
	player = _player(49)
	_play(load(GO_UNDER_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 12, "...at 49 (41 after): 12")
	player = _player(45)
	_play(load(ON_THE_BRINK_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 32, "Under On the Brink at 45: 32")
	player = _player(45)
	_play(load(ON_THE_BRINK_PATH), player)
	Status.remove_at_turn_end(player.statuses)
	_expect_eq(_deal(load(CARD_PATH), player), 12, "...after its turn has ended (line at 24): 12")
	_completed += 1

# Critical before it's played: 12, whatever the 8 does.
func _check_already_critical() -> void:
	var player: Combatant = _player(20)
	_expect_eq(_deal(load(CARD_PATH), player), 12, "Already Critical at 20: 12")
	_expect_eq(player.hp, 12, "...and 8 HP lost")
	_completed += 1

# Bonuses land on whichever amount is dealt: Teeth on 12 and on 32;
# Self-Eater's 2 counts toward the crossing (34 - 2 - 8 = 24) and adds its
# 3; Last Resort's 6 needs Critical after the 8.
func _check_bonuses() -> void:
	var teeth: StatusData = load(TEETH_PATH)
	var player: Combatant = _player(33)
	Status.apply_to(player.statuses, teeth)
	var bonus: int = AttackBonus.when_critical(player, false)
	_expect(bonus > 0, "Teeth gives a bonus (%d)" % bonus)
	_expect_eq(_deal(load(CARD_PATH), player), 12 + bonus, "Teeth at 33: 12 + %d" % bonus)
	player = _player(30)
	Status.apply_to(player.statuses, teeth)
	_expect_eq(_deal(load(CARD_PATH), player), 32 + bonus, "...at 30: 32 + %d" % bonus)
	player = _player(34)
	_play(load(SELF_EATER_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 35, "Self-Eater at 34: its 2 and the 8 take it to 24 - 32 + 3")
	_expect_eq(player.toll, 10, "...10 Toll made")
	player = _player(36)
	_play(load(SELF_EATER_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 15, "...at 36 (26 after): 12 + 3")
	player = _player(30)
	_play(load(LAST_RESORT_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 38, "Last Resort at 30: into Critical, 32 + 6")
	player = _player(40)
	_play(load(LAST_RESORT_PATH), player)
	_expect_eq(_deal(load(CARD_PATH), player), 12, "...at 40 (32 after): 12, no Critical bonus")
	_completed += 1

# Second Swing replays it in full: 8 HP more, the crossing judged afresh
# from where the replay starts. 50 to 42, then 42 to 34: 12 and 12; 40 to
# 32, then 32 to 24: 12, then 32.
func _check_replay() -> void:
	for pair: Array in [[50, [12, 12]], [40, [12, 32]]]:
		var player: Combatant = _player(pair[0])
		player.toll = 10
		var enemy := Combatant.new(500)
		var ctx: EffectContext = _ctx(player, enemy)
		_resolver.resolve_card(load(CARD_PATH), ctx)
		var first: int = 500 - enemy.hp
		player.record_attack(load(CARD_PATH), enemy, false)
		var replay: EffectContext = _ctx(player, enemy)
		_resolver.resolve_card(load(SECOND_SWING_PATH), replay)
		var second: int = 500 - enemy.hp - first
		_expect_eq([first, second], pair[1], "At %d: Last Wager %d, Second Swing's replay %d" % [pair[0], first, second])
		_expect_eq(player.hp, int(pair[0]) - 16, "...16 HP lost in all")
	_completed += 1

# --- Fight ---

# The real fight: the face's -8 HP badge and 15 px text; its clause live at
# 30 of 80 (22 after), grey at 40 and at 20. Then with 20 max HP (the line
# at 6) and 8 HP: the 8 kills - the blow still lands, 32 into Critical -
# and the fight is lost.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.energy = 9
		for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
			combatant.max_hp = 999
			combatant.hp = 999
		var wager: CardData = await _deal_card(controller, CARD_PATH)
		var view: CardView = _view(controller, wager)
		_set_hp(controller, player, 30)
		_expect(view != null and view.hp_cost_label.visible and view.hp_cost_label.text == "−8 HP", "The face's badge reads −8 HP (%s)" % (view.hp_cost_label.text if view != null else "no view"))
		_expect(view != null and view.rules_text.get_theme_font_size("normal_font_size") == 15, "...its text at 15 px")
		_expect(view != null and view.get("_bonus_state") == CardBonus.State.LIVE, "At 30: its clause live")
		_set_hp(controller, player, 40)
		_expect(view != null and view.get("_bonus_state") == CardBonus.State.DORMANT, "At 40: grey")
		_set_hp(controller, player, 20)
		_expect(view != null and view.get("_bonus_state") == CardBonus.State.DORMANT, "At 20, already Critical: grey")
		var lost: Array[bool] = [false]
		controller.connect("battle_lost", func() -> void: lost[0] = true)
		player.max_hp = 20
		_set_hp(controller, player, 8)
		var target: Combatant = null
		for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
			target = combatant
		var before: int = target.hp if target != null else 0
		# Not settled: the lost fight takes the controller down with it.
		_request_at_enemy(controller, wager)
		var landed: bool = await ProbePlay.wait_until(self, func() -> bool: return lost[0], 10.0)
		_expect_eq(player.hp, 0, "At 8 of 20, its 8 kills")
		_expect(target != null and before - target.hp == 32, "...the blow still lands: 32 into Critical (%d)" % (before - target.hp if target != null else -1))
		_expect(landed, "...and the fight is lost")
	await _teardown()
	_completed += 1

func _set_hp(controller: Node, player: Combatant, hp: int) -> void:
	player.hp = hp
	_run_state.set("player_hp", hp)
	controller.emit_signal("hp_changed", hp, player.max_hp)
	controller.emit_signal("status_changed")

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
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

# Plays `card` at the first enemy.
func _request_at_enemy(controller: Node, card: CardData) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if bool(controller.call("is_awaiting_target")):
		for enemy in controller.get("enemies"):
			controller.call("confirm_target", enemy)
			break

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
