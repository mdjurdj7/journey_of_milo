extends SceneTree

# Headless probe for the Samurai's skillchains (Skillchain): the chain a
# card's property (CardData.chain_property) steps, and what each link
# fires after the card's own effects. Test cards made here, not her
# .tres; the numbers the links pay are her CharacterData's.
#
#   steps   - Advance -> Hold -> Withdraw -> Advance raises the level 0,
#             1, 2, 3 and fires Parry, Recover, Lunge, and round again
#   breaks  - a card with no property ends the chain; one with the wrong
#             property starts a new one at level 0, which then extends;
#             either break clears the last skillchain
#   parry   - Block per level, after the card's own Block
#   recover - a draw, after the card's own
#   lunge   - damage per level to the card's target alone, after its own
#             blow
#   fizzle  - a Lunge whose target the card's own blow killed lands
#             nothing
#   burst   - a Burst card reads the level from before it was played, and
#             its own lack of property ends the chain
#   face    - that card's face in a battle hand prints its damage at the
#             chain level now (5, 9, 13 at levels 0, 1, 2); outside a
#             fight its rule prints the per-level number ({chain_bonus})
#   turn    - in a fight: a play's commit steps the chain and fires its
#             link, and the hand's context carries the new level; the
#             chain is gone once the turn ends, before the enemies act,
#             and at the next turn's start
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/skillchain_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 9
const SAMURAI_PATH := "res://run/data/samurai.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
# The test Burst card's rules: the live number in a fight, the rule outside.
const BURST_TEXT := "{battle}Deal {damage} damage.{/battle}{outside}Deal {damage} damage, plus {chain_bonus} per chain level.{/outside}"
const PLAYER_HP := 999
const ENEMY_HP := 100
const CARD_DAMAGE := 6
const CARD_BLOCK := 5
const CARD_DRAW := 1
const BURST_DAMAGE := 5
const BURST_PER_LEVEL := 4
const SAFETY_SECONDS := 120.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _samurai: CharacterData = null

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node_or_null("RunState")
	_samurai = load(SAMURAI_PATH) as CharacterData
	_check_steps()
	_check_breaks()
	_check_parry()
	_check_recover()
	_check_lunge()
	_check_fizzle()
	_check_burst()
	await _check_face()
	await _check_turn()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("skillchain_probe: PASSED")
		quit(0)
	else:
		print("skillchain_probe: %d FAILED" % _failures)
		quit(1)

func _check_steps() -> void:
	var player: Combatant = _player()
	var order: Array[CardData.ChainProperty] = [CardData.ChainProperty.ADVANCE, CardData.ChainProperty.HOLD,
		CardData.ChainProperty.WITHDRAW, CardData.ChainProperty.ADVANCE, CardData.ChainProperty.HOLD]
	var links: Array[StringName] = [&"", Skillchain.PARRY, Skillchain.RECOVER, Skillchain.LUNGE, Skillchain.PARRY]
	for i in order.size():
		var link: StringName = Skillchain.step(player, _skill(order[i]))
		_expect_eq(player.chain_level, i, "Play %d of the loop: level %d" % [i + 1, i])
		_expect_eq(link, links[i], "...firing %s" % (links[i] if links[i] != &"" else "nothing"))
	_expect_eq(player.last_skillchain, Skillchain.PARRY, "The last skillchain fired is kept")
	_completed += 1

func _check_breaks() -> void:
	var player: Combatant = _player()
	Skillchain.step(player, _skill(CardData.ChainProperty.ADVANCE))
	Skillchain.step(player, _skill(CardData.ChainProperty.HOLD))
	var link: StringName = Skillchain.step(player, _skill(CardData.ChainProperty.NONE))
	_expect_eq(link, &"", "A card with no property fires nothing")
	_expect_eq(player.chain_level, 0, "...and ends the chain")
	_expect_eq(player.chain_property, CardData.ChainProperty.NONE, "...leaving none to follow")
	_expect_eq(player.last_skillchain, &"", "...and clears the broken chain's skillchain")
	_expect_eq(Skillchain.step(player, _skill(CardData.ChainProperty.HOLD)), &"", "After it, a Hold starts a chain: nothing fired")

	Skillchain.reset(player)
	Skillchain.step(player, _skill(CardData.ChainProperty.ADVANCE))
	Skillchain.step(player, _skill(CardData.ChainProperty.HOLD))
	link = Skillchain.step(player, _skill(CardData.ChainProperty.ADVANCE))
	_expect_eq(link, &"", "The wrong property (Advance after Hold) fires nothing")
	_expect_eq(player.chain_level, 0, "...and starts a new chain at level 0")
	_expect_eq(player.chain_property, CardData.ChainProperty.ADVANCE, "...from that card")
	_expect_eq(player.last_skillchain, &"", "...clearing the broken chain's skillchain")
	link = Skillchain.step(player, _skill(CardData.ChainProperty.HOLD))
	_expect_eq(link, Skillchain.PARRY, "The new chain extends: Hold fires Parry")
	_expect_eq(player.chain_level, 1, "...at level 1")

	Skillchain.reset(player)
	_expect_eq(player.chain_level, 0, "A reset: level 0")
	_expect_eq(player.chain_property, CardData.ChainProperty.NONE, "...no chain")
	_expect_eq(player.last_skillchain, &"", "...and no skillchain")
	_completed += 1

# Level 1 at an Advance; a Hold Block card takes it to 2.
func _check_parry() -> void:
	var player: Combatant = _player()
	_chain_at(player, CardData.ChainProperty.ADVANCE, 1)
	var gained: Array[int] = []
	var ctx: EffectContext = _ctx(player, [Combatant.new(ENEMY_HP)])
	ctx.on_block_gained = func(amount: int) -> void: gained.append(amount)
	_commit(player, _block_card(CardData.ChainProperty.HOLD), ctx)
	var parry: int = _samurai.parry_block_per_level * 2
	_expect_eq(gained, [CARD_BLOCK, parry] as Array[int], "Parry at level 2: the card's %d, then %d" % [CARD_BLOCK, parry])
	_expect_eq(player.block, CARD_BLOCK + parry, "...both held")
	_completed += 1

func _check_recover() -> void:
	var player: Combatant = _player()
	_chain_at(player, CardData.ChainProperty.HOLD, 0)
	var pile: Array[CardData] = []
	for i in 6:
		pile.append(_skill(CardData.ChainProperty.NONE))
	var ctx: EffectContext = _ctx(player, [Combatant.new(ENEMY_HP)])
	ctx.deck = Deck.new(pile)
	var card := _skill(CardData.ChainProperty.WITHDRAW)
	card.effects = [_effect(CardEffect.EffectType.DRAW, CARD_DRAW)] as Array[CardEffect]
	var link: StringName = _commit(player, card, ctx)
	_expect_eq(link, Skillchain.RECOVER, "Hold -> Withdraw fires Recover")
	_expect_eq(ctx.deck.hand.size(), CARD_DRAW + _samurai.recover_draw, "...its draw on top of the card's")
	_completed += 1

# Level 2 at a Withdraw; an Advance Attack takes it to 3.
func _check_lunge() -> void:
	var player: Combatant = _player()
	_chain_at(player, CardData.ChainProperty.WITHDRAW, 2)
	var enemy := Combatant.new(ENEMY_HP)
	var other := Combatant.new(ENEMY_HP)
	var hits: Array[int] = []
	var ctx: EffectContext = _ctx(player, [enemy, other])
	ctx.on_damage = func(target: Combatant, amount: int, _kind: String) -> void:
		_expect(target == enemy, "Every hit lands on the card's target")
		hits.append(amount)
	_commit(player, _attack(CardData.ChainProperty.ADVANCE), ctx)
	var lunge: int = _samurai.lunge_damage_per_level * 3
	_expect_eq(hits, [CARD_DAMAGE, lunge] as Array[int], "Lunge at level 3: the card's %d, then %d" % [CARD_DAMAGE, lunge])
	_expect_eq(enemy.hp, ENEMY_HP - CARD_DAMAGE - lunge, "...both off its HP")
	_expect_eq(other.hp, ENEMY_HP, "...none off the other enemy")
	_completed += 1

func _check_fizzle() -> void:
	var player: Combatant = _player()
	_chain_at(player, CardData.ChainProperty.WITHDRAW, 2)
	var enemy := Combatant.new(CARD_DAMAGE)
	var hits: Array[int] = []
	var ctx: EffectContext = _ctx(player, [enemy])
	ctx.on_damage = func(_target: Combatant, amount: int, _kind: String) -> void: hits.append(amount)
	var link: StringName = _commit(player, _attack(CardData.ChainProperty.ADVANCE), ctx)
	_expect_eq(link, Skillchain.LUNGE, "The link still fires Lunge")
	_expect_eq(hits, [CARD_DAMAGE] as Array[int], "...but with its target killed by the card it lands nothing")
	_expect_eq(enemy.hp, 0, "...and the dead stay at 0")
	_completed += 1

func _check_burst() -> void:
	var player: Combatant = _player()
	_chain_at(player, CardData.ChainProperty.HOLD, 2)
	var card: CardData = _burst_card()
	var enemy := Combatant.new(ENEMY_HP)
	var hits: Array[int] = []
	var ctx: EffectContext = _ctx(player, [enemy])
	ctx.on_damage = func(_target: Combatant, amount: int, _kind: String) -> void: hits.append(amount)
	var link: StringName = _commit(player, card, ctx)
	var expected: int = BURST_DAMAGE + BURST_PER_LEVEL * 2
	_expect_eq(hits, [expected] as Array[int], "A Burst card at level 2 deals %d + %d x 2" % [BURST_DAMAGE, BURST_PER_LEVEL])
	_expect_eq(link, &"", "...fires no link")
	_expect_eq(player.chain_level, 0, "...and, with no property, ends the chain")
	_completed += 1

func _check_face() -> void:
	var outside: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(outside)
	await process_frame
	outside.set_card_data(_burst_card())
	var rule: String = "Deal %d damage, plus %d per chain level." % [BURST_DAMAGE, BURST_PER_LEVEL]
	_expect_eq(outside.rules_text.get_parsed_text(), rule, "Outside a fight the face says the rule")
	outside.free()
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	for level in [0, 1, 2]:
		var hand: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(hand)
		await process_frame
		var ctx: EffectContext = _ctx(player, [enemy])
		ctx.chain_level_before_this = level
		hand.set_bonus_context(ctx)
		hand.set_card_data(_burst_card())
		var live: String = "Deal %d damage." % (BURST_DAMAGE + BURST_PER_LEVEL * level)
		_expect_eq(hand.rules_text.get_parsed_text(), live, "In a battle hand at chain level %d" % level)
		hand.free()
	_completed += 1

# A fight as her on floor 1 with a hand of test cards: an Advance and four
# Holds, all free Skills with a little Block.
func _check_turn() -> void:
	_run_state.call("new_run", _samurai)
	var deck: Array[CardData] = [_block_card(CardData.ChainProperty.ADVANCE)]
	for i in 4:
		deck.append(_block_card(CardData.ChainProperty.HOLD))
	_run_state.set("deck", deck)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	var controller: Node = await _start_fight()
	if controller == null:
		await _teardown()
		return
	var player: Combatant = controller.get("player")
	_expect_eq(player.parry_block_per_level, _samurai.parry_block_per_level, "The fight copies her Parry number")
	await _play_property(controller, CardData.ChainProperty.ADVANCE)
	var block_before: int = player.block
	await _play_property(controller, CardData.ChainProperty.HOLD)
	_expect_eq(player.chain_level, 1, "A play's commit steps the chain: level 1")
	_expect_eq(player.last_skillchain, Skillchain.PARRY, "...Parry fired")
	_expect_eq(player.block - block_before, CARD_BLOCK + _samurai.parry_block_per_level, "...its Block after the card's")
	var preview: EffectContext = controller.call("preview_context")
	_expect_eq(preview.chain_level_before_this, 1, "...and the hand reads the chain at level 1")

	controller.call("end_turn")
	var enemies_acting: bool = await ProbePlay.wait_until(self, func() -> bool: return bool(controller.get("_enemy_phase")), 10.0)
	_expect(enemies_acting, "The enemy turn comes")
	_expect_eq(player.chain_level, 0, "The turn's end clears the chain before the enemies act")
	_expect_eq(player.last_skillchain, &"", "...and its last skillchain")
	# A chain put back mid enemy turn: the next turn's start clears it too.
	_chain_at(player, CardData.ChainProperty.HOLD, 2)
	player.last_skillchain = Skillchain.PARRY
	var back: bool = await ProbePlay.wait_until(self, func() -> bool:
		return not bool(controller.get("_enemy_phase")) and ProbePlay.is_settled(controller), 20.0)
	_expect(back, "The player's turn comes back")
	_expect_eq(player.chain_level, 0, "The turn's start clears the chain")
	_expect_eq(player.chain_property, CardData.ChainProperty.NONE, "...leaving none to follow")
	_expect_eq(player.last_skillchain, &"", "...and no skillchain")
	await _teardown()
	_completed += 1

func _start_fight() -> Node:
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
	var body: Node3D = _field.get_node("Wanderer") as Node3D
	body.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("no fight started on floor 1")
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
	await ProbePlay.settle_fight(self, _field, controller)
	return controller

# Plays the first hand card with `property` and waits for it to resolve.
func _play_property(controller: Node, property: CardData.ChainProperty) -> void:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data != null and view.card_data.chain_property == property:
			controller.call("request_play", view)
			await ProbePlay.settle(self, controller)
			return
	_fail("no hand card with chain property %d" % property)

# `card` committed and resolved as BattleController._resolve_play() does:
# the chain stepped, the context carrying the level from before it and
# the link fired. Returns the link.
func _commit(player: Combatant, card: CardData, ctx: EffectContext) -> StringName:
	var before: int = player.chain_level
	var link: StringName = Skillchain.step(player, card)
	ctx.chain_level_before_this = before
	ctx.skillchain = link
	ctx.skillchain_level = player.chain_level
	_resolver.resolve_card(card, ctx)
	return link

func _chain_at(player: Combatant, property: CardData.ChainProperty, level: int) -> void:
	player.chain_property = property
	player.chain_level = level

func _player() -> Combatant:
	var player := Combatant.new(PLAYER_HP)
	player.parry_block_per_level = _samurai.parry_block_per_level
	player.recover_draw = _samurai.recover_draw
	player.lunge_damage_per_level = _samurai.lunge_damage_per_level
	return player

func _ctx(player: Combatant, enemies: Array[Combatant]) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = enemies
	ctx.target = enemies[0] if not enemies.is_empty() else null
	return ctx

func _effect(type: CardEffect.EffectType, value: int) -> CardEffect:
	var effect := CardEffect.new()
	effect.effect_type = type
	effect.value = value
	return effect

func _skill(property: CardData.ChainProperty) -> CardData:
	var card := CardData.new()
	card.card_name = "Probe Skill"
	card.card_type = CardData.CardType.SKILL
	card.target_type = CardData.TargetType.NONE
	card.chain_property = property
	return card

func _block_card(property: CardData.ChainProperty) -> CardData:
	var card: CardData = _skill(property)
	card.card_name = "Probe Guard"
	card.effects = [_effect(CardEffect.EffectType.BLOCK, CARD_BLOCK)] as Array[CardEffect]
	return card

# Like Severance: no property, Burst, 5 damage and 4 more per chain level.
func _burst_card() -> CardData:
	var card := CardData.new()
	card.card_name = "Probe Burst"
	card.card_type = CardData.CardType.ATTACK
	card.target_type = CardData.TargetType.ENEMY
	card.burst = true
	card.description = BURST_TEXT
	var hit: CardEffect = _effect(CardEffect.EffectType.DAMAGE, BURST_DAMAGE)
	hit.bonus_per_chain_level = BURST_PER_LEVEL
	card.effects = [hit] as Array[CardEffect]
	return card

func _attack(property: CardData.ChainProperty) -> CardData:
	var card := CardData.new()
	card.card_name = "Probe Cut"
	card.card_type = CardData.CardType.ATTACK
	card.target_type = CardData.TargetType.ENEMY
	card.chain_property = property
	card.effects = [_effect(CardEffect.EffectType.DAMAGE, CARD_DAMAGE)] as Array[CardEffect]
	return card

func _teardown() -> void:
	if _field != null:
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
