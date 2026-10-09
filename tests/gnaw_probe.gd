extends SceneTree

# Headless probe for Gnaw - 0 Energy, Common Attack, one enemy: a hit of
# 3 that Drains (CardEffect.drain_on_condition) when any Toll was spent
# earlier this turn (CardEffect.Condition.TOLL_SPENT_THIS_TURN, Combatant.
# toll_spent_this_turn): the player heals the HP it took, after block, no
# further than max HP. The hit is the card's own blow, so the Attack
# bonuses are in it and in its heal, and Ransom's half comes on top.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/gnaw_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants (max HP 70); Toll is spent the way any card spends it
# (EffectContext.spend_toll(), or Second Swing's repeat). The face case
# reads the drain clause grey (DORMANT) and in ink (LIVE). The fight case
# loads the real region scene, as claw_back_probe does, and plays Gnaw
# through BattleController: the face at hand size, the shared card-play
# sound (Gnaw has none of its own) before any Toll is spent and once
# Second Swing has spent some, and the condition gone at the next turn.
# Untyped against anything that names the RunState autoload.

const CASES := 8
const MAX_HP := 70
const ENEMY_HP := 100
const HIT := 3
const CARD_PATH := "res://cards/data/gnaw.tres"
const SECOND_SWING_PATH := "res://cards/data/second_swing.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const RANSOM_ACTIVE_PATH := "res://battle/rules/statuses/ransom_active.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Gnaw.png"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
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
	_check_no_toll_spent()
	_check_after_second_swing()
	_check_self_eater()
	_check_into_block()
	_check_capped_and_ransom()
	await _check_face()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("gnaw_probe: PASSED")
		quit(0)
	else:
		print("gnaw_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "Gnaw", "The card loads")
	_expect_eq(card.cost, 0, "...costs 0 Energy")
	_expect_eq(card.card_type, CardData.CardType.ATTACK, "...is an Attack")
	_expect_eq(card.rarity, CardData.CardRarity.COMMON, "...Common")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect_eq(card.description, "Deal {damage} damage. {if}If you spent Toll this turn, drain {damage} instead.{/if}", "...its text")
	_expect_eq(card.effects.size(), 1, "...one effect")
	var effect: CardEffect = card.effects[0]
	_expect_eq(effect.effect_type, CardEffect.EffectType.DAMAGE, "...an ordinary hit, the card's own blow")
	_expect_eq([effect.value, effect.condition], [HIT, CardEffect.Condition.TOLL_SPENT_THIS_TURN], "...3, conditioned on Toll spent this turn")
	_expect(effect.drain_on_condition and not effect.drains, "...that drains only while the condition holds")
	_expect_eq(CardBonus.mode(effect), CardBonus.Mode.DRAIN, "...CardBonus's DRAIN mode")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "The card has its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect(card.play_sound_path.is_empty(), "...no play sound of its own: the shared card-play sound")
	_expect_eq([card.critical_sound_pitch, card.critical_sound_volume_db], [1.0, 0.0], "...no conditional pitch or lift")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	_completed += 1

# --- Rules ---

func _check_no_toll_spent() -> void:
	var player: Combatant = _player(40)
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, HIT, "No Toll spent: deals 3")
	_expect_eq(player.hp, 40, "...and heals 0")
	_completed += 1

# Second Swing spends its 6 Toll on the repeat: Toll spent this turn.
func _check_after_second_swing() -> void:
	var player: Combatant = _player(40)
	player.toll = 6
	_play_card(load(SECOND_SWING_PATH), player, _enemy())
	_expect(player.toll == 0 and player.toll_spent_this_turn, "Second Swing's repeat spends 6 Toll: Toll spent this turn")
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, HIT, "...then Gnaw deals 3")
	_expect_eq(player.hp, 43, "...and heals 3")
	_completed += 1

# Self-Eater with Toll spent: its +3 is in the hit and the heal, after
# its 2 HP is paid - 3 + 3 = 6 dealt, 6 healed.
func _check_self_eater() -> void:
	var player: Combatant = _player(50)
	_play_card(load(SELF_EATER_PATH), player, _enemy())
	_spend_toll(player)
	var enemy: Combatant = _enemy()
	var hp_before: int = player.hp
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 6, "Under Self-Eater with Toll spent: deals 6")
	_expect_eq(player.hp, hp_before - 2 + 6, "...and heals 6, after paying 2 HP")
	_completed += 1

func _check_into_block() -> void:
	var player: Combatant = _player(40)
	_spend_toll(player)
	var enemy: Combatant = _enemy()
	enemy.block = 2
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, HIT - 2, "Into 2 Block: 1 gets through")
	_expect_eq(player.hp, 41, "...and it heals only that")
	_completed += 1

# Capped at max HP; and under Ransom its own 3, then Ransom's half on top.
func _check_capped_and_ransom() -> void:
	var full: Combatant = _player(MAX_HP - 1)
	_spend_toll(full)
	_play(full, _enemy())
	_expect_eq(full.hp, MAX_HP, "The heal stops at max HP")
	var player: Combatant = _player(40)
	var ransom: StatusData = load(RANSOM_ACTIVE_PATH)
	Status.apply_to(player.statuses, ransom)
	_spend_toll(player)
	_play(player, _enemy())
	var half: int = floori(float(HIT) * ransom.ransom_heal_fraction)
	_expect_eq(player.hp, 40 + HIT + half, "Under Ransom: its own 3 and Ransom's %d on top" % half)
	_completed += 1

# --- Face and fight ---

# In a battle hand: the drain clause grey (DORMANT) with no Toll spent,
# in ink (LIVE) once some has been; the base clause ink either way.
func _check_face() -> void:
	var player: Combatant = _player(40)
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_bonus_context(_ctx(player))
	view.set_card_data(load(CARD_PATH))
	var dormant: String = "[color=#%s]" % Color(view.bonus_dormant_ink, view.rules_alpha).to_html(true)
	var text: String = view.rules_text.text
	_expect_eq(view._bonus_state, CardBonus.State.DORMANT, "No Toll spent: the face reads DORMANT")
	_expect(text.find(dormant) >= 0 and text.find(dormant) < text.find("If you spent") and text.find(dormant) > text.find("Deal"), "...the drain clause grey, the hit in ink (%s)" % text)
	_spend_toll(player)
	view.set_bonus_context(_ctx(player))
	text = view.rules_text.text
	_expect_eq(view._bonus_state, CardBonus.State.LIVE, "Toll spent: LIVE")
	_expect(not text.contains(dormant), "...the drain clause in ink (%s)" % text)
	var regex := RegEx.new()
	regex.compile("\\[/?[a-z]+(=[^\\]]*)?\\]")
	_expect_eq(regex.sub(text, "", true), "Deal 3 damage. If you spent Toll this turn, drain 3 instead.", "...reading Deal 3 damage. If you spent Toll this turn, drain 3 instead.")
	view.free()
	_completed += 1

# The real fight: Gnaw's face at hand size; played with no Toll spent,
# the shared card-play sound and no heal; Second Swing spends 6, then
# Gnaw drains 3, the same sound; at the next turn the condition is gone -
# no heal.
func _check_fight() -> void:
	var controller: Node = await _start_fight(50)
	if controller != null:
		var player: Combatant = controller.get("player")
		var target: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
		combatant.max_hp = 999
		combatant.hp = 999
		var card: CardData = await _deal(controller, CARD_PATH)
		var view: CardView = _view(controller, card)
		if view != null:
			_expect_eq(view.cost_label.text, "0", "The face: 0 Energy")
			_expect(view.rules_font_sizes.has(view.rules_text.get_theme_font_size("normal_font_size")), "...its text at a rules size")
			_expect_eq(view.size, view.card_size, "...fitting the face at hand size")
		await _gnaw(controller, card, target, false, "No Toll spent")
		player.toll = 6
		player.energy = 3
		await _play_real(controller, await _deal(controller, SECOND_SWING_PATH), target)
		_expect(player.toll_spent_this_turn, "Second Swing spends its 6: Toll spent this turn")
		await _gnaw(controller, await _deal(controller, CARD_PATH), target, true, "Then")
		await controller.call("end_turn")
		var deadline: int = Time.get_ticks_msec() + 15000
		while bool(controller.get("_input_locked")) and Time.get_ticks_msec() < deadline:
			await process_frame
		_expect(not player.toll_spent_this_turn, "At the next turn the condition resets")
		controller.get("deck").call("discard_hand")
		await _gnaw(controller, await _deal(controller, CARD_PATH), target, false, "The next turn")
	await _teardown()
	_completed += 1

# One real play of Gnaw at `target`: 3 dealt, `drains` heals 3, otherwise
# no heal - and either way the shared card-play sound, no override, read
# as the play commits (card_played, after the overlay has answered it).
func _gnaw(controller: Node, card: CardData, target: Node, drains: bool, label: String) -> void:
	var player: Combatant = controller.get("player")
	var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
	player.hp = 40
	# Grace the enemy's hit opened would reclaim HP from this one too -
	# closed, so the heal is Gnaw's drain alone.
	player.grace = 0
	combatant.block = 0
	var enemy_before: int = combatant.hp
	var cue: AudioStreamPlayer = _overlay.get("_card_play_player")
	var own: AudioStreamPlayer = _overlay.get("_card_override_player")
	for player_node: AudioStreamPlayer in [cue, own]:
		if player_node != null:
			player_node.stop()
	var heard: Array[bool] = []
	var listen := func(played: CardData, _target: Node) -> void:
		if played != card:
			return
		var override: AudioStreamPlayer = _overlay.get("_card_override_player")
		heard.append(cue != null and cue.playing)
		heard.append(override != null and override.playing)
	controller.connect("card_played", listen)
	await _play_real(controller, card, target)
	controller.disconnect("card_played", listen)
	_expect_eq(enemy_before - combatant.hp, HIT, "%s: Gnaw deals 3" % label)
	_expect_eq(player.hp - 40, HIT if drains else 0, "...and heals %d" % (HIT if drains else 0))
	_expect_eq(heard, [true, false] as Array[bool], "...the shared card-play sound plays, no override")

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	return player

func _enemy() -> Combatant:
	return Combatant.new(ENEMY_HP)

# 1 Toll spent the way any card spends it, earlier this turn.
func _spend_toll(player: Combatant) -> void:
	player.toll += 1
	_ctx(player).spend_toll(1)

func _ctx(player: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	return ctx

func _play(player: Combatant, enemy: Combatant) -> void:
	_play_card(load(CARD_PATH), player, enemy)

func _play_card(card: CardData, player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy] as Array[Combatant]
	_resolver.resolve_card(card, ctx)

func _start_fight(hp: int) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
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

func _play_real(controller: Node, card: CardData, target: Node) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if not bool(controller.call("is_awaiting_target")):
		_fail("'%s' didn't ask for a target" % card.card_name)
		return
	controller.call("confirm_target", target)
	# By the clock, not frames, which run unthrottled headless.
	var deadline: int = Time.get_ticks_msec() + 5000
	while bool(controller.get("_input_locked")) and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 3:
		await process_frame

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
