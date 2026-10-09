extends SceneTree

# Headless probe for Settled Account - 1 Energy, Common Skill, GUARD, no
# target: gain 3 block, plus 1 for every 2 Toll spent earlier this turn,
# rounded down (TOLL_SPENT_BLOCK, TollSpentBlockEffect.amount()), read off
# Combatant.toll_spent_amount_this_turn - which EffectContext.spend_toll()
# adds to beside Gnaw's flag, and the next turn clears.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/settled_account_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants, working each number out of the card's own data. The fight
# case loads the real region scene and plays through BattleController:
# the face at hand size, its number live mid-turn after Second Swing
# spends, its own sound - one take at its own pitch whatever was spent -
# and the count gone at the next turn. Untyped against anything that names
# the RunState autoload.

const CASES := 9
const MAX_HP := 70
const CARD_PATH := "res://cards/data/settled_account.tres"
const SECOND_SWING_PATH := "res://cards/data/second_swing.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const LAST_RESORT_PATH := "res://cards/data/last_resort.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Settled Account.png"
const SOUND_PATH := "res://assets/audio/cards/Settled Account/Settled Account.mp3"
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
var _base: int = 0
var _rate: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var effect: CardEffect = (load(CARD_PATH) as CardData).effects[0]
	_base = effect.value
	_rate = effect.toll_per_block

	_check_data()
	_check_nothing_spent()
	_check_after_second_swing()
	_check_after_reckoning()
	_check_odd_rounds_down()
	_check_tracker()
	_check_last_resort()
	await _check_face()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("settled_account_probe: PASSED")
		quit(0)
	else:
		print("settled_account_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "Settled Account", "The card loads")
	_expect_eq(card.cost, 1, "...costs 1 Energy")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.COMMON, "...Common")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...takes no enemy target")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.GUARD, "...reading GUARD")
	_expect_eq(card.description, "Gain {block} block.\n+1 per 2 Toll spent this turn.", "...its text")
	_expect_eq(card.effects.size(), 1, "...one effect")
	var effect: CardEffect = card.effects[0]
	_expect_eq([effect.effect_type, effect.value, effect.toll_per_block], [CardEffect.EffectType.TOLL_SPENT_BLOCK, 3, 2], "...TOLL_SPENT_BLOCK, 3 plus 1 per 2 Toll")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "The card has its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its play sound")
	_expect(load(card.play_sound_path) is AudioStream, "...which loads")
	_expect_eq([card.critical_sound_pitch, card.critical_sound_volume_db], [1.0, 0.0], "...one take at its own pitch and level")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	_completed += 1

# --- Rules ---

func _check_nothing_spent() -> void:
	var player: Combatant = _player()
	_play(player)
	_expect_eq(player.block, _base, "Nothing spent: %d block" % _base)
	_completed += 1

func _check_after_second_swing() -> void:
	var player: Combatant = _player()
	player.toll = 6
	_play_card(load(SECOND_SWING_PATH), player, Combatant.new(100))
	_expect_eq(player.toll_spent_amount_this_turn, 6, "Second Swing's repeat spends 6")
	_play(player)
	_expect_eq(player.block, _base + floori(6.0 / _rate), "...then %d block" % (_base + floori(6.0 / _rate)))
	_completed += 1

func _check_after_reckoning() -> void:
	var player: Combatant = _player()
	player.toll = 20
	_play_card(load(RECKONING_PATH), player, Combatant.new(100))
	_expect_eq(player.toll_spent_amount_this_turn, 20, "Reckoning spends all 20")
	_play(player)
	_expect_eq(player.block, _base + floori(20.0 / _rate), "...then %d block" % (_base + floori(20.0 / _rate)))
	_completed += 1

func _check_odd_rounds_down() -> void:
	var player: Combatant = _player()
	_spend(player, 7)
	_play(player)
	_expect_eq(player.block, _base + 3, "7 spent rounds down: %d block, not %d" % [_base + 3, _base + 4])
	_completed += 1

# The amount sums every spend, beside Gnaw's flag; a spend of nothing
# moves neither.
func _check_tracker() -> void:
	var player: Combatant = _player()
	_expect(not player.toll_spent_this_turn and player.toll_spent_amount_this_turn == 0, "A fresh player: nothing spent, no flag")
	_ctx(player).spend_toll(5)
	_expect(not player.toll_spent_this_turn and player.toll_spent_amount_this_turn == 0, "Spending with no Toll held spends nothing")
	_spend(player, 3)
	_spend(player, 4)
	_expect_eq(player.toll_spent_amount_this_turn, 7, "Two spends, 3 and 4: 7 in all")
	_expect(player.toll_spent_this_turn, "...and Gnaw's flag is set as before")
	_completed += 1

# Last Resort refuses Block from any card - this one's too.
func _check_last_resort() -> void:
	var player: Combatant = _player()
	player.hp = 15
	_play_card(load(LAST_RESORT_PATH), player, Combatant.new(100))
	_spend(player, 6)
	var before: int = player.block
	_play(player)
	_expect_eq(player.block - before, 0, "Under Last Resort: no block, whatever was spent")
	_completed += 1

# --- Face and fight ---

# Outside a fight it reads its base; read against a player who has spent,
# the live number - the rules' own.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 3 block.\n+1 per 2 Toll spent this turn.", "The face outside a fight: Gain 3 block.")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), view.rules_font_sizes[0], "...at the first rules size")
	var player: Combatant = _player()
	_spend(player, 20)
	view.set_bonus_context(_ctx(player))
	_expect(view.rules_text.get_parsed_text().begins_with("Gain 13 block."), "Against 20 spent: Gain 13 block. (%s)" % view.rules_text.get_parsed_text())
	view.free()
	_completed += 1

# The real fight: the face at hand size; played with nothing spent, 3
# block; a copy in hand reads 6 once Second Swing has spent 6, and plays
# for 6 - its sound at its own pitch both times; at the next turn the
# count is 0 and the face reads 3 again.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var target: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
		combatant.max_hp = 999
		combatant.hp = 999
		player.energy = 99
		var first: CardData = await _deal(controller, CARD_PATH)
		var view: CardView = _view(controller, first)
		if view != null:
			_expect_eq(view.cost_label.text, "1", "The face: 1 Energy")
			_expect_eq(view.type_label.text, "GUARD", "...labelled GUARD")
			_expect(view.rules_font_sizes.has(view.rules_text.get_theme_font_size("normal_font_size")), "...its text at a rules size")
			_expect_eq(view.size, view.card_size, "...fitting the face at hand size")
		var before: int = player.block
		await _play_real(controller, first, null)
		_expect_eq(player.block - before, _base, "Nothing spent: %d block" % _base)
		_expect_sound(1.0, "Nothing spent")
		var second: CardData = await _deal(controller, CARD_PATH)
		_expect(_face_text(controller, second).begins_with("Gain 3 block."), "A copy in hand reads 3 (%s)" % _face_text(controller, second))
		player.toll = 6
		await _play_real(controller, await _deal(controller, SECOND_SWING_PATH), target)
		_expect_eq(player.toll_spent_amount_this_turn, 6, "Second Swing spends 6")
		_expect(_face_text(controller, second).begins_with("Gain 6 block."), "...and the copy in hand now reads 6, mid-turn (%s)" % _face_text(controller, second))
		before = player.block
		await _play_real(controller, second, null)
		_expect_eq(player.block - before, _base + floori(6.0 / _rate), "...and plays for %d" % (_base + floori(6.0 / _rate)))
		_expect_sound(1.0, "After a spend, one take still")
		await controller.call("end_turn")
		var deadline: int = Time.get_ticks_msec() + 15000
		while bool(controller.get("_input_locked")) and Time.get_ticks_msec() < deadline:
			await process_frame
		_expect_eq(player.toll_spent_amount_this_turn, 0, "At the next turn the count resets")
		_expect(not player.toll_spent_this_turn, "...and Gnaw's flag with it")
		controller.get("deck").call("discard_hand")
		var third: CardData = await _deal(controller, CARD_PATH)
		_expect(_face_text(controller, third).begins_with("Gain 3 block."), "...a fresh copy reads 3 (%s)" % _face_text(controller, third))
	await _teardown()
	_completed += 1

func _expect_sound(pitch: float, label: String) -> void:
	var sound: AudioStreamPlayer = _overlay.get("_card_override_player")
	_expect(sound != null and sound.stream != null and sound.stream.resource_path == SOUND_PATH, "%s: its own sound plays" % label)
	if sound != null:
		_expect(is_equal_approx(sound.pitch_scale, pitch), "...at pitch %s (%s)" % [pitch, sound.pitch_scale])
		_expect(is_equal_approx(sound.volume_db, float(_overlay.get("card_override_volume_db"))), "...at the override level")

# --- Helpers ---

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = 50
	return player

# `amount` Toll spent the way every card spends it.
func _spend(player: Combatant, amount: int) -> void:
	player.toll += amount
	_ctx(player).spend_toll(amount)

func _ctx(player: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	return ctx

func _play(player: Combatant) -> void:
	_play_card(load(CARD_PATH), player, null)

func _play_card(card: CardData, player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	var enemies: Array[Combatant] = [enemy if enemy != null else Combatant.new(100)]
	ctx.enemies = enemies
	_resolver.resolve_card(card, ctx)

func _face_text(controller: Node, card: CardData) -> String:
	var view: CardView = _view(controller, card)
	return view.rules_text.get_parsed_text() if view != null else "(not in hand)"

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
