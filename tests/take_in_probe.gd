extends SceneTree

# Headless probe for Take In - 1 Energy, Uncommon Skill: "Devour a card
# in your hand." - and the Devour keyword. The eaten card leaves the
# hand for the fight (the Spent pile, back next fight; a Twice Over copy
# just gone) and yields, for each Energy of its PRINTED cost, 2: an Attack
# Teeth (your Attacks deal that much more - every hit, each Lash repeat),
# a Skill Marrow (that much Block at the start of each turn); a 0-cost
# card, a Power and a Stance nothing. The line the hand shows over a
# candidate (DevourYield.describe()) says exactly what the Devour applies.
# The fight's Devoured list counts each. The keyword's own sound plays
# once per card it eats, as the bite starts - not as Take In is played.
# The Devour button is untouched: it still heals 3, yields nothing, counts
# nothing and never plays the keyword's sound. Take In+ costs 0.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/take_in_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases resolve the real cards on bare Combatants and a bare Deck;
# the fight cases play them through BattleController on floor 1. Untyped
# against anything that names the RunState autoload.

const CASES := 11
const MAX_HP := 70
const ENEMY_HP := 200
const CARD_PATH := "res://cards/data/take_in.tres"
const TEMPERED_PATH := "res://cards/tempered/take_in_tempered.tres"
const ART_PATH := "res://cards/art/Wanderer/Take In.png"
const SLASH_PATH := "res://cards/data/slash.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const CLAW_BACK_PATH := "res://cards/data/claw_back.tres"
const GNAW_PATH := "res://cards/data/gnaw.tres"
const THE_RETURN_PATH := "res://cards/data/the_return.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const LASH_PATH := "res://cards/weapon/lash.tres"
const TEETH_PATH := "res://battle/rules/statuses/teeth.tres"
const MARROW_PATH := "res://battle/rules/statuses/marrow.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const KEYWORD_SOUND_PATH := "res://assets/audio/sfx/devour/devour_keyword.wav"
const LASH_TAG := &"lash"

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _per_energy: int = 0

func _initialize() -> void:
	_run_state = root.get_node("RunState")
	_per_energy = (load(CARD_PATH) as CardData).effects[0].value
	_check_data()
	_check_preview_matches_yield()
	_check_teeth_every_hit()
	_check_printed_cost()
	_check_out_of_the_hand()
	_check_copy_devoured()
	_check_devoured_list()
	await _check_greyed_and_cancel()
	await _check_choose_and_devour()
	await _check_marrow_next_turn()
	await _check_button_unchanged()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("take_in_probe: PASSED")
		quit(0)
	else:
		print("take_in_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq([card.card_name, card.cost, card.card_type, card.rarity, card.removal_scope, card.offer, card.card_class, card.description], ["Take In", 1, CardData.CardType.SKILL, CardData.CardRarity.UNCOMMON, CardData.RemovalScope.NONE, CardData.OfferScope.REWARDABLE, &"wanderer", "Devour a card in your hand."], "Take In: 1 Energy, an Uncommon Skill, rewardable, the Wanderer's")
	_expect(card.effects.size() == 1 and card.effects[0].effect_type == CardEffect.EffectType.DEVOUR_FROM_HAND and _per_energy == 2, "...one DEVOUR_FROM_HAND, 2 per Energy")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Take In+")
	_expect(card.art != null and card.art.resource_path == ART_PATH and tempered.art == card.art, "...both carrying its art")
	_expect_eq([tempered.card_name, tempered.cost, tempered.description, tempered.effects[0].value], ["Take In+", 0, card.description, _per_energy], "Take In+: 0 Energy, the same text and yield")
	var definition: String = KeywordTable.shared().definition("Devour")
	_expect(definition.contains("deal %d more" % _per_energy) and definition.contains("gives %d Block" % _per_energy), "The Devour keyword's numbers are the card's (%s)" % definition)
	_expect(KeywordTable.shared().pattern().search("Devour a card") != null, "...and Take In's text inks it")
	_completed += 1

# For an Attack (Claw Back, 2), a Skill (Brace, 1), a 0-cost card (Gnaw),
# a Power (The Return, 2) and a Stance (Self-Eater, 1): the line the hand
# shows names exactly what the Devour applies.
func _check_preview_matches_yield() -> void:
	var cases: Array = [
		[CLAW_BACK_PATH, "+4 damage this combat"],
		[BRACE_PATH, "+2 Block each turn"],
		[GNAW_PATH, "Nothing"],
		[THE_RETURN_PATH, "Nothing"],
		[SELF_EATER_PATH, "Nothing"],
	]
	for case in cases:
		var eaten: CardData = (load(case[0]) as CardData).duplicate()
		var preview: String = DevourYield.describe(eaten, _per_energy)
		var player: Combatant = _player()
		_devour(player, eaten)
		var applied: String = _applied_line(player)
		_expect_eq(preview, case[1], "%s: the line reads %s" % [eaten.card_name, case[1]])
		_expect_eq(applied, preview, "...and the Devour applies exactly that")
	_completed += 1

# Teeth 4 (a Claw Back eaten): a Slash deals 4 more; a third Lash in a
# row deals 4 more on each of its three hits.
func _check_teeth_every_hit() -> void:
	var plain: Combatant = _player()
	var teeth: Combatant = _player()
	_devour(teeth, (load(CLAW_BACK_PATH) as CardData).duplicate())
	_expect_eq(_damage_of(SLASH_PATH, plain, 0) + 4, _damage_of(SLASH_PATH, teeth, 0), "Teeth 4: a Slash deals 4 more")
	_expect_eq(_damage_of(LASH_PATH, plain, 2) + 12, _damage_of(LASH_PATH, teeth, 2), "...a third Lash, 4 more on each of its 3 hits")
	_completed += 1

# The printed cost: a discount or a free card leaves the yield alone.
func _check_printed_cost() -> void:
	var player: Combatant = _player()
	player.first_card_free = true
	var claw: CardData = (load(CLAW_BACK_PATH) as CardData).duplicate()
	_devour(player, claw)
	_expect_eq(_applied_line(player), "+4 damage this combat", "With the first card free, a devoured Claw Back still yields its printed 2 x 2")
	_completed += 1

# Out of the hand, onto the Spent pile and spent_unplayed - back next
# fight - and nothing on the run.
func _check_out_of_the_hand() -> void:
	var player: Combatant = _player()
	var brace: CardData = (load(BRACE_PATH) as CardData).duplicate()
	var deck := Deck.new()
	deck.hand.append(brace)
	_devour(player, brace, deck)
	_expect(not deck.hand.has(brace) and deck.exhaust_pile.has(brace) and deck.spent_unplayed.has(brace), "The eaten card: out of the hand, Spent, unplayed (back next fight)")
	_completed += 1

# A Twice Over copy eaten: it yields and counts, then is gone - no pile,
# not spent_unplayed, nothing to come back.
func _check_copy_devoured() -> void:
	var player: Combatant = _player()
	var deck := Deck.new()
	var slash: CardData = (load(SLASH_PATH) as CardData).duplicate()
	deck.hand.append(slash)
	var copy: CardData = deck.add_copy(slash)
	_expect(copy != null and copy.battle_copy, "A Twice Over copy in the hand")
	if copy != null:
		_devour(player, copy, deck)
		_expect_eq(_applied_line(player), "+2 damage this combat", "...devoured, it yields as its card")
		_expect(player.devoured_cards.has(copy), "...counts on the Devoured list")
		_expect(not deck.hand.has(copy) and not deck.exhaust_pile.has(copy) and not deck.spent_unplayed.has(copy) and not deck.discard_pile.has(copy), "...and is gone: in no pile, nothing to come back")
	_completed += 1

func _check_devoured_list() -> void:
	var player: Combatant = _player()
	var slash: CardData = (load(SLASH_PATH) as CardData).duplicate()
	var brace: CardData = (load(BRACE_PATH) as CardData).duplicate()
	_devour(player, slash)
	_devour(player, brace)
	_expect_eq(player.devoured_cards.size(), 2, "Two Take Ins: two on the Devoured list")
	var expected: Array[CardData] = [slash, brace]
	_expect(player.devoured_cards == expected, "...in order")
	_expect_eq(_applied_line(player), "+2 damage this combat|+2 Block each turn", "...each yield its own")
	_completed += 1

# Alone in the hand, Take In is greyed; with a card to eat, its choice
# opens, and a cancel spends nothing.
func _check_greyed_and_cancel() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var take_in: CardData = await _deal(controller, CARD_PATH)
		_expect(not bool(controller.call("_is_playable", take_in)), "Alone in the hand: Take In can't be played")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		_expect(bool(controller.call("_is_playable", take_in)), "With a card to eat: it can")
		var energy: int = player.energy
		controller.call("request_play", _view(controller, take_in))
		_expect(bool(controller.call("_choice_open")), "...its choice opens")
		_expect(_prompt_text().begins_with("DEVOUR"), "...asking to DEVOUR (%s)" % _prompt_text())
		controller.call("cancel_choice")
		await ProbePlay.settle(self, controller)
		_expect(player.energy == energy and (deck.get("hand") as Array).has(take_in) and (deck.get("hand") as Array).has(slash) and player.devoured_cards.is_empty(), "Cancelled: no Energy, both cards in hand, nothing devoured")
	await _teardown()
	_completed += 1

# The real choice: hovering a candidate shows its yield over it - the
# card's own line, clear of the armed Take In above and of the card - and
# no keyword definition; picking it devours it, its sound once with the
# bite and not as Take In plays.
func _check_choose_and_devour() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var claw: CardData = await _deal(controller, CLAW_BACK_PATH)
		var brace: CardData = await _deal(controller, BRACE_PATH)
		var gnaw: CardData = await _deal(controller, GNAW_PATH)
		var take_in: CardData = await _deal(controller, CARD_PATH)
		var energy: int = player.energy
		var armed: CardView = _view(controller, take_in)
		controller.call("request_play", armed)
		for i in 30:
			await process_frame
		var hand: Node = controller.get("_hand_container")
		var line: DevourYieldLine = hand.call("get_yield_line")
		for pair in [[claw, "+4 damage this combat"], [brace, "+2 Block each turn"], [gnaw, "Nothing"]]:
			var view: CardView = _view(controller, pair[0])
			view.set_hovered(true)
			for i in 20:
				await process_frame
			_expect(line != null and line.visible and line.get_text() == pair[1], "Hovering %s: %s over it (%s)" % [(pair[0] as CardData).card_name, pair[1], line.get_text() if line != null else "no line"])
			if line != null:
				var shown := Rect2(line.global_position, line.size)
				var card_rect: Rect2 = view.get_screen_rect_now()
				var armed_rect: Rect2 = armed.get_screen_rect_now()
				_expect(shown.end.y <= card_rect.position.y and not shown.intersects(armed_rect) and not shown.intersects(card_rect), "...above the card, clear of it and of Take In (line %s, card %s, Take In %s)" % [shown, card_rect, armed_rect])
				_expect(not view.keyword_hover_allowed(), "...and no keyword definition on it")
				# On a one-line strip of the card's bone, so it reads over
				# any ground.
				_expect(line.get("_bone") == view.field_color and float(line.get("_reveal")) >= 1.0, "...on a strip of the card's bone (%s)" % str(line.get("_bone")))
				_expect(line.get_line_count() == 1 and line.size.y > float(hand.get("yield_line_font_size_px")), "...one line on it (%d lines, %.0f px tall)" % [line.get_line_count(), line.size.y])
			view.set_hovered(false)
			for i in 5:
				await process_frame
		_expect(line != null and not line.visible, "Over no candidate: no line")
		var heard: Dictionary = _listen_keyword_sound(controller, take_in)
		controller.call("toggle_choice", _view(controller, claw))
		await ProbePlay.settle(self, controller)
		_stop_listening(controller, heard)
		_expect_eq(heard["at_play"], [false] as Array[bool], "Take In played: not the keyword's sound")
		_expect_eq(heard["at_devour"], [true] as Array[bool], "Claw Back devoured: the keyword's sound, once")
		var sound: AudioStreamPlayer = _overlay().get("_devour_keyword_player")
		_expect(sound != null and sound.stream != null and sound.stream.resource_path == KEYWORD_SOUND_PATH and sound.bus == &"SFX", "...devour_keyword.wav, on the SFX bus")
		_expect(not (deck.get("hand") as Array).has(claw) and (deck.get("exhaust_pile") as Array).has(claw), "Picked: Claw Back devoured")
		_expect_eq(_applied_line(player), "+4 damage this combat", "...Teeth 4 on the Wanderer")
		var eaten: Array[CardData] = [claw]
		_expect(player.devoured_cards == eaten, "...on the Devoured list")
		_expect_eq(energy - player.energy, 1, "...Take In's 1 Energy paid")
		_expect((deck.get("discard_pile") as Array).has(take_in), "...and Take In discarded")
		_expect(line != null and not line.visible, "The choice closed: no line")
	await _teardown()
	_completed += 1

# Marrow 2 (a Brace eaten): no Block this turn; 2 at the start of the next.
func _check_marrow_next_turn() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var brace: CardData = await _deal(controller, BRACE_PATH)
		var take_in: CardData = await _deal(controller, CARD_PATH)
		var block: int = player.block
		controller.call("request_play", _view(controller, take_in))
		controller.call("toggle_choice", _view(controller, brace))
		await ProbePlay.settle(self, controller)
		_expect_eq(player.block, block, "Marrow: no Block this turn")
		var turn: int = int(controller.get("_player_turn"))
		controller.call("end_turn")
		await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and ProbePlay.is_settled(controller), 20.0)
		_expect_eq(player.block, 2, "...2 Block at the start of the next")
	await _teardown()
	_completed += 1

# The Devour button: still heals 3, yields nothing, counts nothing, and
# never plays the keyword's sound.
func _check_button_unchanged() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Object = controller.get("deck")
		var claw: CardData = await _deal(controller, CLAW_BACK_PATH)
		player.hp = player.max_hp - 10
		var hp: int = player.hp
		var heard: Dictionary = _listen_keyword_sound(controller, null)
		var bitten: Array[bool] = []
		var on_bite := func(_card: CardData) -> void: bitten.append(_keyword_sound_playing())
		controller.connect("card_devoured", on_bite)
		controller.call("devour")
		controller.call("request_play", _view(controller, claw))
		await ProbePlay.wait_until(self, func() -> bool: return not bool(controller.get("_input_locked")), 5.0)
		controller.disconnect("card_devoured", on_bite)
		_stop_listening(controller, heard)
		_expect_eq(bitten, [false] as Array[bool], "The Devour button's bite: not the keyword's sound")
		_expect(not _keyword_sound_playing() and (heard["at_devour"] as Array).is_empty(), "...nor after it")
		_expect(not (deck.get("hand") as Array).has(claw), "The Devour button eats Claw Back")
		_expect_eq(player.hp - hp, 3, "...heals 3")
		_expect_eq(_applied_line(player), "Nothing", "...yields nothing")
		_expect(player.devoured_cards.is_empty(), "...and counts nothing on the Devoured list")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.energy = 3
	return player

# `card` devoured by Take In's effect, through a bare context.
func _devour(player: Combatant, card: CardData, deck: Deck = null) -> void:
	if deck == null:
		deck = Deck.new()
		deck.hand.append(card)
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.deck = deck
	ctx.devour_choice = card
	var take_in: CardData = load(CARD_PATH)
	_resolver.resolve_card(take_in, ctx)

# What the player holds of Teeth and Marrow, in the line's words, "|"
# between; "Nothing" for neither.
func _applied_line(player: Combatant) -> String:
	var parts: Array[String] = []
	var teeth: Status = Status.find_in(player.statuses, load(TEETH_PATH))
	if teeth != null:
		parts.append("+%d damage this combat" % Status.attack_bonus(player.statuses, false))
	var marrow: Status = Status.find_in(player.statuses, load(MARROW_PATH))
	if marrow != null:
		parts.append("+%d Block each turn" % Status.turn_start_block(player.statuses))
	if parts.is_empty():
		return "Nothing"
	return "|".join(parts)

# The HP `path` takes off a fresh 200-HP enemy, `earlier` of its tag
# played before it this turn (Lash's repeats).
func _damage_of(path: String, player: Combatant, earlier: int) -> int:
	var enemy := Combatant.new(ENEMY_HP)
	var ctx := EffectContext.new()
	ctx.player = player
	var enemies: Array[Combatant] = [enemy]
	ctx.enemies = enemies
	ctx.target = enemy
	ctx.tagged_plays_before_this = {LASH_TAG: earlier}
	_resolver.resolve_card(load(path), ctx)
	return ENEMY_HP - enemy.hp

# Listens for the Devour keyword's sound: whether it plays as `card` is
# played (card_played) and at each keyword_devoured - read after the
# overlay has answered each, as it connected first. The player stopped
# first, so a sound before this can't read as one now.
func _listen_keyword_sound(controller: Node, card: CardData) -> Dictionary:
	var sound: AudioStreamPlayer = _overlay().get("_devour_keyword_player")
	if sound != null:
		sound.stop()
	var at_play: Array[bool] = []
	var at_devour: Array[bool] = []
	var heard: Dictionary = {"at_play": at_play, "at_devour": at_devour}
	heard["on_play"] = func(played: CardData, _target: Node) -> void:
		if played == card:
			at_play.append(_keyword_sound_playing())
	heard["on_devour"] = func(_eaten: CardData) -> void:
		at_devour.append(_keyword_sound_playing())
	controller.connect("card_played", heard["on_play"])
	controller.connect("keyword_devoured", heard["on_devour"])
	return heard

func _stop_listening(controller: Node, heard: Dictionary) -> void:
	controller.disconnect("card_played", heard["on_play"])
	controller.disconnect("keyword_devoured", heard["on_devour"])

func _keyword_sound_playing() -> bool:
	var overlay: Node = _overlay()
	var sound: AudioStreamPlayer = overlay.get("_devour_keyword_player") if overlay != null else null
	return sound != null and sound.playing

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
	while layer.get_child_count() > 0 and bool((layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
	if layer.get_child_count() == 0:
		_fail("no fight started")
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = 999
		enemy.hp = 999
	var player: Combatant = controller.get("player")
	player.max_hp = 999
	player.hp = 900
	player.energy = 3
	controller.get("deck").call("discard_hand")
	await process_frame
	return controller

func _overlay() -> Node:
	if _field == null or not is_instance_valid(_field):
		return null
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

func _prompt_text() -> String:
	var overlay: Node = _overlay()
	var prompt := overlay.get_node_or_null("ChoicePrompt") as Label if overlay != null else null
	return prompt.text if prompt != null and prompt.visible else ""

func _deal(controller: Node, path: String) -> CardData:
	var deck: Object = controller.get("deck")
	var card: CardData = (load(path) as CardData).duplicate()
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
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
