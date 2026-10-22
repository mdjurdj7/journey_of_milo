extends SceneTree

# Headless probe for Twice Over - 0 Energy, Uncommon Skill, Spent, TOLL:
# "Spend 7 Toll. Copy another card in hand." Blocked under 7 Toll, and
# with no other card it may copy - never a Twice Over. The picker takes
# exactly one of the cards it may, the rest faded, and plays at the pick.
# The copy (Deck.add_copy(), CardData.battle_copy) is the same card,
# tempered or not; it costs its Energy, is Spent when played, can be
# Second Swing's last Attack, and is gone at the end of the turn unplayed
# - Keep or not - in no pile, never in the run's deck (a Consumed copy
# included). Its face reads "COPY ·" and carries the hatched band. The
# spend hurries a Sentence. Twice Over+ spends 5.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/countersign_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Deck cases drive a bare Deck; fight cases load the real region scene and
# fight floor 1's Sputter through RegionField's contact handler, playing
# real cards through BattleController. Untyped against anything that names
# the RunState autoload.

const CASES := 10
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_PATH := "res://cards/data/countersign.tres"
const TEMPERED_PATH := "res://cards/tempered/countersign_tempered.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const SLASH_PLUS_PATH := "res://cards/tempered/slash_tempered.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const SAMPHIRE_PATH := "res://cards/neutral/samphire.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const BATTLE_CONTROLLER_PATH := "res://battle/battle_controller.gd"
const ENEMY_HP := 999
const ESCAPE := 2
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
	_toll = (load(CARD_PATH) as CardData).effects[0].toll_cost

	_check_data()
	_check_deck_copy()
	_check_targets()
	await _check_copy_and_play()
	await _check_vanishes_with_keep()
	await _check_never_in_run_deck()
	await _check_consumed_copy()
	await _check_blocked()
	await _check_sentence()
	await _check_face()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("countersign_probe: PASSED")
		quit(0)
	else:
		print("countersign_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq([card.card_name, card.card_type, card.rarity, card.removal_scope, card.offer, card.card_class], ["Twice Over", CardData.CardType.SKILL, CardData.CardRarity.UNCOMMON, CardData.RemovalScope.SPENT, CardData.OfferScope.REWARDABLE, &"wanderer"], "Twice Over: an Uncommon Skill, Spent, rewardable, the Wanderer's")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[1].effect_type == CardEffect.EffectType.COPY_HAND_CARD, "...SPEND_TOLL, then COPY_HAND_CARD")
	_expect_eq(card.description, "Copy another card in hand.\nSpent.", "...its text, numbers from data")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art != null and card.art.resource_path == "res://cards/art/Wanderer/Twice Over.png", "...with its art")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Twice Over+")
	_expect_eq([tempered.card_name, tempered.removal_scope, tempered.description], ["Twice Over+", CardData.RemovalScope.SPENT, card.description], "Twice Over+: the same text, Spent")
	_completed += 1

# A copy into the hand: a new card, the same in all else, marked; with a
# full hand, none. Discarded, it vanishes - no pile; Keep doesn't hold it.
# Played, it's Spent.
func _check_deck_copy() -> void:
	var slash: CardData = load(SLASH_PLUS_PATH)
	var deck := Deck.new([])
	deck.hand.append(slash)
	var copy: CardData = deck.add_copy(slash)
	_expect(copy != null and copy != slash and copy.battle_copy and not slash.battle_copy, "A copy: a card of its own, marked, the original not")
	_expect(copy != null and copy.card_name == "Slash+" and copy.effects == slash.effects and copy.cost == slash.cost, "...the same card, tempered state and all")
	_expect(deck.hand.has(copy), "...in the hand")
	var controller_script := load(BATTLE_CONTROLLER_PATH) as GDScript
	_expect(bool(controller_script.call("exhausts_on_play", copy)), "...Spent when played")
	deck.grant_keep(copy)
	deck.discard_hand()
	_expect(not deck.hand.has(copy) and not deck.discard_pile.has(copy) and not deck.draw_pile.has(copy), "The turn ends: the copy is gone, Keep or not, in no pile")
	_expect(deck.discard_pile.has(slash), "...the original discarded as ever")
	var full := Deck.new([])
	for i in full.hand_size:
		full.hand.append(load(BRACE_PATH))
	_expect(full.add_copy(load(BRACE_PATH)) == null and full.draw_pile.is_empty(), "A full hand: no copy, nothing in the draw pile")
	_completed += 1

func _check_targets() -> void:
	var card: CardData = (load(CARD_PATH) as CardData).duplicate()
	var other: CardData = (load(CARD_PATH) as CardData).duplicate()
	var plus: CardData = (load(TEMPERED_PATH) as CardData).duplicate()
	var slash: CardData = (load(SLASH_PATH) as CardData).duplicate()
	var hand: Array[CardData] = [card, other, plus, slash]
	_expect_eq(EffectResolver.copy_targets(card, hand), [slash] as Array[CardData], "It may copy Slash - not itself, nor any Twice Over")
	var only: Array[CardData] = [card, other]
	_expect(EffectResolver.copy_targets(card, only).is_empty(), "...with only other Twice Overs, nothing")
	_completed += 1

# --- Fights ---

# On 7 Toll with Slash and another Twice Over: the picker offers Slash
# alone; picked, it plays - 7 Toll spent, Twice Over Spent, a Slash copy
# in the hand. The copy costs its 1 Energy, lands, is Spent, and is the
# last Attack.
func _check_copy_and_play() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Object = controller.get("deck")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var spare: CardData = await _deal(controller, CARD_PATH)
		var card: CardData = await _deal(controller, CARD_PATH)
		controller.call("request_play", _view(controller, card))
		_expect(_prompt_text().begins_with("COPY"), "The picker: %s" % _prompt_text())
		controller.call("toggle_choice", _view(controller, spare))
		_expect(not _view(controller, spare).is_marked(), "...the other Twice Over can't be picked")
		controller.call("toggle_choice", _view(controller, slash))
		await ProbePlay.settle(self, controller)
		_expect_eq(player.toll, 0, "Picked: 7 Toll spent, at once")
		_expect((deck.get("exhaust_pile") as Array).has(card), "...Twice Over Spent")
		var copy: CardData = _copy_in_hand(deck)
		_expect(copy != null and copy.card_name == "Slash", "...a Slash copy in the hand")
		if copy != null:
			var energy: int = player.energy
			var enemy: Combatant = (controller.get("_combatants") as Dictionary).values()[0]
			var hp: int = enemy.hp
			controller.call("request_play", _view(controller, copy))
			controller.call("confirm_target", (controller.get("_combatants") as Dictionary).keys()[0])
			await ProbePlay.settle(self, controller)
			_expect_eq(energy - player.energy, 1, "The copy costs Slash's 1 Energy")
			_expect(enemy.hp < hp, "...lands")
			_expect((deck.get("exhaust_pile") as Array).has(copy) and not (deck.get("discard_pile") as Array).has(copy), "...and is Spent")
			_expect(player.last_attack == copy, "...the last Attack, for Second Swing")
	await _teardown()
	_completed += 1

# A copy given Keep still goes at the end of the turn.
func _check_vanishes_with_keep() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Object = controller.get("deck")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _countersign(controller, await _deal(controller, CARD_PATH), slash)
		var copy: CardData = _copy_in_hand(deck)
		deck.call("grant_keep", copy)
		await _end_turn(controller)
		var everywhere: Array = []
		for pile: String in ["hand", "draw_pile", "discard_pile", "exhaust_pile"]:
			everywhere.append_array(deck.get(pile))
		_expect(copy != null and not everywhere.has(copy), "The copy, kept, is gone at the turn's end - in no pile")
	await _teardown()
	_completed += 1

# The run's deck after a fight with a copy made and played: unchanged.
func _check_never_in_run_deck() -> void:
	var controller: Node = await _start_fight()
	var before: int = (_run_state.get("deck") as Array).size()
	var copy: CardData = null
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _countersign(controller, await _deal(controller, CARD_PATH), slash)
		copy = _copy_in_hand(controller.get("deck"))
		_overlay().call("_finish_battle", ESCAPE)
		await process_frame
	var run_deck: Array = _run_state.get("deck")
	_expect_eq(run_deck.size(), before, "After the fight the run's deck is the size it was")
	_expect(copy != null and not run_deck.has(copy), "...with no copy in it")
	await _teardown()
	_completed += 1

# A copy of a Consumed card (Samphire), played: Spent, and the run keeps
# its Samphire.
func _check_consumed_copy() -> void:
	var controller: Node = await _start_fight()
	var samphire: CardData = null
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Object = controller.get("deck")
		player.toll = _toll
		samphire = _run_state.call("add_card", load(SAMPHIRE_PATH))
		deck.call("add", samphire)
		await process_frame
		await _countersign(controller, await _deal(controller, CARD_PATH), samphire)
		var copy: CardData = _copy_in_hand(deck)
		if copy != null:
			controller.call("request_play", _view(controller, copy))
			await ProbePlay.settle(self, controller)
		_overlay().call("_finish_battle", ESCAPE)
		await process_frame
	_expect(samphire != null and (_run_state.get("deck") as Array).has(samphire), "A played copy of Samphire leaves the run's Samphire where it is")
	await _teardown()
	_completed += 1

# 6 Toll: blocked. 7, but only another Twice Over in hand: nothing it may
# copy - not playable, faded.
func _check_blocked() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll - 1
		await _deal(controller, SLASH_PATH)
		var card: CardData = await _deal(controller, CARD_PATH)
		_expect(not bool(controller.call("_is_playable", card)), "On 6 Toll Twice Over can't be played")
		controller.get("deck").call("discard_hand")
		await process_frame
		player.toll = _toll
		await _deal(controller, CARD_PATH)
		var lone: CardData = await _deal(controller, CARD_PATH)
		_expect(not bool(controller.call("_is_playable", lone)), "On 7 with only a Twice Over beside it: nothing to copy, not playable")
		_expect(not controller.get("_hand_container").call("_can_play", lone, player.energy), "...the hand fades it")
	await _teardown()
	_completed += 1

func _check_sentence() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var enemy: Combatant = (controller.get("_combatants") as Dictionary).values()[0]
		Status.apply_to(enemy.statuses, load(SENTENCE_STATUS_PATH))
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _countersign(controller, await _deal(controller, CARD_PATH), slash)
		var sentence: Status = Status.find_in(enemy.statuses, load(SENTENCE_STATUS_PATH))
		_expect(sentence != null and sentence.turns_remaining == 2, "Twice Over's spend hurries a Sentence: 3 -> 2")
	await _teardown()
	_completed += 1

# The copy's face: "COPY ·" ahead of its type, the word answering the
# hover as Copy; the original's untouched.
func _check_face() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _countersign(controller, await _deal(controller, CARD_PATH), slash)
		var copy: CardData = _copy_in_hand(controller.get("deck"))
		var view: CardView = _view(controller, copy) if copy != null else null
		_expect(view != null and view.type_label.text == "COPY · STRIKE", "The copy reads %s" % (view.type_label.text if view != null else "?"))
		_expect_eq(_view(controller, slash).type_label.text, "STRIKE", "...the original STRIKE")
		if view != null:
			var font: Font = view.type_label.get_theme_font("font")
			var whole: float = font.get_string_size(view.type_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, view.type_label_font_size_px).x
			var at: Vector2 = view.type_label.position + Vector2((view.type_label.size.x - whole) / 2.0 + 4.0, view.type_label.size.y / 2.0)
			_expect_eq(view.keyword_at(at), "Copy", "...its COPY answering the hover as Copy")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _copy_in_hand(deck: Object) -> CardData:
	for card: CardData in deck.get("hand"):
		if card.battle_copy:
			return card
	return null

func _countersign(controller: Node, card: CardData, target: CardData) -> void:
	controller.call("request_play", _view(controller, card))
	controller.call("toggle_choice", _view(controller, target))
	await ProbePlay.settle(self, controller)

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

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

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

func _end_turn(controller: Node) -> void:
	var turn: int = int(controller.get("_player_turn"))
	controller.call("end_turn")
	await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and ProbePlay.is_settled(controller), 20.0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
