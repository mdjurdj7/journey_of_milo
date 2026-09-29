extends SceneTree

# Headless probe for Toll between fights: whatever a fight ends on, only
# min(Toll, CharacterData.toll_carry_cap) carries - after a win, after an
# escape, and across a floor advance - and a new run starts at 0. The cap
# directly, then real fights and a real floor exit on the region scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/toll_carry_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Deliberately untyped against the project's own classes (get()/call()
# only), like kill_order_probe: a SceneTree script compiles before the
# autoloads register, and naming RunState here would fail to compile.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CASES := 6
const SAFETY_SECONDS := 180.0
# Physics frames for a fight's end to land (settle, frees, reward delay).
const SETTLE_FRAMES := 90

var _failures: int = 0
var _completed: int = 0
var _run_state: Node = null

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_run_state.call("new_run", load(CHARACTER_PATH))
	_check_cap_data()
	_check_carry()
	_check_new_run()
	await _check_win()
	await _check_escape()
	await _check_floor_advance()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("toll_carry_probe: PASSED")
		quit(0)
	else:
		print("toll_carry_probe: %d FAILED" % _failures)
		quit(1)

func _check_cap_data() -> void:
	var character: Resource = load(CHARACTER_PATH)
	_expect_eq(character.get("toll_carry_cap"), 5, "The Wanderer carries up to 5 Toll")
	_completed += 1

func _check_carry() -> void:
	for pair in [[0, 0], [3, 3], [5, 5], [14, 5]]:
		_toll(pair[0])
		_run_state.call("carry_toll")
		_expect_eq(_toll_now(), pair[1], "Ending on %d carries %d" % [pair[0], pair[1]])
	_completed += 1

func _check_new_run() -> void:
	_toll(4)
	_run_state.call("new_run", load(CHARACTER_PATH))
	_expect_eq(_toll_now(), 0, "A new run starts at 0 Toll")
	_completed += 1

# A won fight on floor 1: ending on 14 keeps 5, ending on 3 keeps 3.
func _check_win() -> void:
	for pair in [[14, 5], [3, 3]]:
		_run_state.call("new_run", load(CHARACTER_PATH))
		_run_state.set("current_floor_index", 0)
		var field: Node3D = await _load_field()
		var fight: Array = await _start_fight(field)
		if fight.is_empty():
			await _teardown(field)
			return
		var controller: Node = fight[0]
		_toll(pair[0])
		var combatants: Dictionary = controller.get("_combatants")
		for member in (controller.get("enemies") as Array).duplicate():
			var combatant: RefCounted = combatants.get(member)
			combatant.set("hp", 0)
			controller.call("_report_damage", "player", combatant, 99, "card")
		controller.call("_check_battle_end")
		for i in SETTLE_FRAMES:
			await physics_frame
		_expect(not bool(field.get("_battle_open")), "Win on %d: the fight is over" % pair[0])
		_expect_eq(_toll_now(), pair[1], "Win on %d: the next fight starts on %d" % [pair[0], pair[1]])
		await _teardown(field)
	_completed += 1

# An escaped fight: ending on 14 keeps 5, ending on 2 keeps 2.
func _check_escape() -> void:
	for pair in [[14, 5], [2, 2]]:
		_run_state.call("new_run", load(CHARACTER_PATH))
		_run_state.set("current_floor_index", 0)
		var field: Node3D = await _load_field()
		var fight: Array = await _start_fight(field)
		if fight.is_empty():
			await _teardown(field)
			return
		var overlay: Node = fight[1]
		_toll(pair[0])
		# The Escape button's own path.
		overlay.call("_finish_battle", 2)
		for i in SETTLE_FRAMES:
			await physics_frame
		_expect(not is_instance_valid(overlay), "Escape on %d: the fight is over" % pair[0])
		_expect_eq(_toll_now(), pair[1], "Escape on %d: carries %d" % [pair[0], pair[1]])
		await _teardown(field)
	_completed += 1

# The floor advance keeps min(Toll, 5) instead of resetting to 0.
func _check_floor_advance() -> void:
	for pair in [[14, 5], [3, 3], [0, 0]]:
		_run_state.call("new_run", load(CHARACTER_PATH))
		_run_state.set("current_floor_index", 0)
		var field: Node3D = await _load_field()
		current_scene = field
		_toll(pair[0])
		await field.call("_on_floor_exited")
		for i in 10:
			await process_frame
		_expect_eq(int(_run_state.get("current_floor_index")), 1, "Floor exit on %d: onto floor 2" % pair[0])
		_expect_eq(_toll_now(), pair[1], "Floor exit on %d: floor 2 starts on %d" % [pair[0], pair[1]])
		var reloaded: Node = current_scene
		if reloaded != null:
			reloaded.queue_free()
		current_scene = null
		for i in 5:
			await process_frame
	_completed += 1

# --- Helpers ---

func _toll(value: int) -> void:
	_run_state.call("set_toll", value)

func _toll_now() -> int:
	return int(_run_state.get("toll"))

func _load_field() -> Node3D:
	var field := (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(field)
	for i in 30:
		await physics_frame
	return field

# Starts a fight with the floor's first required enemy, the way the
# contact Area would. [controller, overlay], or [] if none started.
func _start_fight(field: Node3D) -> Array:
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if bool(node.get("required")):
			target = node as Node3D
			break
	if target == null:
		_fail("no required enemy on the floor")
		return []
	var wanderer := field.get_node("Wanderer") as Node3D
	# Just outside its contact radius, so only the deferred call below
	# starts the fight - not the Area as well.
	var reach: float = float(target.get("contact_radius")) + 0.6
	wanderer.global_position = target.global_position + Vector3(reach, 0.0, 0.0)
	await physics_frame
	field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("no fight started")
		return []
	var overlay: Node = layer.get_child(0)
	return [overlay.get("battle_controller"), overlay]

func _teardown(field: Node3D) -> void:
	field.queue_free()
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
