extends SceneTree

# Headless probe for the order a play runs in (DESIGN.md, The played
# card): the card leaves deck.hand at its commit - not counted toward the
# hand cap of 10 while it resolves - reaches its pile at the fade's end,
# and a card with no battle_animation resolves after that, in the same
# frame; one with a clip keeps its impact delay. A draw on a card never
# draws the card itself, and a Consumed card that ends the fight still
# leaves the run deck.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/play_order_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Real fights on floor 1, started through RegionField's contact handler,
# as run_log_probe's are. Untyped against anything that names the
# RunState autoload (RegionField, BattleController, HandContainer).

const CASES := 4
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SECOND_THOUGHTS_PATH := "res://cards/neutral/second_thoughts.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const ENDURE_PATH := "res://cards/neutral/endure.tres"
# Timers fire on a frame; headless frames are short, so this is generous.
const TIME_TOLERANCE := 0.05
const SAFETY_SECONDS := 300.0

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
	await _check_draw_at_nine()
	await _check_never_draws_itself()
	await _check_timing()
	await _check_consumed_fight_end()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("play_order_probe: PASSED")
		quit(0)
	else:
		print("play_order_probe: %d FAILED" % _failures)
		quit(1)

# Second Thoughts (draw 2, no clip) played at 9 cards: the hand ends on
# 10. It is out of the hand from the commit, in the discard before the
# first card is drawn, and never back in the hand's row.
func _check_draw_at_nine() -> void:
	var controller: Node = await _open_fight()
	if controller == null:
		_completed += 1
		return
	var deck: Deck = controller.get("deck")
	await _empty_hand(controller)
	var played: CardData = null
	for i in 9:
		var card: CardData = await _deal(controller, SECOND_THOUGHTS_PATH if i == 4 else SLASH_PATH)
		if i == 4:
			played = card
	deck.draw_pile.append((load(ENDURE_PATH) as CardData).duplicate())
	deck.draw_pile.append((load(ENDURE_PATH) as CardData).duplicate())
	_expect_eq(deck.hand.size(), 9, "Nine cards in hand, Second Thoughts among them")
	var at_first_draw: Array = []
	var on_first_draw := func(_card: CardData) -> void:
		if at_first_draw.is_empty():
			at_first_draw.append([deck.discard_pile.has(played), deck.hand.has(played), _has_view(controller, played)])
	deck.drawn.connect(on_first_draw, CONNECT_ONE_SHOT)
	_set_energy(controller, 3)
	controller.call("request_play", _view(controller, played))
	_expect(not deck.hand.has(played), "At the commit Second Thoughts is out of the hand")
	_expect(not deck.discard_pile.has(played), "...and in no pile yet")
	_expect(not _has_view(controller, played), "...and has no slot in the row")
	await _settle(controller)
	_expect_eq(deck.hand.size(), 10, "The hand ends on 10 (both cards drawn)")
	_expect(not at_first_draw.is_empty(), "Something was drawn")
	if not at_first_draw.is_empty():
		var seen: Array = at_first_draw[0]
		_expect(bool(seen[0]), "At the first draw Second Thoughts is in the discard")
		_expect(not bool(seen[1]) and not bool(seen[2]), "...and not in the hand, nor its row")
	_expect(deck.discard_pile.has(played), "Second Thoughts stays in the discard")
	_expect(not _has_view(controller, played), "...never back in the hand's row")
	await _teardown()
	_completed += 1

# A draw card on an empty draw pile: the reshuffle takes the rest of the
# discard and leaves the card being played - it never draws itself.
func _check_never_draws_itself() -> void:
	var controller: Node = await _open_fight()
	if controller == null:
		_completed += 1
		return
	var deck: Deck = controller.get("deck")
	await _empty_hand(controller)
	var played: CardData = await _deal(controller, SECOND_THOUGHTS_PATH)
	var other: CardData = (load(ENDURE_PATH) as CardData).duplicate()
	deck.draw_pile.clear()
	deck.discard_pile.clear()
	deck.discard_pile.append(other)
	_set_energy(controller, 3)
	controller.call("request_play", _view(controller, played))
	await _settle(controller)
	_expect(deck.hand.has(other), "With the draw pile empty it draws the discard's other card")
	_expect(not deck.hand.has(played), "...never itself")
	_expect_eq(deck.hand.size(), 1, "...and nothing else (the hand holds 1)")
	_expect(deck.discard_pile.has(played), "...staying in the discard")
	_expect(deck.draw_pile.is_empty(), "...the draw pile empty again")
	_expect(deck.playing == null, "The play is over (Deck.end_play())")
	await _teardown()
	_completed += 1

# Second Thoughts (no clip) reaches the discard and resolves at the fade's
# end, the discard first; Slash (a clip) reaches the discard at the fade's
# end and still hits at its own impact delay from the commit.
func _check_timing() -> void:
	var controller: Node = await _open_fight()
	if controller == null:
		_completed += 1
		return
	var deck: Deck = controller.get("deck")
	var fade: float = float(controller.get("_hand_container").get("play_fade_duration"))
	await _empty_hand(controller)
	var thoughts: CardData = await _deal(controller, SECOND_THOUGHTS_PATH)
	var slash: CardData = await _deal(controller, SLASH_PATH)
	for i in 4:
		deck.draw_pile.append((load(ENDURE_PATH) as CardData).duplicate())
	_set_energy(controller, 3)
	var events: Array = []
	var start: Array = [Time.get_ticks_usec()]
	deck.discarded.connect(func(card: CardData) -> void:
		events.append(["discarded", card, _since(start[0])]))
	controller.connect("card_impact", func(card: CardData) -> void:
		events.append(["impact", card, _since(start[0]), deck.discard_pile.has(card)]))
	start[0] = Time.get_ticks_usec()
	controller.call("request_play", _view(controller, thoughts))
	await _settle(controller)
	var discarded: Array = _event(events, "discarded", thoughts)
	var impact: Array = _event(events, "impact", thoughts)
	_expect(not discarded.is_empty() and absf(float(discarded[2]) - fade) <= TIME_TOLERANCE, "Second Thoughts reaches the discard at the fade's end (%.3f s, fade %.2f)" % [float(discarded[2]) if not discarded.is_empty() else -1.0, fade])
	_expect(not impact.is_empty() and absf(float(impact[2]) - fade) <= TIME_TOLERANCE, "...and resolves then too (%.3f s)" % [float(impact[2]) if not impact.is_empty() else -1.0])
	_expect(not impact.is_empty() and bool(impact[3]), "...after it is in the discard")
	events.clear()
	var target: Node = _field_enemy(controller)
	var expected: float = float(controller.call("_impact_delay_for", slash))
	_expect(expected > fade, "Slash's impact delay (%.3f s) is past the fade" % expected)
	controller.call("request_play", _view(controller, slash))
	start[0] = Time.get_ticks_usec()
	controller.call("confirm_target", target)
	await _settle(controller)
	discarded = _event(events, "discarded", slash)
	impact = _event(events, "impact", slash)
	_expect(not discarded.is_empty() and absf(float(discarded[2]) - fade) <= TIME_TOLERANCE, "Slash reaches the discard at the fade's end (%.3f s)" % [float(discarded[2]) if not discarded.is_empty() else -1.0])
	_expect(not impact.is_empty() and absf(float(impact[2]) - expected) <= TIME_TOLERANCE, "...and hits at its impact delay, %.3f s from the commit (%.3f s)" % [expected, float(impact[2]) if not impact.is_empty() else -1.0])
	await _teardown()
	_completed += 1

# A Consumed card that ends the fight: it is in the exhaust pile from its
# fade's end, so the fight's end takes it out of the run deck.
func _check_consumed_fight_end() -> void:
	var finisher := CardData.new()
	finisher.card_name = "Probe Finisher"
	finisher.rarity = CardData.CardRarity.COMMON
	finisher.card_type = CardData.CardType.SKILL
	finisher.target_type = CardData.TargetType.ENEMY
	finisher.removal_scope = CardData.RemovalScope.CONSUMED
	var hit := CardEffect.new()
	hit.effect_type = CardEffect.EffectType.DAMAGE
	hit.value = 999
	finisher.effects = [hit] as Array[CardEffect]
	_new_run()
	var owned: CardData = _run_state.call("add_card", finisher)
	var size_before: int = (_run_state.get("deck") as Array).size()
	var controller: Node = await _open_fight(false)
	if controller == null:
		_completed += 1
		return
	var deck: Deck = controller.get("deck")
	deck.draw_pile.erase(owned)
	deck.hand.erase(owned)
	deck.draw_pile.append(owned)
	deck.draw(1)
	await process_frame
	_expect(deck.hand.has(owned), "The fight's Consumed card is in hand")
	_set_energy(controller, 3)
	controller.call("request_play", _view(controller, owned))
	controller.call("confirm_target", _field_enemy(controller))
	for i in 600:
		await process_frame
		if not bool(_field.get("_battle_open")):
			break
	_expect(not bool(_field.get("_battle_open")), "Its hit ends the fight")
	var run_deck: Array = _run_state.get("deck")
	_expect(not run_deck.has(owned), "...and it leaves the run deck")
	_expect_eq(run_deck.size(), size_before - 1, "...and nothing else does")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("player_max_hp", 999)
	_run_state.set("player_hp", 999)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)

# Floor 1 loaded and its fight started; the controller, or null.
func _open_fight(fresh_run: bool = true) -> Node:
	if fresh_run:
		_new_run()
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
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
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started")
		return null
	# The opening hand lands.
	await create_timer(1.5).timeout
	return overlay.get("battle_controller")

# The hand to the discard, and its fade over.
func _empty_hand(controller: Node) -> void:
	(controller.get("deck") as Deck).discard_hand()
	await create_timer(0.3).timeout

func _deal(controller: Node, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	var deck: Deck = controller.get("deck")
	deck.draw_pile.append(card)
	deck.draw(1)
	await process_frame
	return card

func _set_energy(controller: Node, energy: int) -> void:
	controller.get("player").set("energy", energy)

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	_fail("'%s' has no view in the hand" % card.card_name)
	return null

func _has_view(controller: Node, card: CardData) -> bool:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return true
	return false

# Until the play has resolved and its draws have landed.
func _settle(controller: Node) -> void:
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.8).timeout

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _since(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000000.0

func _event(events: Array, kind: String, card: CardData) -> Array:
	for event: Array in events:
		if event[0] == kind and event[1] == card:
			return event
	return []

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
