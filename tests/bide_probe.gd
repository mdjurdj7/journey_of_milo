extends SceneTree

# Headless probe for Bide - 0 Energy, Common Skill, TOLL: "Spend 4 Toll.
# Choose up to 2 cards in your hand. They gain Keep." Blocked under 4
# Toll. The picker (up to 2 of the other hand cards, DONE) opens before
# the play; none chosen still spends the Toll (and so hurries a
# Sentence); alone in the hand it just plays. Keep (Deck.kept): a kept
# card stays in the hand at the end of each turn until it leaves the
# hand by any route - played, Spent, devoured - and loses Keep then;
# Frayed Cord's pick keeps on top of it; the hand cap stops the draw; a
# new fight's Deck starts with none. A kept face reads "KEEP ·" ahead of
# its type, answering the hover as the Keep keyword. Bide+ keeps 3.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/bide_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Deck cases drive a bare Deck; fight cases load the real region scene and
# fight floor 1's Sputter through RegionField's contact handler, playing
# real cards through BattleController.request_play() / toggle_choice() /
# confirm_choice() / end_turn(). Untyped against anything that names the
# RunState autoload.

const CASES := 12
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BIDE_PATH := "res://cards/data/bide.tres"
const TEMPERED_PATH := "res://cards/tempered/bide_tempered.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Bide.png"
const ENEMY_HP := 999
const TURN_DRAW := 5
const SAFETY_SECONDS := 400.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _toll: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_toll = (load(BIDE_PATH) as CardData).effects[0].toll_cost

	_check_data()
	_check_deck_keep()
	_check_keep_lost_any_route()
	_check_frayed_cord_on_top()
	_check_hand_cap()
	await _check_choose_two()
	await _check_kept_through_turns()
	await _check_played_loses_keep()
	await _check_zero_counts()
	await _check_alone()
	await _check_cancel()
	await _check_blocked()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("bide_probe: PASSED")
		quit(0)
	else:
		print("bide_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(BIDE_PATH)
	_expect_eq([card.card_name, card.cost, card.card_type, card.rarity, card.removal_scope], ["Bide", 0, CardData.CardType.SKILL, CardData.CardRarity.COMMON, CardData.RemovalScope.NONE], "Bide: 0 Energy, a Common Skill, not Spent")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[0].toll_cost == 4 and card.effects[1].effect_type == CardEffect.EffectType.GRANT_KEEP and card.effects[1].value == 2, "...SPEND_TOLL 4, then GRANT_KEEP 2")
	_expect_eq(card.description, "Spend {toll_cost} Toll.\nChoose up to {keep} cards in your hand. They gain Keep.", "...its text, numbers from data")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...its art kept")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Bide+")
	_expect_eq([tempered.card_name, tempered.effects[1].value, tempered.description], ["Bide+", 3, card.description], "Bide+: up to 3, the same text")
	_expect_eq(KeywordTable.shared().definition("Keep"), "Stays in your hand at the end of each turn until played.", "The Keep keyword")
	_completed += 1

# --- The Deck ---

# Two of four kept: the end of the turn discards the other two, the kept
# stay - and stay again at the next end.
func _check_deck_keep() -> void:
	var cards: Array[CardData] = [_card(SLASH_PATH), _card(BRACE_PATH), _card(RECKONING_PATH), _card(SLASH_PATH)]
	var deck := Deck.new([])
	deck.hand.append_array(cards)
	_expect(deck.grant_keep(cards[0]) and deck.grant_keep(cards[1]), "Two hand cards gain Keep")
	_expect(not deck.grant_keep(_card(SLASH_PATH)), "...one not in the hand can't")
	deck.discard_hand()
	_expect_eq(deck.hand, [cards[0], cards[1]] as Array[CardData], "The turn ends: the kept two stay")
	_expect_eq(deck.discard_pile.size(), 2, "...the other two discarded")
	deck.discard_hand()
	_expect_eq(deck.hand.size(), 2, "...and they stay again at the next end")
	var next := Deck.new(cards)
	_expect(next.kept.is_empty(), "A new fight's Deck starts with none kept")
	_completed += 1

# Played, Spent or devoured (exhaust), discarded: Keep goes with the card.
func _check_keep_lost_any_route() -> void:
	var cards: Array[CardData] = [_card(SLASH_PATH), _card(BRACE_PATH), _card(RECKONING_PATH)]
	var deck := Deck.new([])
	deck.hand.append_array(cards)
	for card in cards:
		deck.grant_keep(card)
	deck.begin_play(cards[0])
	_expect(not deck.has_keep(cards[0]), "Played: Keep gone")
	deck.exhaust(cards[1])
	_expect(not deck.has_keep(cards[1]), "Spent from the hand (Devour): Keep gone")
	deck.discard(cards[2])
	_expect(not deck.has_keep(cards[2]), "Discarded: Keep gone")
	_completed += 1

# Frayed Cord keeps one more on top of a kept card, not counted against it.
func _check_frayed_cord_on_top() -> void:
	var cards: Array[CardData] = [_card(SLASH_PATH), _card(BRACE_PATH), _card(RECKONING_PATH)]
	var deck := Deck.new([])
	deck.hand.append_array(cards)
	deck.grant_keep(cards[0])
	deck.discard_hand([cards[1]] as Array[CardData])
	_expect_eq(deck.hand, [cards[0], cards[1]] as Array[CardData], "Keep and Frayed Cord's pick both stay")
	_completed += 1

# Eight kept and a draw of 5: the hand stops at 10, the rest waiting in
# the draw pile.
func _check_hand_cap() -> void:
	var pile: Array[CardData] = []
	for i in 10:
		pile.append(_card(SLASH_PATH))
	var deck := Deck.new(pile)
	for i in 8:
		var card: CardData = _card(BRACE_PATH)
		deck.hand.append(card)
		deck.grant_keep(card)
	deck.discard_hand()
	deck.draw(TURN_DRAW)
	_expect_eq(deck.hand.size(), deck.hand_size, "Eight kept, a draw of 5: the hand stops at %d" % deck.hand_size)
	_expect_eq(deck.draw_pile.size(), 8, "...the rest left in the draw pile")
	_completed += 1

# --- Fights ---

# Bide on 4 Toll with Slash, Brace and Reckoning: the picker asks for up to
# 2; Slash and Brace chosen - Toll spent, both kept, their faces reading
# KEEP and answering the Keep keyword.
func _check_choose_two() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var brace: CardData = await _deal(controller, BRACE_PATH)
		await _deal(controller, RECKONING_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		_expect(_prompt_text().begins_with("KEEP"), "The picker opens: %s" % _prompt_text())
		controller.call("toggle_choice", _view(controller, slash))
		controller.call("toggle_choice", _view(controller, brace))
		controller.call("confirm_choice")
		await _settle(controller)
		var deck: Object = controller.get("deck")
		_expect_eq(player.toll, 0, "Bide spends 4")
		_expect(bool(deck.call("has_keep", slash)) and bool(deck.call("has_keep", brace)), "...Slash and Brace kept")
		var view: CardView = _view(controller, slash)
		_expect(view != null and view.is_kept() and view.type_label.text.begins_with("KEEP · "), "...Slash's face reads %s" % (view.type_label.text if view != null else "?"))
		if view != null:
			var at: Vector2 = view.type_label.position + Vector2((view.type_label.size.x - view.type_label.get_theme_font("font").get_string_size(view.type_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, view.type_label_font_size_px).x) / 2.0 + 4.0, view.type_label.size.y / 2.0)
			_expect_eq(view.keyword_at(at), "Keep", "...its KEEP answering the Keep keyword")
	await _teardown()
	_completed += 1

# Kept through two turn ends: still in the hand, the turn's draw added.
func _check_kept_through_turns() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		await _bide(controller, await _deal(controller, BIDE_PATH), [slash])
		var deck: Object = controller.get("deck")
		await _end_turn(controller)
		var hand: Array = deck.get("hand")
		_expect(hand.has(slash) and not hand.has(reckoning), "The turn ends: Slash kept, Reckoning discarded")
		_expect_eq(hand.size(), 1 + TURN_DRAW, "...and the turn's draw added")
		await _end_turn(controller)
		_expect((deck.get("hand") as Array).has(slash), "...still there after another turn")
	await _teardown()
	_completed += 1

func _check_played_loses_keep() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _bide(controller, await _deal(controller, BIDE_PATH), [slash])
		var deck: Object = controller.get("deck")
		controller.call("request_play", _view(controller, slash))
		controller.call("confirm_target", (controller.get("_combatants") as Dictionary).keys()[0])
		await _settle(controller)
		_expect(not bool(deck.call("has_keep", slash)), "Played, Slash loses Keep")
		await _end_turn(controller)
		_expect(not (deck.get("hand") as Array).has(slash), "...and isn't held at the turn's end")
	await _teardown()
	_completed += 1

# None chosen: the Toll is spent all the same, and a Sentence hurried.
func _check_zero_counts() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var enemy: Combatant = (controller.get("_combatants") as Dictionary).values()[0]
		Status.apply_to(enemy.statuses, load(SENTENCE_STATUS_PATH))
		player.toll = _toll
		await _deal(controller, SLASH_PATH)
		await _bide(controller, await _deal(controller, BIDE_PATH), [])
		_expect_eq(player.toll, 0, "None chosen: the 4 Toll still spent")
		var sentence: Status = Status.find_in(enemy.statuses, load(SENTENCE_STATUS_PATH))
		_expect(sentence != null and sentence.turns_remaining == 2, "...and a Sentence hurried, 3 -> 2")
	await _teardown()
	_completed += 1

func _check_alone() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		_expect_eq(_prompt_text(), "", "Alone in the hand: no picker")
		await _settle(controller)
		_expect_eq(player.toll, 0, "...it just plays, spending 4")
	await _teardown()
	_completed += 1

func _check_cancel() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		controller.call("toggle_choice", _view(controller, slash))
		controller.call("cancel_choice")
		await process_frame
		_expect_eq(player.toll, _toll, "Cancelled: nothing spent")
		_expect(not bool(controller.get("deck").call("has_keep", slash)), "...nothing kept")
		_expect(_view(controller, bide) != null, "...Bide still in the hand")
	await _teardown()
	_completed += 1

func _check_blocked() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll - 1
		await _deal(controller, SLASH_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		_expect(not bool(controller.call("_is_playable", bide)), "On 3 Toll Bide can't be played")
		_expect(not controller.get("_hand_container").call("_can_play", bide, player.energy), "...the hand fades it")
	await _teardown()
	_completed += 1

func _card(path: String) -> CardData:
	return (load(path) as CardData).duplicate()

# --- Helpers ---

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
	var overlay: Node = _overlay()
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	var player: Combatant = controller.get("player")
	player.max_hp = 999
	player.hp = 999
	(player as Combatant).energy = 3
	await process_frame
	return controller

func _overlay() -> Node:
	if _field == null or not is_instance_valid(_field):
		return null
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

# The open choice's prompt line, and its DONE (BattleOverlay's).
func _prompt_text() -> String:
	var overlay: Node = _overlay()
	var prompt := overlay.get_node_or_null("ChoicePrompt") as Label if overlay != null else null
	return prompt.text if prompt != null and prompt.visible else ""

func _done_button() -> Button:
	var overlay: Node = _overlay()
	return overlay.get_node_or_null("ChoiceDone") as Button if overlay != null else null

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand - the first
# call of a case discards the opening hand first, so each case starts
# from exactly the cards it deals.
func _deal(controller: Node, path: String) -> CardData:
	var deck: Object = controller.get("deck")
	if not bool(controller.get_meta("probe_dealt", false)):
		controller.set_meta("probe_dealt", true)
		deck.call("discard_hand")
		await process_frame
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

# Plays Bide choosing `cards` and waits for the play to resolve.
func _bide(controller: Node, bide: CardData, cards: Array) -> void:
	controller.call("request_play", _view(controller, bide))
	for card in cards:
		controller.call("toggle_choice", _view(controller, card))
	controller.call("confirm_choice")
	await _settle(controller)

# Until the play has resolved - the played card reaches the discard at its
# fade's end (Deck.settle_play()), before then - and a margin after.
func _settle(controller: Node) -> void:
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.8).timeout

func _end_turn(controller: Node) -> void:
	controller.call("end_turn")
	for i in 3000:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

func _readout_line(controller: Node, name: String) -> Dictionary:
	var overlay: Node = _overlay()
	if overlay == null:
		return {}
	overlay.call("_refresh_standing_row")
	for item: Dictionary in (overlay.get("_field_hp_bar").get("_row_items") as Array):
		if item.get("name", "") == name:
			return item
	return {}

func _labels(player: Combatant) -> Array[String]:
	var out: Array[String] = []
	for active in player.statuses:
		if active.data != null:
			out.append(active.label())
	return out

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
