extends SceneTree

# Headless probe for the battle's pile views: DRAW and DISCARD each open a
# DeckView over the fight, whose scrim lets the battle show through - so
# the hand is hidden while one is open (BattleOverlay._on_pile_view_
# opened()), never reading through the view, and back once it closes.
# Guards the 20 Oct bug: the hand's cards drawn over the draw pile's view.
# Played on floor 1's first fight.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/pile_view_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 1
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_1 := 0
# Frames for a view to open or close and the overlay to answer it.
const VIEW_FRAMES := 5

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	await _check_pile_views()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("pile_view_probe: PASSED")
		quit(0)
	else:
		print("pile_view_probe: %d FAILED" % _failures)
		quit(1)

# In a fight: DRAW's view hides the hand and closing it brings it back;
# DISCARD's the same.
func _check_pile_views() -> void:
	var overlay: Node = await _start_fight()
	if overlay != null:
		var hand: Control = overlay.get("hand_container")
		_expect(hand.visible, "In the fight the hand shows")
		for pair: Array in [["_deck_readout", "DRAW"], ["_discard_readout", "DISCARD"]]:
			var readout: Node = overlay.get(str(pair[0]))
			readout.call("_open_deck_view")
			for i in VIEW_FRAMES:
				await process_frame
			var view: Node = readout.get("_deck_view_instance")
			_expect(view != null and is_instance_valid(view), "%s opens its view" % pair[1])
			_expect(not hand.visible, "...the hand hidden under it")
			if view != null and is_instance_valid(view):
				view.call("close")
			for i in VIEW_FRAMES:
				await process_frame
			_expect(readout.get("_deck_view_instance") == null, "...closed")
			_expect(hand.visible, "...and the hand back once it closes")
	await _teardown()
	_completed += 1

# Floor 1 on a fresh run, its first enemy contacted: the overlay once the
# fight has settled, or null (a FAIL is recorded).
func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_1)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node = null
	for node in get_nodes_in_group("enemies"):
		if not node.is_queued_for_deletion():
			target = node
			break
	if target == null:
		_fail("no enemy on floor 1")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 1")
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
