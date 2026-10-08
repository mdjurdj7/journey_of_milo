extends SceneTree

# Headless probe for the card faces against Come Due in a real fight -
# what come_due_probe.gd can't reach without a controller: the hand at
# rest with two enemies, the armed card's face following the enemy under
# the cursor (BattleController.hovered_enemy_changed) and reverting when
# it leaves, and the lone survivor read without any hover - where an
# all-enemies card (Carve, which plays without arming) leaves the mark
# out though the hand has a target.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/come_due_face_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# The fight is floor 3's Blackback and Nipper, started through
# RegionField's contact handler as blackback_probe.gd does. The Blackback
# carries the mark. Hovers go through the controller's own _update_hover()
# at the centre of each enemy's target rect, read in the same frame, so
# the headless cursor can't move them. Untyped against anything that
# names the RunState autoload.

const CASES := 3
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BLACKBACK_PATH := "res://battle/rules/enemies/blackback.tres"
const COME_DUE_STATUS_PATH := "res://battle/rules/statuses/come_due.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const FLOOR_3 := 2
const PLAYER_HP := 999
const ENEMY_HP := 999
const SLASH := 6
const MARKED := 10
const CARVE := 6
const OFF_SCREEN := Vector2(-100000.0, -100000.0)
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

	var controller: Node = await _start_fight()
	if controller != null:
		var blackback: Node = _member(controller, "Blackback")
		var nipper: Node = _member(controller, "Nipper")
		_expect(blackback != null and nipper != null, "The fight is the Blackback and the Nipper")
		if blackback != null and nipper != null:
			Status.apply_to(_combatant(controller, blackback).statuses, load(COME_DUE_STATUS_PATH) as StatusData)
			controller.emit_signal("status_changed")
			var slash: CardData = await _deal(controller, SLASH_PATH)
			var other: CardData = await _deal(controller, SLASH_PATH)
			var carve: CardData = await _deal(controller, CARVE_PATH)
			_check_rest(controller, slash, carve)
			_check_hover(controller, slash, other, blackback, nipper)
			await _check_lone_survivor(controller, slash, carve, blackback, nipper)
	await _teardown()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("come_due_face_probe: PASSED")
		quit(0)
	else:
		print("come_due_face_probe: %d failure(s)" % _failures)
		quit(1)

# Two enemies and nothing armed: every face reads with the player's own
# modifiers only - the mark on one of them left out.
func _check_rest(controller: Node, slash: CardData, carve: CardData) -> void:
	_expect_eq(_face_damage(controller, slash), SLASH, "At rest with two enemies, Slash reads 6")
	_expect_eq(_face_damage(controller, carve), CARVE, "...and Carve 6")
	_completed += 1

# Slash armed: 10 over the marked Blackback, 6 over the Nipper and over
# no one (the default target lit then is not a hover), 10 again, and 6
# once cancelled. The other Slash in hand stays 6 throughout.
func _check_hover(controller: Node, slash: CardData, other: CardData, blackback: Node, nipper: Node) -> void:
	controller.call("request_play", _view(controller, slash))
	_expect(controller.call("is_awaiting_target"), "Slash arms")
	_hover(controller, blackback)
	_expect_eq(_face_damage(controller, slash), MARKED, "Armed over the marked Blackback, Slash reads 10")
	_expect_eq(_face_damage(controller, other), SLASH, "...while the Slash still in hand reads 6")
	_hover(controller, nipper)
	_expect_eq(_face_damage(controller, slash), SLASH, "Over the Nipper it reads 6")
	_hover(controller, blackback)
	_expect_eq(_face_damage(controller, slash), MARKED, "Back over the Blackback, 10")
	controller.call("_update_hover", OFF_SCREEN)
	_expect_eq(_face_damage(controller, slash), SLASH, "Over no enemy it reverts to 6")
	_hover(controller, blackback)
	controller.call("cancel_target")
	_expect_eq(_face_damage(controller, slash), SLASH, "Cancelled over the Blackback, it reverts to 6")
	_completed += 1

# The Nipper dead, the Blackback is the only enemy: Slash reads 10 with no
# hover at all, and that is what it then takes off. Carve, beside it,
# still reads 6 - it hits everyone, so no one enemy's mark is its number.
func _check_lone_survivor(controller: Node, slash: CardData, carve: CardData, blackback: Node, nipper: Node) -> void:
	var survivor: Combatant = _combatant(controller, blackback)
	var dead: Combatant = _combatant(controller, nipper)
	dead.hp = 0
	controller.call("_report_damage", "player", dead, 99, "card")
	for i in 30:
		await process_frame
	controller.emit_signal("status_changed")
	var face: int = _face_damage(controller, slash)
	_expect_eq(face, MARKED, "With the Blackback alone, Slash reads 10 at rest")
	_expect_eq(_face_damage(controller, carve), CARVE, "...and Carve still 6")
	var before: int = survivor.hp + survivor.block
	(controller.get("player") as Combatant).energy = 3
	await _play(controller, slash, blackback)
	_expect_eq(before - (survivor.hp + survivor.block), face, "...and lands the 9 it read")
	_completed += 1

# --- Helpers ---

# A new run on floor 3 at PLAYER_HP, the fight started on the Blackback,
# both enemies unkillable by a stray blow, an empty hand and 3 Energy.
# The controller, or null (a FAIL is recorded).
func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_3)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == BLACKBACK_PATH:
			target = node as Node3D
	if target == null:
		_fail("no Blackback on floor 3")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(0.0, 0.0, 1.5)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 3")
		return null
	# Let the battle frame settle and the opening hand land.
	await create_timer(2.5).timeout
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	controller.get("deck").call("discard_hand")
	(controller.get("player") as Combatant).energy = 3
	await process_frame
	return controller

# The controller's own hover pass with the cursor at the centre of
# `member`'s target rect.
func _hover(controller: Node, member: Node) -> void:
	controller.call("_refresh_enemy_rects")
	var rects: Dictionary = controller.get("_enemy_rects")
	if not rects.has(member):
		_fail("no target rect for %s" % member.name)
		return
	var rect: Rect2 = rects[member]
	controller.call("_update_hover", rect.get_center())
	if controller.get("_cursor_enemy") != member:
		_fail("the cursor at %s's rect centre isn't over it" % member.name)

# A fresh copy of the card at `path`, drawn into the hand.
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

# Plays `card` from the hand through the controller's own path, and waits
# for the play to resolve.
func _play(controller: Node, card: CardData, target: Node) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	controller.call("confirm_target", target)
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

# The number after "Deal" on `card`'s face in the hand - its damage. -1
# with none or no such card.
func _face_damage(controller: Node, card: CardData) -> int:
	var view: CardView = _view(controller, card)
	if view == null:
		return -1
	var regex := RegEx.new()
	regex.compile("Deal (\\d+)")
	var found: RegExMatch = regex.search(view.rules_text.get_parsed_text())
	return int(found.get_string(1)) if found != null else -1

func _member(controller: Node, enemy_name: String) -> Node:
	for member: Node in (controller.get("enemies") as Array):
		var data: EnemyData = member.get("enemy_data")
		if data != null and data.enemy_name == enemy_name:
			return member
	return null

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

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
