extends SceneTree

# Headless probe for the battle's number keys (BattleController.key_slot()):
# card_slot_1..card_slot_10 arm the card at that hand position as a click
# does, the same key again plays it - at the lit target, which target_next
# and target_prev move left to right and the mouse moving hands back to
# the cursor; another card's key switches, battle_cancel disarms, a card
# with no target arms first and plays on its key again, an unplayable card
# doesn't arm (not for Devour either), and in a hand choice (Bide's) a key
# marks and unmarks. Every key goes through the viewport (Viewport.push_
# input()) as the InputMap's own event, so the actions are what's tested.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/card_keys_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fights load the real region scene and fight the first floor that has a
# pack (two or more enemies sharing a FieldEnemy.group) through RegionField's
# contact handler (ProbePlay.start_fight()). Untyped against anything that
# names the RunState autoload.

const CASES := 6
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const STONESHELL_PATH := "res://cards/data/stoneshell.tres"
const BIDE_PATH := "res://cards/data/bide.tres"
const ENEMY_HP := 999
const PLAYER_HP := 999
# Floors tried for a pack, from the first.
const MAX_FLOORS := 8
const SAFETY_SECONDS := 300.0
# How long a dealt card may take to land in the hand.
const LAND_SECONDS := 3.0

var _run_state: Node = null
var _field: Node = null
var _pack_floor: int = -1
var _failures: int = 0
var _completed: int = 0
var _hovered: Array[Node] = []
var _played: Array = []

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	await _check_arm_cycle_play()
	await _check_switch_and_cancel()
	await _check_mouse_takes_back()
	await _check_no_target_two_presses()
	await _check_unplayable_not_armed()
	await _check_choice_toggles()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("card_keys_probe: PASSED")
		quit(0)
	else:
		print("card_keys_probe: %d FAILED" % _failures)
		quit(1)

# A Slash armed by its number, the target moved right by target_next -
# told as hovered_enemy_changed - round the whole row back to where it
# began, and back one by target_prev; its number again plays it at the
# target the keys chose.
func _check_arm_cycle_play() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var position: int = _position_of(controller, slash)
		_expect(position >= 0, "The dealt Slash has a hand position")
		_press("card_slot_%d" % (position + 1))
		_expect(bool(controller.call("is_awaiting_target")), "Its number arms it")
		_expect(controller.call("get_pending_card_view") == _view(controller, slash), "...that card, the one at the position")
		_expect_eq(int(controller.get("cards_played_this_turn")), 0, "...nothing played yet")
		for i in 3:
			await physics_frame
		var targets: Array = controller.call("_key_targets")
		_expect(targets.size() >= 2, "The pack gives the armed Slash two targets or more (%d)" % targets.size())
		var start: Node = controller.call("get_hovered_enemy")
		_expect(start != null, "...one lit before any key (the default)")
		_hovered.clear()
		_press("target_next")
		var next: Node = controller.call("get_hovered_enemy")
		_expect(next != null and next != start, "target_next lights another target")
		_expect(_hovered.has(next), "...told as hovered_enemy_changed, so the face previews it")
		for i in 3:
			await physics_frame
		_expect(controller.call("get_hovered_enemy") == next, "...and it holds over the cursor's frame by frame")
		for i in targets.size() - 1:
			_press("target_next")
		_expect(controller.call("get_hovered_enemy") == start, "target_next round the whole row wraps back to the first")
		_press("target_prev")
		var chosen: Node = controller.call("get_hovered_enemy")
		_expect(chosen != null and chosen != start, "target_prev steps back the other way")
		_played.clear()
		_press("card_slot_%d" % (position + 1))
		await ProbePlay.settle(self, controller)
		_expect_eq(_played.size(), 1, "Its number again plays it")
		_expect(not _played.is_empty() and _played[0][1] == chosen, "...at the target the keys chose")
		_expect(not bool(controller.call("is_awaiting_target")), "...nothing armed after")
	await _teardown()
	_completed += 1

# Another card's number switches the armed card at once, the first back
# in the fan; battle_cancel disarms with nothing played; battle_confirm
# plays at the lit target.
func _check_switch_and_cancel() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var first: CardData = await _deal(controller, SLASH_PATH)
		var second: CardData = await _deal(controller, SLASH_PATH)
		var first_view: CardView = _view(controller, first)
		_press("card_slot_%d" % (_position_of(controller, first) + 1))
		_expect(controller.call("get_pending_card_view") == first_view, "The first card armed")
		_press("card_slot_%d" % (_position_of(controller, second) + 1))
		_expect(controller.call("get_pending_card_view") == _view(controller, second), "Another number switches to that card")
		_expect(controller.get("_hand_container").get("_armed_slot") == _view(controller, second).get_parent(), "...the hand holds it as the armed card")
		_expect(not bool(first_view.get("_armed")) and controller.get("_hand_container").get("_armed_slot") != first_view.get_parent(), "...the first released")
		_press("battle_cancel")
		_expect(not bool(controller.call("is_awaiting_target")), "battle_cancel disarms")
		_expect_eq(int(controller.get("cards_played_this_turn")), 0, "...nothing played")
		_press("card_slot_%d" % (_position_of(controller, second) + 1))
		for i in 3:
			await physics_frame
		var lit: Node = controller.call("get_hovered_enemy")
		_played.clear()
		_press("battle_confirm")
		await ProbePlay.settle(self, controller)
		_expect_eq(_played.size(), 1, "battle_confirm plays the armed card")
		_expect(not _played.is_empty() and lit != null and _played[0][1] == lit, "...at the lit target")
	await _teardown()
	_completed += 1

# The keys' target stands until the mouse moves; then the cursor's rule
# (over no enemy, the default) lights again.
func _check_mouse_takes_back() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var slash: CardData = await _deal(controller, SLASH_PATH)
		_press("card_slot_%d" % (_position_of(controller, slash) + 1))
		for i in 3:
			await physics_frame
		var start: Node = controller.call("get_hovered_enemy")
		_press("target_next")
		_expect(controller.call("get_hovered_enemy") != start, "target_next moves off the default")
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(4, 4)
		motion.relative = Vector2(3, 0)
		root.push_input(motion)
		for i in 3:
			await physics_frame
		_expect(controller.get("_key_target") == null, "The mouse moving lets the keys' target go")
		_expect(controller.call("get_hovered_enemy") == start, "...the default lit again, the cursor over no enemy")
		_press("battle_cancel")
	await _teardown()
	_completed += 1

# A card with no target (Stoneshell): its number arms it, playing
# nothing and lighting no enemy; its number again plays it.
func _check_no_target_two_presses() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var shell: CardData = await _deal(controller, STONESHELL_PATH)
		var position: int = _position_of(controller, shell)
		_press("card_slot_%d" % (position + 1))
		for i in 3:
			await physics_frame
		_expect(controller.call("get_pending_card_view") == _view(controller, shell), "A card with no target: its number arms it")
		_expect_eq(int(controller.get("cards_played_this_turn")), 0, "...plays nothing yet")
		_expect(controller.call("get_hovered_enemy") == null, "...and lights no enemy")
		_press("target_next")
		_expect(controller.call("get_hovered_enemy") == null, "...nor does target_next")
		_played.clear()
		_press("card_slot_%d" % (position + 1))
		await ProbePlay.settle(self, controller)
		_expect_eq(_played.size(), 1, "Its number again plays it")
		_expect(not _played.is_empty() and _played[0][0] == shell, "...that card")
		_expect(not bool(controller.call("is_awaiting_target")), "...nothing armed after")
	await _teardown()
	_completed += 1

# With no Energy, a Slash's number arms nothing - not even for Devour,
# which a click would; a key past the hand does nothing.
func _check_unplayable_not_armed() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var player: Combatant = controller.get("player")
		player.energy = 0
		controller.emit_signal("energy_changed", 0)
		await process_frame
		_press("card_slot_%d" % (_position_of(controller, slash) + 1))
		_expect(not bool(controller.call("is_awaiting_target")), "An unplayable card's number arms nothing")
		_expect(not bool(controller.call("is_armed_for_devour_only")), "...not for Devour either")
		var count: int = (controller.get("_hand_container").call("positioned_card_views") as Array).size()
		if InputMap.has_action("card_slot_%d" % (count + 1)):
			_press("card_slot_%d" % (count + 1))
			_expect(not bool(controller.call("is_awaiting_target")) and not bool(controller.call("is_choosing")), "A number past the hand does nothing")
	await _teardown()
	_completed += 1

# Bide (its Toll held) by its number opens its choice (as a click does); another card's
# number marks it, again unmarks it; battle_cancel backs out.
func _check_choice_toggles() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var other: CardData = await _deal(controller, SLASH_PATH)
		var bide: CardData = await _deal(controller, BIDE_PATH)
		# Bide's own Toll price (its SPEND_TOLL), held, so it can be played.
		var player: Combatant = controller.get("player")
		for effect: CardEffect in bide.effects:
			if effect != null:
				player.toll = maxi(player.toll, effect.toll_cost)
		controller.emit_signal("toll_changed", player.toll)
		await process_frame
		_press("card_slot_%d" % (_position_of(controller, bide) + 1))
		_expect(bool(controller.call("is_choosing")), "Bide's number opens its choice")
		_press("card_slot_%d" % (_position_of(controller, other) + 1))
		_expect((controller.call("get_choice_marked_names") as Array).has(other.card_name), "...another card's number marks it")
		_press("card_slot_%d" % (_position_of(controller, other) + 1))
		_expect((controller.call("get_choice_marked_names") as Array).is_empty(), "...and again unmarks it")
		_press("card_slot_%d" % (_position_of(controller, bide) + 1))
		_expect(bool(controller.call("is_choosing")) and (controller.call("get_choice_marked_names") as Array).is_empty(), "...Bide's own number does nothing")
		_press("battle_cancel")
		_expect(not bool(controller.call("is_choosing")), "battle_cancel backs out of the choice")
		_expect_eq(int(controller.get("cards_played_this_turn")), 0, "...nothing played")
	await _teardown()
	_completed += 1

# --- Keys ---

# `action`'s first InputMap event, pressed, through the viewport - then
# released, as a key is.
func _press(action: StringName) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		_fail("the InputMap has no event for %s" % action)
		return
	var press := events[0].duplicate() as InputEventKey
	if press == null:
		_fail("%s's first event is no key" % action)
		return
	press.pressed = true
	root.push_input(press)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)

# --- Fights ---

# A new run, its deck Slash alone, on the first floor with a pack, the
# fight started on one of the pack - every enemy's HP and the Wanderer's
# raised so nothing ends it. The controller, or null (a FAIL recorded).
func _start_fight() -> Node:
	var floors: Array[int] = []
	if _pack_floor >= 0:
		floors.append(_pack_floor)
	else:
		for index in MAX_FLOORS:
			floors.append(index)
	for floor_index in floors:
		_run_state.call("new_run", load(CHARACTER_PATH))
		var cards: Array[CardData] = []
		for i in 10:
			cards.append((load(SLASH_PATH) as CardData).duplicate() as CardData)
		_run_state.set("deck", cards)
		_run_state.set("player_max_hp", PLAYER_HP)
		_run_state.set("player_hp", PLAYER_HP)
		_run_state.set("current_floor_index", floor_index)
		_run_state.set("run_opening_pending", false)
		_run_state.set("title_pending", false)
		_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(_field)
		for i in 30:
			await physics_frame
		var target: Node3D = _pack_member()
		if target == null:
			await _teardown()
			continue
		_pack_floor = floor_index
		var controller: Node = await ProbePlay.start_fight(self, _field, target)
		if controller == null:
			_fail("no fight started on floor %d's pack" % (floor_index + 1))
			return null
		for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
			enemy.max_hp = ENEMY_HP
			enemy.hp = ENEMY_HP
		var player: Combatant = controller.get("player")
		player.energy = 3
		controller.emit_signal("energy_changed", player.energy)
		controller.connect("hovered_enemy_changed", func(enemy: Node) -> void: _hovered.append(enemy))
		controller.connect("card_played", func(card: CardData, enemy: Node) -> void: _played.append([card, enemy]))
		await process_frame
		return controller
	_fail("no floor with a pack in the first %d" % MAX_FLOORS)
	return null

# A field enemy with a packmate on the field (the same non-empty group).
func _pack_member() -> Node3D:
	var by_group: Dictionary = {}
	for node in get_nodes_in_group("enemies"):
		var group: StringName = node.get("group")
		if group == &"":
			continue
		by_group[group] = int(by_group.get(group, 0)) + 1
		if int(by_group[group]) >= 2:
			return node as Node3D
	return null

# `path`'s card into the hand (the opening hand discarded first, once),
# waited until it has landed and takes keys.
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
	var hand: Node = controller.get("_hand_container")
	var takes_keys := func() -> bool:
		var position: int = _position_of(controller, card)
		return position >= 0 and hand.call("card_view_at_position", position) != null
	var landed: bool = await ProbePlay.wait_until(self, takes_keys, LAND_SECONDS)
	_expect(landed, "the dealt %s landed in the hand" % card.card_name)
	return card

# `card`'s hand position (HandContainer.positioned_card_views()), or -1.
func _position_of(controller: Node, card: CardData) -> int:
	var views: Array = controller.get("_hand_container").call("positioned_card_views")
	for index in views.size():
		if (views[index] as CardView).card_data == card:
			return index
	return -1

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
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
