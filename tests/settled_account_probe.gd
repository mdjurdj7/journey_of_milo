extends SceneTree

# Headless probe for Settled Account - 1 Energy, Common Skill, GUARD, no
# target: gain 5 block, then spend up to 5 of the Toll held for 1 block
# each (BLOCK 5, then a TOLL_BLOCK capped at toll_cost 5 - TollBlockEffect).
# The spend is automatic and counts as Toll spent this turn; Toll spent
# earlier doesn't matter. Under Last Resort it gains no block and spends
# nothing. Settled Account+ is 6 and up to 8.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/settled_account_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants, working each number out of the card's own data. The fight
# case loads the real region scene and plays through BattleController:
# the face at hand size reading the Toll it will spend, its own sound -
# at the card's pitch and lift when it spends, 1.0 and the usual level
# when it has nothing to spend. Untyped against anything that names the
# RunState autoload.

const CASES := 9
const MAX_HP := 70
const CARD_PATH := "res://cards/data/settled_account.tres"
const TEMPERED_PATH := "res://cards/tempered/settled_account_tempered.tres"
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
var _cap: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var card: CardData = load(CARD_PATH)
	_base = card.effects[0].value
	_cap = card.effects[1].toll_cost

	_check_data()
	_check_nothing_held()
	_check_some_held()
	_check_capped()
	_check_earlier_spend()
	_check_last_resort()
	_check_tempered()
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
	_expect_eq(card.offer, CardData.OfferScope.REWARDABLE, "...rewardable")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...takes no enemy target")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.GUARD, "...reading GUARD")
	_expect_eq(card.description, "Gain {block} block.\n{battle}Spend {toll_block} Toll: gain {toll_block} more block.{/battle}{outside}Spend up to {toll_block} Toll: gain that much more block.{/outside}", "...its text")
	_expect_eq(_shape(card), [CardEffect.EffectType.BLOCK, 5, CardEffect.EffectType.TOLL_BLOCK, 5], "...BLOCK 5, then TOLL_BLOCK up to 5")
	_expect_eq(CardBonus.mode(card.effects[0]), CardBonus.Mode.NONE, "...no condition left")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Settled Account+")
	_expect_eq(tempered.description, card.description, "Settled Account+ reads the same text")
	_expect_eq(_shape(tempered), [CardEffect.EffectType.BLOCK, 6, CardEffect.EffectType.TOLL_BLOCK, 8], "...BLOCK 6, then TOLL_BLOCK up to 8")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "The card has its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its play sound")
	_expect(load(card.play_sound_path) is AudioStream, "...which loads")
	_expect_eq([card.critical_sound_pitch, card.critical_sound_volume_db], [0.95, 1.0], "...fuller when it spends (0.95, +1 dB)")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	_completed += 1

# [BLOCK type, value, TOLL_BLOCK type, cap] - a card's two effects.
func _shape(card: CardData) -> Array:
	if card.effects.size() != 2:
		return [card.effects.size()]
	var block: CardEffect = card.effects[0]
	var toll_block: CardEffect = card.effects[1]
	return [block.effect_type, block.value, toll_block.effect_type, toll_block.toll_cost]

# --- Rules ---

func _check_nothing_held() -> void:
	var player: Combatant = _player()
	_play(player)
	_expect_eq(player.block, _base, "No Toll held: %d block" % _base)
	_expect(not player.toll_spent_this_turn, "...and no Toll spent this turn")
	_completed += 1

func _check_some_held() -> void:
	var player: Combatant = _player()
	player.toll = _cap - 2
	_play(player)
	_expect_eq(player.block, _base + _cap - 2, "%d Toll held: all of it spent, %d block" % [_cap - 2, _base + _cap - 2])
	_expect_eq(player.toll, 0, "...no Toll left")
	_expect(player.toll_spent_this_turn, "...and it counts as Toll spent this turn")
	_completed += 1

func _check_capped() -> void:
	var player: Combatant = _player()
	player.toll = _cap + 7
	_play(player)
	_expect_eq(player.block, _base + _cap, "%d Toll held: %d spent, %d block" % [_cap + 7, _cap, _base + _cap])
	_expect_eq(player.toll, 7, "...7 left")
	_completed += 1

# Toll spent earlier this turn no longer counts: Reckoning took it all, so
# there is nothing to spend.
func _check_earlier_spend() -> void:
	var player: Combatant = _player()
	player.toll = 20
	_play_card(load(RECKONING_PATH), player, Combatant.new(100))
	_expect(player.toll == 0 and player.toll_spent_this_turn, "Reckoning spends all 20")
	_play(player)
	_expect_eq(player.block, _base, "...then %d block, no more" % _base)
	_completed += 1

# Last Resort refuses Block from any card - and with no Block to buy, the
# card spends nothing.
func _check_last_resort() -> void:
	var player: Combatant = _player()
	player.hp = 15
	_play_card(load(LAST_RESORT_PATH), player, Combatant.new(100))
	player.toll = 6
	player.toll_spent_this_turn = false
	var before: int = player.block
	_play(player)
	_expect_eq(player.block - before, 0, "Under Last Resort: no block")
	_expect_eq(player.toll, 6, "...no Toll spent")
	_expect(not player.toll_spent_this_turn, "...and no Toll spent this turn")
	_completed += 1

func _check_tempered() -> void:
	var player: Combatant = _player()
	player.toll = 10
	_play_card(load(TEMPERED_PATH), player, null)
	_expect_eq(player.block, 14, "Settled Account+ on 10 Toll: 6 + 8 block")
	_expect_eq(player.toll, 2, "...2 Toll left")
	_completed += 1

# --- Face and fight ---

# Outside a fight: the rule, its cap. In a battle hand: the Toll it will
# spend, up to the cap, 0 under Last Resort.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\nSpend up to 5 Toll: gain that much more block.", "The face outside a fight says its rule")
	_expect_eq(view._bonus_state, CardBonus.State.NONE, "...with no clause to light")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 6 block.\nSpend up to 8 Toll: gain that much more block.", "Settled Account+ outside a fight")
	view.set_card_data(load(CARD_PATH))
	var player: Combatant = _player()
	view.set_bonus_context(_ctx(player))
	view.set_toll(3)
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\nSpend 3 Toll: gain 3 more block.", "In a battle hand on 3 Toll: spend 3")
	view.set_toll(9)
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\nSpend 5 Toll: gain 5 more block.", "...on 9 Toll: spend 5, the cap")
	player.hp = 15
	_play_card(load(LAST_RESORT_PATH), player, Combatant.new(100))
	view.set_stance(player.stance)
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 0 block.\nSpend 0 Toll: gain 0 more block.", "...under Last Resort: 0 and 0")
	view.free()
	_completed += 1

# The real fight: the face at hand size; played on no Toll, 5 block and
# its sound at 1.0; a copy on 7 Toll reads its 5, plays for 10 leaving 2,
# its sound at 0.95 and 1 dB up, and counts as Toll spent this turn.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.energy = 99
		player.toll = 0
		controller.emit_signal("toll_changed", 0)
		var first: CardData = await _deal(controller, CARD_PATH)
		var view: CardView = _view(controller, first)
		if view != null:
			_expect_eq(view.cost_label.text, "1", "The face: 1 Energy")
			_expect_eq(view.type_label.text, "GUARD", "...labelled GUARD")
			_expect(view.rules_font_sizes.has(view.rules_text.get_theme_font_size("normal_font_size")), "...its text at a rules size")
			_expect_eq(view.size, view.card_size, "...fitting the face at hand size")
		var before: int = player.block
		await _play_real(controller, first, null)
		_expect_eq(player.block - before, _base, "No Toll: %d block" % _base)
		_expect_sound(false, "No Toll")
		player.toll = 7
		controller.emit_signal("toll_changed", 7)
		var second: CardData = await _deal(controller, CARD_PATH)
		view = _view(controller, second)
		var face: String = view.rules_text.get_parsed_text() if view != null else "no view"
		_expect(face.ends_with("Spend 5 Toll: gain 5 more block."), "On 7 Toll a copy in hand reads its 5 (%s)" % face)
		before = player.block
		await _play_real(controller, second, null)
		_expect_eq(player.block - before, _base + _cap, "...plays for %d" % (_base + _cap))
		_expect_eq(player.toll, 2, "...leaving 2 Toll")
		_expect(player.toll_spent_this_turn, "...and counts as Toll spent this turn")
		_expect_sound(true, "Toll spent")
	await _teardown()
	_completed += 1

func _expect_sound(fuller: bool, label: String) -> void:
	var card: CardData = load(CARD_PATH)
	var sound: AudioStreamPlayer = _overlay.get("_card_override_player")
	_expect(sound != null and sound.stream != null and sound.stream.resource_path == SOUND_PATH, "%s: its own sound plays" % label)
	if sound != null:
		var pitch: float = card.critical_sound_pitch if fuller else 1.0
		var level: float = float(_overlay.get("card_override_volume_db")) + (card.critical_sound_volume_db if fuller else 0.0)
		_expect(is_equal_approx(sound.pitch_scale, pitch), "...at pitch %s (%s)" % [pitch, sound.pitch_scale])
		_expect(is_equal_approx(sound.volume_db, level), "...at %s dB (%s)" % [level, sound.volume_db])

# --- Helpers ---

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = 50
	return player

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
