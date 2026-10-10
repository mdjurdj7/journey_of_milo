extends SceneTree

# Headless probe for encounter slots and their roll (EncounterSlot,
# EncounterOption, RegionField._resolve_encounters()), on a test fixture
# floor - floor 1's land with one slot of two options, never a real
# floor's encounters:
#
#   seed     - the same stream seed stands the same option, twice
#   seeds    - different seeds can stand different options (both stand
#              across SEEDS seeds), and the field stands what the slot's
#              own stream picks for the run's seed
#   force    - RegionField.force_options stands the named option, either
#   props    - an option's props stand only with it: the bones with one,
#              the hull with the other, never both
#   repeat   - a run never stands an option twice: one already stood
#              elsewhere (RunState.encounter_rolls) is passed over
#   rng      - the roll leaves RunState.rng exactly where it was
#   role     - a slot whose options are fought as different roles fails
#              validation, and the field stands nothing in it
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/encounter_slots_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# BattleController, the props' own scripts).

const CASES := 7
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BASE_FLOOR_PATH := "res://floors/region1_floor1.tres"
const BATTLE_CONTROLLER_PATH := "res://battle/battle_controller.gd"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const ADDER_PATH := "res://battle/rules/enemies/adder.tres"
const BONES_SCENE_PATH := "res://field/bone_scatter.tscn"
const HULL_SCENE_PATH := "res://field/hull.tscn"
const SLOT_ID := &"fixture"
const OPTION_A := &"fixture_sputter"
const OPTION_B := &"fixture_siltjaw"
const OPTION_ELITE := &"fixture_adder"
# Floor 1's own crab anchor: dry land, and the gate measures from it.
const ANCHOR := Vector2(-2.25, -10.73)
# Where each option's one prop stands, in the slot's frame.
const PROP_AT := Vector3(2.0, 0.0, -1.5)
const SEEDS := 64
const SETTLE_FRAMES := 10
const SAFETY_SECONDS := 240.0

var _run_state: Node = null
var _failures: int = 0
var _completed: int = 0
# Run seeds whose roll stands A, and B (_check_seeds()).
var _seed_for_a: int = -1
var _seed_for_b: int = -1

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_run_state.call("new_run", load(CHARACTER_PATH))
	_check_seed()
	_check_seeds()
	await _check_field_roll()
	await _check_force_and_props()
	await _check_repeat()
	await _check_rng()
	await _check_role()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("encounter_slots_probe: PASSED")
		quit(0)
	else:
		print("encounter_slots_probe: %d FAILED" % _failures)
		quit(1)

# --- Cases ---

func _check_seed() -> void:
	var slot := _fixture_slot(SILTJAW_PATH)
	var none: Array[StringName] = []
	for stream_seed in [1, 77, 123456789]:
		var first: EncounterOption = slot.pick(stream_seed, none)
		var second: EncounterOption = slot.pick(stream_seed, none)
		_expect(first != null and first == second, "Seed %d stands the same option twice (%s)" % [stream_seed, first.option_id if first != null else &"none"])
	var single := EncounterSlot.new()
	single.slot_id = &"single"
	single.options = [slot.options[0]] as Array[EncounterOption]
	_expect(single.pick(5, none) == slot.options[0], "A slot of one option stands it")
	_completed += 1

func _check_seeds() -> void:
	var slot := _fixture_slot(SILTJAW_PATH)
	var none: Array[StringName] = []
	for run_seed in SEEDS:
		var picked: EncounterOption = slot.pick(slot.stream_seed(run_seed, 0, 0), none)
		if picked.option_id == OPTION_A and _seed_for_a < 0:
			_seed_for_a = run_seed
		elif picked.option_id == OPTION_B and _seed_for_b < 0:
			_seed_for_b = run_seed
	_expect(_seed_for_a >= 0 and _seed_for_b >= 0, "Across %d run seeds both options stand (A at seed %d, B at seed %d)" % [SEEDS, _seed_for_a, _seed_for_b])
	_expect(slot.stream_seed(1, 0, 0) != slot.stream_seed(1, 0, 1), "...the stream differs by floor")
	_expect(slot.stream_seed(1, 0, 0) != slot.stream_seed(2, 0, 0), "...and by run seed")
	_completed += 1

# The field rolls with the slot's own stream: what pick() says for the
# run's seed is what stands.
func _check_field_roll() -> void:
	for pair in [[_seed_for_a, OPTION_A], [_seed_for_b, OPTION_B]]:
		if int(pair[0]) < 0:
			_fail("no seed for %s to load the field with" % pair[1])
			continue
		_clear_rolls()
		var field: Node = await _load_field(_fixture_slot(SILTJAW_PATH), int(pair[0]), {})
		_expect_eq(_stood(field), [pair[1]], "Run seed %d: the field stands %s" % [pair[0], pair[1]])
		await _teardown(field)
	_completed += 1

func _check_force_and_props() -> void:
	for forced: StringName in [OPTION_A, OPTION_B]:
		# The seed that would roll the OTHER option, so only the force explains it.
		var against: int = _seed_for_b if forced == OPTION_A else _seed_for_a
		var force: Dictionary[StringName, StringName] = {SLOT_ID: forced}
		_clear_rolls()
		var field: Node = await _load_field(_fixture_slot(SILTJAW_PATH), against, force)
		_expect_eq(_stood(field), [forced], "force_options {%s: %s} stands it against a roll for the other" % [SLOT_ID, forced])
		var props: Array[String] = _prop_scripts(field)
		var expected: Array[String] = ["bone_scatter.gd" if forced == OPTION_A else "hull.gd"]
		_expect_eq(props, expected, "...and only its own prop stands (%s)" % ", ".join(props))
		await _teardown(field)
	_completed += 1

# A: stood elsewhere this run already - the seed that would roll it rolls
# B instead; and the floor stood again stands what it stood.
func _check_repeat() -> void:
	var slot := _fixture_slot(SILTJAW_PATH)
	var taken: Array[StringName] = [OPTION_A]
	var passed_over: bool = true
	for run_seed in SEEDS:
		if slot.pick(slot.stream_seed(run_seed, 0, 0), taken).option_id != OPTION_B:
			passed_over = false
	_expect(passed_over, "With A taken, every one of %d seeds stands B" % SEEDS)
	var both: Array[StringName] = [OPTION_A, OPTION_B]
	_expect(slot.pick(3, both) != null, "...and with both taken it still stands one")

	_clear_rolls()
	(_run_state.get("encounter_rolls") as Dictionary)["0:3:elsewhere"] = OPTION_A
	var field: Node = await _load_field(slot, _seed_for_a, {})
	_expect_eq(_stood(field), [OPTION_B], "The field passes over A, stood on another floor this run, for B")
	await _teardown(field)
	field = await _load_field(_fixture_slot(SILTJAW_PATH), _seed_for_a, {})
	_expect_eq(_stood(field), [OPTION_B], "...and stands B again when the same floor is stood again")
	await _teardown(field)
	_clear_rolls()
	_completed += 1

func _check_rng() -> void:
	var rng: RandomNumberGenerator = _run_state.get("rng")
	rng.seed = 991
	_clear_rolls()
	var field: Node = await _load_field(_fixture_slot(SILTJAW_PATH), _seed_for_b, {})
	var before: int = rng.state
	_clear_rolls()
	field.call("_resolve_encounters")
	_expect_eq(rng.state, before, "Rolling the floor's slots leaves RunState.rng's state as it was")
	var reference := RandomNumberGenerator.new()
	reference.seed = 991
	reference.state = before
	_expect_eq(rng.randi(), reference.randi(), "...its next draw the one it would have been")
	await _teardown(field)
	_clear_rolls()
	_completed += 1

func _check_role() -> void:
	var rule := Callable(load(BATTLE_CONTROLLER_PATH) as GDScript, "encounter_role")
	_expect_eq(_fixture_slot(SILTJAW_PATH).validate(rule), "", "A slot of two required fights validates")
	var mixed := _fixture_slot(ADDER_PATH, OPTION_ELITE)
	var problem: String = mixed.validate(rule)
	_expect(problem.contains("required") and problem.contains("elite"), "A slot of a required fight and an elite one fails validation: \"%s\"" % problem)
	_clear_rolls()
	var field: Node = await _load_field(mixed, _seed_for_a, {})
	_expect_eq(_stood(field), [] as Array[StringName], "...and the field stands nothing in it")
	await _teardown(field)
	_completed += 1

# --- Fixture ---

# One required slot at floor 1's crab anchor: A, a Sputter with the bones
# beside it; the other, `second_path`'s enemy with a hull beside it.
func _fixture_slot(second_path: String, second_id: StringName = OPTION_B) -> EncounterSlot:
	var slot := EncounterSlot.new()
	slot.slot_id = SLOT_ID
	slot.position = ANCHOR
	slot.required = true
	slot.options = [_option(OPTION_A, SPUTTER_PATH, BONES_SCENE_PATH), _option(second_id, second_path, HULL_SCENE_PATH)] as Array[EncounterOption]
	return slot

func _option(option_id: StringName, enemy_path: String, prop_scene_path: String) -> EncounterOption:
	var member := FloorEnemy.new()
	member.enemy_data = load(enemy_path) as EnemyData
	var prop := FloorProp.new()
	prop.scene = load(prop_scene_path) as PackedScene
	prop.position = PROP_AT
	var option := EncounterOption.new()
	option.option_id = option_id
	option.members = [member] as Array[FloorEnemy]
	option.props = [prop] as Array[FloorProp]
	return option

# Floor 1's land with `slot` its only encounter and no props of its own -
# nothing on it draws from RunState.rng as it loads.
func _fixture_floor(slot: EncounterSlot) -> FloorData:
	var floor_data := (load(BASE_FLOOR_PATH) as FloorData).duplicate() as FloorData
	floor_data.slots = [slot] as Array[EncounterSlot]
	floor_data.props = [] as Array[FloorProp]
	return floor_data

func _load_field(slot: EncounterSlot, run_seed: int, force: Dictionary) -> Node:
	var region := RegionData.new()
	region.display_name = "Fixture"
	region.floors = [_fixture_floor(slot)] as Array[FloorData]
	_run_state.set("current_region_index", 0)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_seed", run_seed)
	_run_state.set("run_opening_pending", false)
	var field: Node = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	field.set("region", region)
	field.set("run_logging_enabled", false)
	if not force.is_empty():
		var typed: Dictionary[StringName, StringName] = {}
		for key in force:
			typed[StringName(key)] = StringName(force[key])
		field.set("force_options", typed)
	root.add_child(field)
	for i in SETTLE_FRAMES:
		await physics_frame
	return field

# What this run has stood, forgotten - each case rolls fresh.
func _clear_rolls() -> void:
	(_run_state.get("encounter_rolls") as Dictionary).clear()

func _teardown(field: Node) -> void:
	field.queue_free()
	for i in 3:
		await process_frame

# The option ids the field's enemies were spawned from, in spawn order.
func _stood(field: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for node in field.get_tree().get_nodes_in_group("enemies"):
		if field.is_ancestor_of(node) and not node.is_queued_for_deletion():
			ids.append(node.get("option_id"))
	return ids

# The script file of every prop standing under the field's Props node.
func _prop_scripts(field: Node) -> Array[String]:
	var found: Array[String] = []
	var props: Node = field.get_node_or_null(^"Props")
	if props == null:
		return found
	for child in props.get_children():
		var script: Script = child.get_script()
		found.append(script.resource_path.get_file() if script != null else child.name)
	return found

# --- Helpers ---

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ok: %s" % label)
	else:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("ok: %s" % label)
	else:
		_fail("%s - expected %s, got %s" % [label, expected, actual])

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: %s" % label)
