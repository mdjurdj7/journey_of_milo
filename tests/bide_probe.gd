extends SceneTree

# Headless probe for Bide - SET_ASIDE and the choice behind it: playing it
# opens a choice of up to 2 other hand cards (fewer when the hand holds
# fewer, 0 always allowed); confirmed, the chosen leave the hand for the
# deck's set-aside pile, Bide draws 1 and goes to the discard; at the
# start of the next turn they come back after the normal draw, which is
# unchanged. Cancelled, nothing is spent. Next-card discounts (Leverage,
# Collateral) wait through it. The readout names the waiting cards.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/bide_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fight cases load the real region scene and start fights through
# RegionField's contact handler, as collateral_probe does, then drive
# BattleController's own request_play() / toggle_choice() / confirm_
# choice() / cancel_choice() / end_turn(). Each case discards the hand and
# deals itself fresh copies of the cards it needs. Untyped against
# anything that names the RunState autoload.

const CASES := 12
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BIDE_PATH := "res://cards/data/bide.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Bide.png"
const LEVERAGE_STATUS_PATH := "res://battle/rules/statuses/leverage.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const ENEMY_HP := 999
const TURN_DRAW := 5
const SAFETY_SECONDS := 400.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	_check_reshuffle_leaves_it()
	await _check_alone()
	await _check_choose_two()
	await _check_cap()
	await _check_cancel()
	await _check_zero()
	await _check_one_other()
	await _check_return_next_turn()
	await _check_hand_full_on_return()
	await _check_discounts_wait()
	await _check_fight_ends_first()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("bide_probe: PASSED")
		quit(0)
	else:
		print("bide_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var bide := load(BIDE_PATH) as CardData
	_expect_eq(bide.card_name, "Bide", "The card is named Bide")
	_expect_eq(bide.cost, 0, "...costs 0")
	_expect_eq(bide.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(bide.rarity, CardData.CardRarity.COMMON, "...is Common")
	_expect_eq(bide.target_type, CardData.TargetType.SELF, "...targets the player")
	_expect_eq(bide.removal_scope, CardData.RemovalScope.NONE, "...is not Spent")
	_expect_eq(bide.effects.size(), 2, "...two effects")
	_expect_eq(bide.effects[0].effect_type, CardEffect.EffectType.SET_ASIDE, "...SET_ASIDE first")
	_expect_eq(bide.effects[0].value, 2, "...of 2")
	_expect_eq(bide.effects[1].effect_type, CardEffect.EffectType.DRAW, "...then DRAW")
	_expect_eq(bide.effects[1].value, 1, "...of 1")
	_expect(bide.art != null and bide.art.resource_path == ART_PATH, "...and carries its art")
	var in_pool: bool = false
	for card: CardData in (load(POOL_PATH) as RewardPool).entries:
		if card == bide:
			in_pool = true
	_expect(in_pool, "...and is in the Wanderer reward pool")
	_completed += 1

# The set-aside pile is outside every pile a draw or a reshuffle reads.
func _check_reshuffle_leaves_it() -> void:
	var slash := (load(SLASH_PATH) as CardData).duplicate() as CardData
	var brace := (load(BRACE_PATH) as CardData).duplicate() as CardData
	var others: Array[CardData] = []
	for i in 4:
		others.append((load(SLASH_PATH) as CardData).duplicate() as CardData)
	var deck := Deck.new(others)
	deck.hand = [slash, brace] as Array[CardData]
	deck.set_aside([slash, brace] as Array[CardData])
	_expect_eq(deck.hand.size(), 0, "Set aside: the hand gives them up")
	deck.discard_pile = deck.draw_pile
	deck.draw_pile = [] as Array[CardData]
	deck.draw(4)
	_expect(not deck.hand.has(slash) and not deck.hand.has(brace) and not deck.draw_pile.has(slash), "A reshuffle and draw never reach the set-aside cards")
	_expect_eq(deck.set_aside_pile, [slash, brace] as Array[CardData], "...they wait in the set-aside pile")
	_completed += 1

# --- Fights ---

# Bide alone: nothing to choose, so it just plays - draws 1, sets aside
# nothing, and goes to the discard.
func _check_alone() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		_expect(not bool(controller.call("is_choosing")), "Bide alone opens no choice")
		await _settle(controller)
		_expect_eq((deck.get("hand") as Array).size(), 1, "...it draws 1")
		_expect_eq((deck.get("set_aside_pile") as Array).size(), 0, "...sets aside nothing")
		_expect((deck.get("discard_pile") as Array).has(bide), "...and goes to the discard")
		_expect_eq((controller.get("player") as Combatant).energy, 3, "...for 0 Energy")
	await _teardown()
	_completed += 1

# Two chosen from three: they leave the hand, Bide draws 1 and is
# discarded, and the readout names them.
func _check_choose_two() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var brace: CardData = await _deal(controller, BRACE_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		_expect(bool(controller.call("is_choosing")), "Bide with three others opens the choice")
		_expect_eq(int(controller.get("_choice_cap")), 2, "...capped at 2")
		var slash_view: CardView = _view(controller, slash)
		controller.call("toggle_choice", slash_view)
		controller.call("toggle_choice", _view(controller, brace))
		_expect(slash_view.is_marked(), "A clicked card is marked")
		controller.call("confirm_choice")
		await _settle(controller)
		var hand: Array = deck.get("hand")
		_expect_eq(deck.get("set_aside_pile"), [slash, brace], "Confirmed: Slash and Brace are set aside")
		_expect(hand.has(reckoning) and not hand.has(slash) and not hand.has(brace), "...Reckoning stays in hand")
		_expect_eq(hand.size(), 2, "...beside the 1 Bide drew")
		_expect((deck.get("discard_pile") as Array).has(bide), "Bide goes to the discard")
		_expect_eq((controller.get("player") as Combatant).energy, 3, "...for 0 Energy")
		var line: Dictionary = _readout_line(controller, "Set aside")
		_expect_eq(line.get("text", ""), "Set aside 2", "The readout reads Set aside 2")
		_expect_eq(line.get("rules", ""), "Back in your hand at the start of your next turn: Slash, Brace.", "...and its reveal names them")
	await _teardown()
	_completed += 1

# A third mark past the cap does nothing; unmarking frees a slot.
func _check_cap() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var a: CardData = await _deal(controller, SLASH_PATH)
		var b: CardData = await _deal(controller, BRACE_PATH)
		var c: CardData = await _deal(controller, RECKONING_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		controller.call("toggle_choice", _view(controller, a))
		controller.call("toggle_choice", _view(controller, b))
		controller.call("toggle_choice", _view(controller, c))
		_expect(not _view(controller, c).is_marked(), "A third mark past the cap of 2 does nothing")
		_expect_eq((controller.get("_choice_marked") as Array).size(), 2, "...two stay marked")
		controller.call("toggle_choice", _view(controller, b))
		controller.call("toggle_choice", _view(controller, c))
		_expect(_view(controller, c).is_marked() and not _view(controller, b).is_marked(), "Unmarking one frees the slot")
		controller.call("cancel_choice")
		await _settle(controller)
	await _teardown()
	_completed += 1

# Cancelled: nothing spent, nothing set aside, the marks come off and
# Bide is back in the hand; End Turn comes back.
func _check_cancel() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _deal(controller, BRACE_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		controller.call("toggle_choice", _view(controller, slash))
		controller.call("cancel_choice")
		await create_timer(0.8).timeout
		_expect(not bool(controller.call("is_choosing")), "Cancelled: the choice closes")
		_expect((deck.get("hand") as Array).has(bide), "...Bide stays in hand")
		_expect_eq((deck.get("hand") as Array).size(), 3, "...with both others")
		_expect_eq((deck.get("set_aside_pile") as Array).size(), 0, "...nothing set aside")
		_expect(not _view(controller, slash).is_marked(), "...the mark comes off")
		_expect_eq((controller.get("player") as Combatant).energy, 3, "...nothing spent")
		_expect(not bool(_overlay().get("_card_armed")), "...and End Turn is back")
	await _teardown()
	_completed += 1

# Confirmed with nothing marked: Bide just draws 1.
func _check_zero() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		await _deal(controller, SLASH_PATH)
		await _deal(controller, BRACE_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		controller.call("confirm_choice")
		await _settle(controller)
		_expect_eq((deck.get("set_aside_pile") as Array).size(), 0, "Set aside 0: nothing set aside")
		_expect_eq((deck.get("hand") as Array).size(), 3, "...both others stay, plus the 1 drawn")
		_expect((deck.get("discard_pile") as Array).has(bide), "...and Bide goes to the discard")
		_expect(_readout_line(controller, "Set aside").is_empty(), "...and no readout line")
	await _teardown()
	_completed += 1

# One other card: the cap shrinks to 1, and it is still a choice.
func _check_one_other() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		controller.call("request_play", _view(controller, bide))
		_expect(bool(controller.call("is_choosing")), "One other card: the choice still opens")
		_expect_eq(int(controller.get("_choice_cap")), 1, "...capped at 1")
		controller.call("toggle_choice", _view(controller, slash))
		controller.call("confirm_choice")
		await _settle(controller)
		_expect_eq(deck.get("set_aside_pile"), [slash], "...and Slash is set aside")
	await _teardown()
	_completed += 1

# Next turn: the normal draw is 5, as ever, and the two come back after it.
func _check_return_next_turn() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var brace: CardData = await _deal(controller, BRACE_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		await _bide(controller, bide, [slash, brace])
		var drawn: Array = []
		deck.connect("drawn", func(card: CardData) -> void: drawn.append(card))
		await _end_turn(controller)
		var hand: Array = deck.get("hand")
		_expect_eq(drawn.size(), TURN_DRAW, "Next turn draws %d, as ever" % TURN_DRAW)
		_expect(hand.has(slash) and hand.has(brace), "...and Slash and Brace are back in hand")
		_expect_eq(hand.size(), TURN_DRAW + 2, "...beside the %d drawn" % TURN_DRAW)
		_expect(not drawn.has(slash) and not drawn.has(brace), "...returned, not drawn")
		_expect_eq((deck.get("set_aside_pile") as Array).size(), 0, "...the set-aside pile empty")
		_expect(_readout_line(controller, "Set aside").is_empty(), "...and the readout line gone")
	await _teardown()
	_completed += 1

# A hand already at its limit when they come back: what doesn't fit goes
# to the discard, never lost.
func _check_hand_full_on_return() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var brace: CardData = await _deal(controller, BRACE_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		await _bide(controller, bide, [slash, brace])
		deck.set("hand_size", TURN_DRAW + 1)
		await _end_turn(controller)
		var hand: Array = deck.get("hand")
		_expect_eq(hand.size(), TURN_DRAW + 1, "A hand limit of %d: 5 drawn, 1 back" % (TURN_DRAW + 1))
		_expect(hand.has(slash), "...Slash, set aside first, back in hand")
		_expect((deck.get("discard_pile") as Array).has(brace), "...Brace, past the limit, to the discard")
		_expect_eq((deck.get("set_aside_pile") as Array).size(), 0, "...and none left waiting")
	await _teardown()
	_completed += 1

# Leverage and Collateral wait through Bide (it costs 0) and through the
# set-aside, for the next card that costs something.
func _check_discounts_wait() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
		Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		await _bide(controller, bide, [slash, reckoning])
		_expect_eq(_labels(player), ["Leverage", "Collateral ×1"] as Array[String], "Bide spends neither Leverage nor Collateral")
		await _end_turn(controller)
		_expect_eq(_labels(player), ["Leverage", "Collateral ×1"] as Array[String], "...nor does a card set aside")
		_expect_eq(player.energy_cost(slash), 0, "...the returned Slash reads Leverage's 0")
		_expect_eq(player.energy_cost(reckoning), 0, "...and Reckoning, 2 less, falls under Collateral's 2")
	await _teardown()
	_completed += 1

# The fight ends with cards set aside: the run's deck is untouched - each
# fight's Deck is built fresh from it.
func _check_fight_ends_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var run_deck: Array = (_run_state.get("deck") as Array).duplicate()
		# The opening hand kept: Bide joins it rather than replacing it.
		controller.set_meta("probe_dealt", true)
		var hand: Array = (deck.get("hand") as Array).duplicate()
		var bide: CardData = await _deal(controller, BIDE_PATH)
		var chosen: Array = [hand[0], hand[1]]
		await _bide(controller, bide, chosen)
		_expect_eq((deck.get("set_aside_pile") as Array).size(), 2, "Two of the opening hand set aside")
		for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
			combatant.hp = 0
		controller.call("_check_battle_end")
		await create_timer(0.5).timeout
		_expect_eq((_run_state.get("deck") as Array), run_deck, "The fight ends: the run's deck holds every card, as before")
	await _teardown()
	_completed += 1

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
