extends SceneTree

# Headless probe for Settled Account - 1 Energy, Common Skill, GUARD, no
# target: gain 5 block, then - all or nothing - spend exactly 5 Toll for 5
# more (BLOCK 5, then a TOLL_BLOCK of toll_cost 5, value 5 -
# TollBlockEffect). On under 5 Toll the clause spends nothing and gains
# nothing. The spend is automatic and counts as Toll spent this turn; Toll
# spent earlier doesn't matter. Under Last Resort it gains no block and
# spends nothing. Settled Account+ is 8, then the same 5 for 5.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/settled_account_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants, working each number out of the card's own data. The fight
# case loads the real region scene and plays through BattleController:
# the face at hand size, its Toll clause grey until it will pay, its own
# sound - at the card's pitch and lift when it spends, 1.0 and the usual
# level when it has nothing to spend. Untyped against anything that names the
# RunState autoload.

const CASES := 10
const MAX_HP := 70
const CARD_PATH := "res://cards/data/settled_account.tres"
const TEMPERED_PATH := "res://cards/tempered/settled_account_tempered.tres"
const COME_DUE_PATH := "res://cards/data/come_due.tres"
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
var _spend: int = 0
var _more: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var card: CardData = load(CARD_PATH)
	_base = card.effects[0].value
	_spend = card.effects[1].toll_cost
	_more = card.effects[1].value

	_check_data()
	_check_nothing_held()
	_check_some_held()
	_check_exact()
	_check_more_held()
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
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.COMMON, "...Common")
	_expect_eq(card.offer, CardData.OfferScope.REWARDABLE, "...rewardable")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...takes no enemy target")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.GUARD, "...reading GUARD")
	_expect_eq(card.description, "Gain {block} block.\n{if}{toll_price}: {toll_block} more block.{/if}", "...its text")
	_expect_eq(_shape(card), [CardEffect.EffectType.BLOCK, CardEffect.EffectType.TOLL_BLOCK], "...BLOCK, then TOLL_BLOCK")
	_expect_eq(CardBonus.mode(card.effects[0]), CardBonus.Mode.NONE, "...no condition left")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Settled Account+")
	_expect_eq(tempered.description, card.description, "Settled Account+ reads the same text")
	_expect_eq(_shape(tempered), _shape(card), "...the same effects")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "The card has its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its play sound")
	_expect(load(card.play_sound_path) is AudioStream, "...which loads")
	_expect_eq([card.critical_sound_pitch, card.critical_sound_volume_db], [0.95, 1.0], "...fuller when it spends (0.95, +1 dB)")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	_completed += 1

# [BLOCK type, value, TOLL_BLOCK type, its spend, its Block] - a card's
# two effects.
func _shape(card: CardData) -> Array:
	if card.effects.size() != 2:
		return [card.effects.size()]
	var block: CardEffect = card.effects[0]
	var toll_block: CardEffect = card.effects[1]
	return [block.effect_type, toll_block.effect_type]

# --- Rules ---

func _check_nothing_held() -> void:
	var player: Combatant = _player()
	_play(player)
	_expect_eq(player.block, _base, "No Toll held: %d block" % _base)
	_expect(not player.toll_spent_this_turn, "...and no Toll spent this turn")
	_completed += 1

# One short of the spend: all or nothing, so nothing.
func _check_some_held() -> void:
	var player: Combatant = _player()
	player.toll = _spend - 1
	_play(player)
	_expect_eq(player.block, _base, "%d Toll held: none spent, %d block" % [_spend - 1, _base])
	_expect_eq(player.toll, _spend - 1, "...the Toll kept")
	_expect(not player.toll_spent_this_turn, "...and no Toll spent this turn")
	_completed += 1

func _check_exact() -> void:
	var player: Combatant = _player()
	player.toll = _spend
	_play(player)
	_expect_eq(player.block, _base + _more, "%d Toll held: all %d spent, %d block" % [_spend, _spend, _base + _more])
	_expect_eq(player.toll, 0, "...no Toll left")
	_expect(player.toll_spent_this_turn, "...and it counts as Toll spent this turn")
	_completed += 1

func _check_more_held() -> void:
	var player: Combatant = _player()
	player.toll = _spend + 7
	_play(player)
	_expect_eq(player.block, _base + _more, "%d Toll held: %d spent, %d block" % [_spend + 7, _spend, _base + _more])
	_expect_eq(player.toll, 7, "...7 left")
	_completed += 1

# Toll spent earlier this turn doesn't matter: Come Due spends 5 of 10,
# and the 5 left still pay.
func _check_earlier_spend() -> void:
	var player: Combatant = _player()
	player.toll = _spend * 2
	_play_card(load(COME_DUE_PATH), player, null)
	_expect(player.toll == _spend and player.toll_spent_this_turn, "Come Due spends 5 of 10")
	_play(player)
	_expect_eq(player.block, _base + _more, "...then %d block: the 5 left pay" % (_base + _more))
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
	_expect_eq(player.block, 13, "Settled Account+ on 10 Toll: 8 + 5 block")
	_expect_eq(player.toll, 5, "...5 Toll left")
	_completed += 1

# --- Face and fight ---

# The face always reads its fixed numbers. Outside a fight all in ink; in
# a battle hand the Toll clause grey under 5 Toll, in ink from 5, grey
# again under Last Resort (which spends nothing) - "Gain 5 block." always
# in ink.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	# The price is the Toll glyph - its image's place, one space in the
	# parsed text - then its number.
	var rule: String = " 5: 5 more block."
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\n" + rule, "The face outside a fight")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	_expect_eq(view._bonus_state, CardBonus.State.NONE, "...with no clause to light")
	_expect_clause_grey(view, false, "...all in ink")
	_expect(view.rules_text.text.contains(CardView.TOLL_SPACER_CLOSE), "...the Toll glyph inline")
	_expect(view.rules_text.text.contains("[b][color=#%s]%d[/color][/b]" % [(view.call("_toll_ink") as Color).to_html(true), _spend]), "...its number bold in the toll ink")
	var glyphs: Array = (view.call("_rules_geometry") as Dictionary)["glyphs"]
	_expect(glyphs.size() == 1 and view.keyword_at((glyphs[0] as Rect2).get_center()) == "Toll", "...the glyph hovered: the Toll slip")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 8 block.\n" + rule, "Settled Account+ outside a fight")
	view.set_card_data(load(CARD_PATH))
	var player: Combatant = _player()
	player.toll = _spend - 1
	view.set_bonus_context(_ctx(player))
	view.set_toll(player.toll)
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\n" + rule, "In a battle hand on 4 Toll: the fixed numbers")
	_expect_eq(view._bonus_state, CardBonus.State.DORMANT, "...the clause dormant")
	_expect_clause_grey(view, true, "...grey, the base in ink")
	player.toll = _spend
	view.set_toll(player.toll)
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\n" + rule, "...on 5 Toll: the same numbers")
	_expect_eq(view._bonus_state, CardBonus.State.LIVE, "...the clause live")
	_expect_clause_grey(view, false, "...all in ink")
	player.toll = 9
	view.set_toll(player.toll)
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 5 block.\n" + rule, "...on 9 Toll: still 5 and 5")
	player.hp = 15
	_play_card(load(LAST_RESORT_PATH), player, Combatant.new(100))
	view.set_stance(player.stance)
	_expect(view.rules_text.get_parsed_text().ends_with(rule), "...under Last Resort the clause keeps its numbers (%s)" % view.rules_text.get_parsed_text())
	_expect_eq(view._bonus_state, CardBonus.State.DORMANT, "...and goes dormant: it spends nothing")
	_expect_clause_grey(view, true, "...grey")
	view.free()
	_completed += 1

# Whether the face's second line - the Toll clause - is in the dormant
# ink, and the first never.
func _expect_clause_grey(view: CardView, grey: bool, label: String) -> void:
	var bbcode: String = view.rules_text.text
	var dormant: String = "[color=#%s]" % Color(view.bonus_dormant_ink, view.rules_alpha).to_html(true)
	var at: int = bbcode.find(dormant)
	var line_break: int = bbcode.find("\n")
	if grey:
		_expect(at > line_break and line_break >= 0, "%s (%s)" % [label, bbcode])
	else:
		_expect(at < 0, "%s (%s)" % [label, bbcode])

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
		_expect(face.ends_with(" 5: 5 more block."), "On 7 Toll a copy in hand reads its 5 for 5 (%s)" % face)
		_expect(view != null and view._bonus_state == CardBonus.State.LIVE, "...its clause in ink")
		before = player.block
		await _play_real(controller, second, null)
		_expect_eq(player.block - before, _base + _more, "...plays for %d" % (_base + _more))
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
