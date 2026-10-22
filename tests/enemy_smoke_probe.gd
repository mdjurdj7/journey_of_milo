extends SceneTree

# Core probe: every encounter fights. Data-driven: every option of every
# slot on every floor of the region (its FloorData), stood with
# RegionField.force_options and fought for real - contact, the fight
# opening, then TURNS enemy turns through BattleController.end_turn(),
# the Wanderer at HUGE_HP so nothing ends it. Each turn, the HP the
# enemies' previews say will reach him (get_intent_preview()'s damage_to_
# hp, every enemy summed) is the HP their attacks take from him. A fight
# that doesn't open, ends early, or doesn't come back to his turn fails.
# Values are never pinned; a script error anywhere fails it too (tools/
# run_probes.sh).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_smoke_probe.gd
#
# Exit code 0 = every encounter fought, 1 = a failure (each printed as
# FAIL). Untyped against anything that names the RunState autoload.

const REGION_PATH := "res://floors/region1.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const TURNS := 3
const HUGE_HP := 99999
const SAFETY_SECONDS := 480.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _fought: int = 0
var _options: int = 0
# The HP enemy attacks took from him this enemy turn.
var _landed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var floors: Array = (load(REGION_PATH) as Resource).get("floors")
	for floor_index in floors.size():
		var floor_data := floors[floor_index] as FloorData
		for slot in floor_data.slots:
			if slot == null:
				continue
			for option in slot.options:
				# An option that stands no one has no fight.
				if option != null and not option.members.is_empty():
					_options += 1
					await _fight(floor_index, slot, option)
	print("enemy_smoke_probe: %d of %d encounters fought" % [_fought, _options])
	if _failures == 0:
		print("enemy_smoke_probe: PASSED")
		quit(0)
	else:
		print("enemy_smoke_probe: %d FAILED" % _failures)
		quit(1)

func _fight(floor_index: int, slot: EncounterSlot, option: EncounterOption) -> void:
	var label: String = "Floor %d %s/%s" % [floor_index + 1, slot.slot_id, option.option_id]
	print("\n=== %s" % label)
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.call("set_max_hp", HUGE_HP)
	_run_state.set("player_hp", HUGE_HP)
	_run_state.set("current_floor_index", floor_index)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	var forced: Dictionary[StringName, StringName] = {}
	forced[slot.slot_id] = option.option_id
	_field.set("force_options", forced)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	await ProbePlay.wait_until(self, func() -> bool: return not bool(_field.call("is_arrival_held")), 10.0)
	var target: Node3D = _target_for(slot.slot_id)
	if target == null:
		_fail("%s: no enemy of the slot on the field" % label)
		await _teardown()
		return
	var controller: Node = await ProbePlay.start_fight(self, _field, target)
	if controller == null:
		_fail("%s: contact opened no fight" % label)
		await _teardown()
		return
	controller.connect("damage_dealt", _on_damage_dealt)
	var clean: bool = true
	for turn in TURNS:
		var player: Combatant = controller.get("player")
		player.max_hp = HUGE_HP
		player.hp = HUGE_HP
		player.block = 0
		var previewed: int = 0
		for enemy: Node in (controller.get("enemies") as Array):
			previewed += int((controller.call("get_intent_preview", enemy) as Dictionary).get("damage_to_hp", 0))
		_landed = 0
		var before: int = int(controller.get("_player_turn"))
		controller.call("end_turn")
		var held: WeakRef = weakref(controller)
		var back: bool = await ProbePlay.wait_until(self, func() -> bool:
			var live: Node = held.get_ref() as Node
			return live == null or not _battle_open() or (int(live.get("_player_turn")) > before and ProbePlay.is_settled(live)), 20.0)
		if not _battle_open() or not is_instance_valid(controller):
			_fail("%s: the fight ended on enemy turn %d" % [label, turn + 1])
			clean = false
			break
		if not back:
			_fail("%s: enemy turn %d never handed the turn back" % [label, turn + 1])
			clean = false
			break
		print("%s: enemy turn %d previewed %d HP, took %d" % [label, turn + 1, previewed, _landed])
		if _landed != previewed:
			_fail("%s: enemy turn %d took %d HP, its previews said %d" % [label, turn + 1, _landed, previewed])
			clean = false
	if clean:
		_fought += 1
		print("%s: fought %d turns" % [label, TURNS])
	await _teardown()

func _on_damage_dealt(source: Variant, target: Variant, amount: int, kind: String) -> void:
	if target is String and str(target) == "player" and source is Node and kind == "attack":
		_landed += amount

# The slot's enemy to make contact with: its anchor, else its first.
func _target_for(slot_id: StringName) -> Node3D:
	var first: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if node.get("slot_id") != slot_id or not _field.is_ancestor_of(node):
			continue
		if bool(node.get("anchor")):
			return node as Node3D
		if first == null:
			first = node as Node3D
	return first

func _battle_open() -> bool:
	return _field != null and is_instance_valid(_field) and bool(_field.get("_battle_open"))

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
