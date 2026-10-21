extends SceneTree

# Headless probe for what a hovered intent says and where: the
# Nettlebasket's Signal counts its answerers - "wakes 3 Nettles to Nip 2
# each (6)." with the pack asleep, "wakes 1 Nettle to Nip 2." with one
# left, "calls" once any answerer is awake - and the hovered intent's line
# is on its bone slip above the readout, clear of every fighter, listed
# with the readouts (BattleOverlay.get_readout_rects()). Guards the 20 Oct
# line "wakes the Nettle; each answers with Nip 2 (2 in all)", thin text
# across the model. The answers' move and number are read off the
# Nettle's data. On floor 4 with its pack stood (force_options).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/intent_hover_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 2
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const NETTLE_PATH := "res://battle/rules/enemies/nettle.tres"
const NETTLEBASKET_PATH := "res://battle/rules/enemies/nettlebasket.tres"
const FLOOR_4 := 3
const SLOT_ID := &"nettlebasket"
const OPTION_ID := &"nettlebasket"
# Frames for the hover and the readout layout to settle.
const SETTLE_FRAMES := 10

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	var overlay: Node = await _start_fight()
	if overlay != null:
		await _check_signal_wording(overlay)
		await _check_slip(overlay)
	await _teardown()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("intent_hover_probe: PASSED")
		quit(0)
	else:
		print("intent_hover_probe: %d FAILED" % _failures)
		quit(1)

# The Signal's line with the pack asleep, one Nettle left, and that one
# awake.
func _check_signal_wording(overlay: Node) -> void:
	var controller: Node = overlay.get("battle_controller")
	var basket: Node = _first_of(controller, NETTLEBASKET_PATH)
	var nettles: Array[Node] = _all_of(controller, NETTLE_PATH)
	if basket == null or nettles.size() < 2:
		_fail("the fight has no Nettlebasket and pack")
		_completed += 1
		return
	var combatants: Dictionary = controller.get("_combatants")
	var basket_combatant: Combatant = combatants.get(basket)
	_set_signal(basket_combatant, basket.get("enemy_data"))
	var answer: EnemyIntent = _first_attack(load(NETTLE_PATH) as EnemyData)
	var move: String = answer.intent_name
	var each: int = answer.value
	var name: String = EnemyTurn.current_intent(basket_combatant, basket.get("enemy_data")).intent_name
	var count: int = nettles.size()
	_expect_eq(str(overlay.call("_intent_hover_text", basket)), "%s: wakes %d Nettles to %s %d each (%d)." % [name, count, move, each, each * count], "The pack asleep: it wakes them all, counted")
	for i in range(1, nettles.size()):
		(combatants.get(nettles[i]) as Combatant).hp = 0
	_expect_eq(str(overlay.call("_intent_hover_text", basket)), "%s: wakes 1 Nettle to %s %d." % [name, move, each], "One Nettle left: wakes 1 Nettle, no \"each\"")
	(combatants.get(nettles[0]) as Combatant).dormant = false
	_expect_eq(str(overlay.call("_intent_hover_text", basket)), "%s: calls 1 Nettle to %s %d." % [name, move, each], "...awake: it calls it")
	_completed += 1

# The hovered basket's line on its slip: shown, above its readout, clear of
# every fighter, inside the window, and listed with the readouts.
func _check_slip(overlay: Node) -> void:
	var controller: Node = overlay.get("battle_controller")
	var basket: Node = _first_of(controller, NETTLEBASKET_PATH)
	var intent: Node = (overlay.get("_enemy_intents") as Dictionary).get(basket)
	if intent == null:
		_fail("no intent readout on the Nettlebasket")
		_completed += 1
		return
	overlay.set("hover_intent_override", basket)
	for i in SETTLE_FRAMES:
		await process_frame
	var slip: Rect2 = intent.call("get_hover_slip_rect")
	_expect(slip.has_area(), "Hovered, its line shows on its slip")
	_expect_eq(str(intent.call("get_refusal")), str(overlay.call("_intent_hover_text", basket)), "...saying what it does")
	if slip.has_area():
		var readout: Rect2 = intent.call("get_global_rect")
		_expect(slip.end.y <= readout.position.y, "...above its readout")
		for box: Rect2 in overlay.call("fighter_screen_boxes"):
			_expect(not slip.intersects(box), "...clear of every fighter (%s meets %s)" % [slip, box])
		var view: Vector2 = root.get_visible_rect().size
		_expect(slip.position.x >= 0.0 and slip.end.x <= view.x and slip.position.y >= 0.0, "...inside the window")
		_expect((overlay.call("get_readout_rects") as Array).has(slip), "...and listed with the readouts")
	overlay.set("hover_intent_override", null)
	for i in SETTLE_FRAMES:
		await process_frame
	_expect(not (intent.call("get_hover_slip_rect") as Rect2).has_area(), "Unhovered, the slip goes")
	_completed += 1

# Its loop on its Signal.
func _set_signal(combatant: Combatant, data: EnemyData) -> void:
	for index in data.intents.size():
		if data.intents[index].type == EnemyIntent.IntentType.SIGNAL:
			combatant.current_intent_index = index
			return
	_fail("the Nettlebasket has no Signal")

func _first_attack(data: EnemyData) -> EnemyIntent:
	for intent in data.intents:
		if intent.type == EnemyIntent.IntentType.ATTACK:
			return intent
	return null

func _all_of(controller: Node, data_path: String) -> Array[Node]:
	var found: Array[Node] = []
	for member: Node in controller.get("enemies") as Array:
		var data: Resource = member.get("enemy_data")
		if data != null and data.resource_path == data_path:
			found.append(member)
	return found

func _first_of(controller: Node, data_path: String) -> Node:
	var found: Array[Node] = _all_of(controller, data_path)
	return found[0] if not found.is_empty() else null

# Floor 4 on a fresh run, its pack stood and contacted: the overlay once
# the fight has settled, or null (a FAIL is recorded).
func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_4)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	var forced: Dictionary[StringName, StringName] = {}
	forced[SLOT_ID] = OPTION_ID
	_field.set("force_options", forced)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == NETTLEBASKET_PATH:
			target = node
	if target == null:
		_fail("no Nettlebasket on floor 4")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on the Nettlebasket")
		return null
	await ProbePlay.settle_fight(self, _field, overlay.get("battle_controller"))
	return overlay

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
