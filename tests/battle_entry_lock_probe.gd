extends SceneTree

# Headless probe for the fight's opening input hold (RegionField.battle_
# input_unlock_time, BattleController.lock_entry_input()): a real fight on
# floor 1, started through RegionField's contact handler.
#   at 0.3 s - a click on a card (HandContainer.card_clicked, what a
#              CardView's click sends) plays nothing, a click on an Attack
#              arms nothing and a target confirmed on the enemy lands
#              nothing, End Turn is disabled and end_turn() ends nothing
#   at 0.9 s - End Turn is enabled and a click on the same card plays it
#   fallback - the hold is battle_input_unlock_time (0.875 s, draw_sword
#              frame 21) with the glb's own DrawSword, and the camera's
#              settle on the Mixamo fallback
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/battle_entry_lock_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# BattleController, HandContainer).

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const ENDURE_PATH := "res://cards/neutral/endure.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const UNLOCK_S := 21.0 / 24.0
const LOCKED_CLICK_S := 0.3
const OPEN_CLICK_S := 0.9
const SAFETY_SECONDS := 60.0

var _field: Node = null
var _failures: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	var run_state: Node = root.get_node("RunState")
	run_state.call("new_run", load(CHARACTER_PATH))
	run_state.set("current_floor_index", 0)
	run_state.set("run_opening_pending", false)
	run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	await _check_hold()
	_check_unlock_time()
	_field.queue_free()
	for i in 5:
		await process_frame
	print("\nbattle_entry_lock_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)

func _check_hold() -> void:
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	if target == null:
		_check(false, "floor 1 has an enemy to fight")
		return
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	var layer: Node = _field.get_node("BattleLayer")
	var start: int = Time.get_ticks_msec()
	while layer.get_child_count() == 0 and Time.get_ticks_msec() - start < 2000:
		await process_frame
	# The contact ran in the deferred flush just before this frame.
	var contact_usec: int = Time.get_ticks_usec()
	if layer.get_child_count() == 0:
		_check(false, "a fight starts")
		return
	var overlay: Node = layer.get_child(0)
	var controller: Node = overlay.get("battle_controller")
	var hand: Node = controller.get("_hand_container")
	var end_turn_button: Button = overlay.get("end_turn_button")
	controller.get("player").set("energy", 3)
	var deck: Deck = controller.get("deck")
	var endure: CardData = _deal(deck, ENDURE_PATH)
	var slash: CardData = _deal(deck, SLASH_PATH)
	var played: Array[CardData] = []
	controller.connect("card_played", func(card: CardData, _target: Node) -> void: played.append(card))
	var phases: Array[bool] = []
	controller.connect("turn_phase_changed", func(player_turn: bool) -> void: phases.append(player_turn))
	await process_frame

	await _until(contact_usec, LOCKED_CLICK_S)
	var at: float = _since(contact_usec)
	_check(bool(controller.call("is_entry_locked")), "%.3f s after contact the opening hold is on" % at)
	_check(end_turn_button.disabled, "End Turn is disabled through it")
	hand.emit_signal("card_clicked", _view(hand, endure))
	hand.emit_signal("card_clicked", _view(hand, slash))
	controller.call("confirm_target", target)
	controller.call("end_turn")
	await process_frame
	_check(played.is_empty() and deck.hand.has(endure) and deck.hand.has(slash), "a click on Endure at %.3f s plays nothing (played: %d)" % [at, played.size()])
	_check(controller.call("get_pending_card_view") == null, "a click on Slash arms nothing, and a confirmed target lands nothing")
	_check(phases.is_empty(), "end_turn() ends nothing")

	await _until(contact_usec, OPEN_CLICK_S)
	at = _since(contact_usec)
	_check(not bool(controller.call("is_entry_locked")), "%.3f s after contact the hold is over" % at)
	_check(not end_turn_button.disabled, "End Turn is enabled")
	hand.emit_signal("card_clicked", _view(hand, endure))
	await process_frame
	_check(played.size() == 1 and played[0] == endure, "a click on Endure at %.3f s plays it" % at)

# The hold is battle_input_unlock_time with the glb's own DrawSword, the
# camera's settle on the Mixamo fallback.
func _check_unlock_time() -> void:
	var wanderer: Node = _field.get_node("Wanderer")
	var unlock: float = float(_field.get("battle_input_unlock_time"))
	_check(absf(unlock - UNLOCK_S) <= 0.0001, "battle_input_unlock_time is draw_sword frame 21, %.4f s" % unlock)
	_check(bool(wanderer.call("has_own_draw_sword")), "the Wanderer carries the glb's own DrawSword")
	var transition: float = 0.6
	_check(absf(float(_field.call("_battle_input_unlock_seconds", transition)) - unlock) <= 0.0001, "with it, the hold is battle_input_unlock_time")
	wanderer.set("_own_draw_sword", false)
	var fallback: float = float(_field.call("_battle_input_unlock_seconds", transition))
	wanderer.set("_own_draw_sword", true)
	_check(absf(fallback - transition) <= 0.0001, "on the Mixamo fallback, the camera's settle (%.3f s)" % fallback)

func _deal(deck: Deck, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	deck.draw_pile.append(card)
	deck.draw(1)
	return card

func _view(hand: Node, card: CardData) -> CardView:
	for view: CardView in hand.call("_card_views"):
		if view.card_data == card:
			return view
	_check(false, "'%s' has a view in the hand" % card.card_name)
	return null

func _until(start_usec: int, seconds: float) -> void:
	while _since(start_usec) < seconds:
		await process_frame

func _since(start_usec: int) -> float:
	return float(Time.get_ticks_usec() - start_usec) / 1000000.0

func _check(ok: bool, label: String) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1
