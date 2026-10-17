extends SceneTree

# Headless probe for the fight's opening input hold (BattleController.
# lock_entry_input(), released by Wanderer.draw_strike_passed): a real
# fight on floor 1, started through RegionField's contact handler.
#   at 0.3 s - a click on a card (HandContainer.card_clicked, what a
#              CardView's click sends) plays nothing, a click on an Attack
#              arms nothing and a target confirmed on the enemy lands
#              nothing, End Turn is disabled and end_turn() ends nothing
#   strike   - the hold ends as DrawSword's playhead reaches the Wanderer's
#              draw_sword_strike_time, as read live; End Turn is enabled
#              then and a click on the same card plays it
#   cut      - a draw cut off before its strike ends the hold too, and a
#              release that never comes ends it at its safety time; either
#              way the release signal is let go
#   latest   - the hold's safety time is DrawSword's own length with the
#              glb's own DrawSword, the camera's settle on the Mixamo
#              fallback
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
const LOCKED_CLICK_S := 0.3
# How far past the strike key the hold may end (seconds, a few frames),
# and the longest the probe waits for it.
const STRIKE_SLACK_S := 1.0 / 20.0
const RELEASE_WAIT_S := 2.0
# Holds armed by the probe itself, for the cut and the safety time.
const PROBE_HOLD_S := 5.0
const SAFETY_HOLD_S := 0.2
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
	_check_hold_seconds()
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
	var start: int = ProbePlay.cap_msec()
	while layer.get_child_count() == 0 and ProbePlay.cap_msec() - start < 2000:
		await process_frame
	# The contact ran in the deferred flush just before this frame.
	var contact_usec: int = ProbePlay.game_usec()
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
	var player: AnimationPlayer = wanderer.get("_animation_player")
	var released_at: Array[float] = []
	controller.connect("entry_lock_changed", func(locked: bool) -> void:
		if not locked and released_at.is_empty():
			released_at.append(player.current_animation_position if player.current_animation == "DrawSword" else -1.0))
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

	while bool(controller.call("is_entry_locked")) and _since(contact_usec) < RELEASE_WAIT_S:
		await process_frame
	at = _since(contact_usec)
	var strike: float = float(wanderer.get("draw_sword_strike_time"))
	var released: float = released_at[0] if not released_at.is_empty() else -1.0
	_check(not bool(controller.call("is_entry_locked")), "the hold is over %.3f s after contact" % at)
	_check(released >= strike - 0.001 and released <= strike + STRIKE_SLACK_S, "it ended on the draw's strike: DrawSword %.3f s in (draw_sword_strike_time %.4f)" % [released, strike])
	_check(not end_turn_button.disabled, "End Turn is enabled")
	hand.emit_signal("card_clicked", _view(hand, endure))
	await process_frame
	_check(played.size() == 1 and played[0] == endure, "a click on Endure at %.3f s plays it" % at)

	# The entry's own safety timer runs out before the probe arms more.
	await _until(contact_usec, float(wanderer.call("get_draw_sword_length")) + 0.1)
	var release: Signal = wanderer.get("draw_strike_passed")
	var unlock: Callable = Callable(controller, "unlock_entry_input")
	# A draw still waiting on its strike, cut off: the next pose the
	# mixer applies (BattleIdle playing) is the cut.
	controller.call("lock_entry_input", PROBE_HOLD_S, release)
	wanderer.set("_strike_pending", true)
	for i in 5:
		await process_frame
	_check(not bool(controller.call("is_entry_locked")), "a draw cut off before its strike ends the hold")
	_check(not release.is_connected(unlock), "and lets the release go")
	controller.call("lock_entry_input", SAFETY_HOLD_S, release)
	var armed_usec: int = ProbePlay.game_usec()
	await _until(armed_usec, SAFETY_HOLD_S - 0.05)
	_check(bool(controller.call("is_entry_locked")), "a release that never comes holds on (%.3f s)" % _since(armed_usec))
	await _until(armed_usec, SAFETY_HOLD_S + 0.1)
	_check(not bool(controller.call("is_entry_locked")), "until its safety time (%.3f s)" % _since(armed_usec))
	_check(not release.is_connected(unlock), "and lets the release go")

# The hold's safety time: DrawSword's own length with the glb's own
# DrawSword, the camera's settle on the Mixamo fallback.
func _check_hold_seconds() -> void:
	var wanderer: Node = _field.get_node("Wanderer")
	_check(bool(wanderer.call("has_own_draw_sword")), "the Wanderer carries the glb's own DrawSword")
	var player: AnimationPlayer = wanderer.get("_animation_player")
	var length: float = player.get_animation(&"DrawSword").length
	var transition: float = 0.6
	var hold: float = float(_field.call("_battle_input_hold_seconds", transition))
	_check(length > 0.0 and absf(hold - length) <= 0.0001, "with it, the hold lasts at most DrawSword's length (%.4f s, clip %.4f s)" % [hold, length])
	wanderer.set("_own_draw_sword", false)
	var fallback: float = float(_field.call("_battle_input_hold_seconds", transition))
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
	return float(ProbePlay.game_usec() - start_usec) / 1000000.0

func _check(ok: bool, label: String) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1
