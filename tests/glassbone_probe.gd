extends SceneTree

# Headless probe for Glassbone, the run's one material: RunState's count
# and its helpers, that it lives exactly as long as the run (across a
# fight, across a floor, gone on a new run), that the Wardling leaves one
# piece as its own TAKE line on the reward screen - taken, or left behind
# on WALK ON, never granted on its own - that an enemy leaves any only if
# it is an elite or a region-end enemy (a required fight on its region's
# last floor - the Greyshelf), every enemy's data checked against that,
# that the gold, card and keepsake rewards around it are unchanged, and
# the field HUD's GLASSBONE line.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/glassbone_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Field cases load the real region scene and start fights through
# RegionField's contact handler, the way trinket_probe does. Untyped
# against anything that names the RunState autoload (RegionField,
# RewardScreen, the HUD lines): a SceneTree script compiles before the
# autoloads register.

const CASES := 8
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const ENEMIES_DIR := "res://battle/rules/enemies"
# Where the regions are: every RegionData here names its floors in order.
const FLOORS_DIR := "res://floors"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
# Floor 3 (index 2) is the Wardling's; floor 1 (index 0) the lone Sputter's.
const WARDLING_FLOOR := 2
const SPUTTER_FLOOR := 0
const SAFETY_SECONDS := 300.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0

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
	_check_counting()
	_check_enemy_data()
	await _check_floor_advance()
	await _check_wardling_take()
	await _check_wardling_walk_on()
	await _check_sputter_leaves_none()
	await _check_hud_line()
	await _check_hud_hides_for_fight()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("glassbone_probe: PASSED")
		quit(0)
	else:
		print("glassbone_probe: %d FAILED" % _failures)
		quit(1)

# Starts at 0, adds, accumulates, never below 0, all-or-nothing spend,
# and new_run() puts it back to 0.
func _check_counting() -> void:
	_new_run()
	_expect_eq(_glassbone(), 0, "A new run starts on 0 Glassbone")
	_run_state.call("add_glassbone", 1)
	_expect_eq(_glassbone(), 1, "Adding 1 gives 1")
	_run_state.call("add_glassbone", 1)
	_run_state.call("add_glassbone", 2)
	_expect_eq(_glassbone(), 4, "Grants accumulate (1 + 1 + 2)")
	_run_state.call("add_glassbone", 0)
	_run_state.call("add_glassbone", -3)
	_expect_eq(_glassbone(), 4, "Adding 0 or less changes nothing")
	_expect(not _run_state.call("spend_glassbone", 5), "Spending more than is held is refused")
	_expect_eq(_glassbone(), 4, "...and takes nothing")
	_expect(not _run_state.call("spend_glassbone", -1), "Spending 0 or less is refused")
	_expect(_run_state.call("spend_glassbone", 4), "Spending exactly what is held works")
	_expect_eq(_glassbone(), 0, "...down to 0, never below")
	_run_state.call("add_glassbone", 3)
	_new_run()
	_expect_eq(_glassbone(), 0, "A new run resets it to 0")
	_completed += 1

# An enemy may leave Glassbone only if it is an elite (EnemyData.is_
# elite) or a region-end enemy: every enemy's data under ENEMIES_DIR
# that leaves any is one or the other.
func _check_enemy_data() -> void:
	var region_end: Array[String] = _region_end_enemies()
	_expect(not region_end.is_empty(), "Some region has a region-end enemy (%s)" % str(region_end))
	var dir := DirAccess.open(ENEMIES_DIR)
	var checked: int = 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var path: String = ENEMIES_DIR.path_join(file)
		var data: Resource = load(path)
		if data == null or data.get("glassbone_reward") == null:
			continue
		checked += 1
		var reward: int = int(data.get("glassbone_reward"))
		if reward > 0:
			var elite: bool = bool(data.get("is_elite"))
			_expect(elite or region_end.has(path), "%s leaves %d Glassbone, so it's an elite or a region-end enemy" % [file, reward])
	_expect(checked >= 2, "More than one enemy's data was checked (%d)" % checked)
	_completed += 1

# The region-end enemies: each required enemy (FloorEnemy.required) on
# the last floor of a region - every RegionData under FLOORS_DIR - by
# its EnemyData's path.
func _region_end_enemies() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(FLOORS_DIR)
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var region: Resource = load(FLOORS_DIR.path_join(file))
		if region == null or region.get_script() == null or (region.get_script() as Script).get_global_name() != &"RegionData":
			continue
		var floors: Array = region.get("floors")
		if floors.is_empty() or floors.back() == null:
			continue
		for entry: Resource in floors.back().get("enemies"):
			if entry == null or not bool(entry.get("required")) or entry.get("enemy_data") == null:
				continue
			var path: String = (entry.get("enemy_data") as Resource).resource_path
			if not found.has(path):
				found.append(path)
	return found

# What a floor advance does (RegionField._on_floor_exited() reloads the
# scene); the count is RunState's, so it rides through.
func _check_floor_advance() -> void:
	_new_run()
	_run_state.call("add_glassbone", 2)
	await _load_field(0)
	current_scene = _field
	await _field.call("_on_floor_exited")
	for i in 10:
		await process_frame
	_expect_eq(int(_run_state.get("current_floor_index")), 1, "The floor exit lands on floor 2")
	_expect_eq(_glassbone(), 2, "Glassbone carries across the floor advance")
	var reloaded: Node = current_scene
	if reloaded != null:
		reloaded.queue_free()
	current_scene = null
	_field = null
	for i in 5:
		await process_frame
	_completed += 1

# Win against the Wardling: nothing granted by the win itself; the reward
# screen offers gold, Glassbone x1 and a card, in that order; TAKE on the
# Glassbone line adds exactly 1, once, and moves nothing else; the
# keepsake offer still follows the screen.
func _check_wardling_take() -> void:
	_new_run()
	_run_state.call("add_glassbone", 2)
	var controller: Node = await _start_fight(WARDLING_FLOOR, WARDLING_PATH)
	if controller == null:
		await _teardown()
		_completed += 1
		return
	_expect_eq(_glassbone(), 2, "A fight starting leaves the count alone")
	_kill_all(controller)
	_expect_eq(_glassbone(), 2, "The win itself grants nothing")
	await _await_reward_screen()
	_expect_eq(_glassbone(), 2, "...nor the fight's end - it waits on the reward screen")
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	_expect(reward != null, "Killing the Wardling opens the reward screen")
	if reward != null:
		var ids: Array[String] = _line_ids(reward)
		_expect_eq(ids, ["gold", "glassbone", "card"] as Array[String], "...gold, Glassbone, a card")
		var index: int = ids.find("glassbone")
		if index >= 0:
			var line: RefCounted = (reward.get("_lines") as Array)[index]
			_expect_eq(str(line.get("item")), "Glassbone ×1", "...the line reads Glassbone ×1")
			_expect_eq(str(line.get("action")), "TAKE", "...with TAKE")
			_expect(line.get("icon") != null and line.get("shard_glyph") == false, "...drawn with the Glassbone art, not the placeholder shard")
			var gold_before: int = int(_run_state.get("gold"))
			var deck_before: int = (_run_state.get("deck") as Array).size()
			reward.call("_take_line", index)
			_expect_eq(_glassbone(), 3, "TAKE adds exactly 1 (2 -> 3)")
			_expect_eq(int(_run_state.get("gold")), gold_before, "...and no gold")
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before, "...and no card")
			reward.call("_take_line", index)
			_expect_eq(_glassbone(), 3, "A taken line can't be taken twice")
			_expect(is_instance_valid(reward) and not reward.is_queued_for_deletion(), "...and the screen stays up for the gold and the card")
		var gold_index: int = ids.find("gold")
		if gold_index >= 0:
			var gold_before_take: int = int(_run_state.get("gold"))
			reward.call("_take_line", gold_index)
			_expect(int(_run_state.get("gold")) > gold_before_take, "The gold line still pays gold")
			_expect_eq(_glassbone(), 3, "...and no Glassbone")
		if is_instance_valid(reward):
			reward.call("close")
		await process_frame
		_expect(_child_with_script(_field, "keepsake_offer.gd") != null, "The Wardling's keepsake offer still follows the screen")
	await _teardown()
	_completed += 1

# WALK ON with the line untaken: the piece is left behind.
func _check_wardling_walk_on() -> void:
	_new_run()
	var controller: Node = await _start_fight(WARDLING_FLOOR, WARDLING_PATH)
	if controller == null:
		await _teardown()
		_completed += 1
		return
	_kill_all(controller)
	await _await_reward_screen()
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	_expect(reward != null, "The Wardling's reward screen opens again")
	if reward != null:
		_expect(_line_ids(reward).has("glassbone"), "...with its Glassbone line")
		reward.call("_on_dismiss")
		await process_frame
		_expect(not is_instance_valid(reward) or reward.is_queued_for_deletion(), "WALK ON closes the screen")
		_expect_eq(_glassbone(), 0, "...and the untaken Glassbone is left behind")
	await _teardown()
	_completed += 1

# An ordinary enemy: gold and a card, as before; no Glassbone line.
func _check_sputter_leaves_none() -> void:
	_new_run()
	var controller: Node = await _start_fight(SPUTTER_FLOOR, "")
	if controller == null:
		await _teardown()
		_completed += 1
		return
	_kill_all(controller)
	await _await_reward_screen()
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	_expect(reward != null, "Killing the Sputter opens the reward screen")
	if reward != null:
		_expect_eq(_line_ids(reward), ["gold", "card"] as Array[String], "...gold and a card, no Glassbone line")
		reward.call("close")
	await process_frame
	_expect_eq(_glassbone(), 0, "An ordinary enemy grants no Glassbone")
	await _teardown()
	_completed += 1

# GLASSBONE: hidden on 0, shown from the first piece with its count,
# beside GOLD, the last resource - a keepsake taken after sits past it
# and doesn't move it.
func _check_hud_line() -> void:
	_new_run()
	await _load_field(0)
	var line: Control = _field.get_node("FieldHUD/GlassboneLine")
	var hp_line: Control = _field.get_node("FieldHUD/HPLine")
	var gold_line: Control = _field.get_node("FieldHUD/GoldLine")
	var keepsake_line: Control = _field.get_node("FieldHUD/KeepsakeLine")
	_expect(not line.visible, "GLASSBONE is hidden on 0")
	_run_state.call("add_glassbone", 1)
	_expect(line.visible, "...shown from the first piece")
	var count_sec: float = float((line.get("style") as Resource).get("hud_count_sec"))
	await create_timer(count_sec + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "1", "...reading 1 once its count lands")
	_expect_eq(str(line.get("label_text")), "GLASSBONE", "...under the label GLASSBONE")
	var gold_right: float = gold_line.position.x + gold_line.size.x
	_expect(line.position.x > gold_right and line.position.x < gold_right + 40.0, "...right beside GOLD")
	var glassbone_x: float = line.position.x
	_run_state.call("add_glassbone", 1)
	await create_timer(count_sec + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "2", "...and counts on to 2")
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	await process_frame
	_expect(keepsake_line.visible, "KEEPSAKE shows once one is held")
	_expect(keepsake_line.position.x > line.position.x + line.size.x, "...past GLASSBONE")
	_expect_eq(line.position.x, glassbone_x, "...and GLASSBONE never moved")
	_expect_eq(line.position.y + line.size.y, hp_line.position.y + hp_line.size.y, "...on the same bottom edge as HP")
	await _teardown()
	_completed += 1

# The field row goes for a fight - GLASSBONE with it, even while it sits
# past a hidden KEEPSAKE - and comes back after.
func _check_hud_hides_for_fight() -> void:
	_new_run()
	_run_state.call("add_glassbone", 1)
	var controller: Node = await _start_fight(SPUTTER_FLOOR, "")
	if controller == null:
		await _teardown()
		_completed += 1
		return
	var line: Control = _field.get_node("FieldHUD/GlassboneLine")
	var hp_line: Control = _field.get_node("FieldHUD/HPLine")
	_expect(not hp_line.visible, "The row's HP hides for the fight")
	_expect(not line.visible, "...and GLASSBONE with it")
	_kill_all(controller)
	await _await_reward_screen()
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	if reward != null:
		reward.call("close")
	for i in 5:
		await process_frame
	_expect(hp_line.visible, "HP is back after the fight")
	_expect(line.visible, "...and GLASSBONE with it")
	_expect_eq(_glassbone(), 1, "The count came through the fight")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _glassbone() -> int:
	return int(_run_state.get("glassbone"))

func _line_ids(reward: Node) -> Array[String]:
	var ids: Array[String] = []
	for line in reward.get("_lines") as Array:
		ids.append(str((line as RefCounted).get("id")))
	return ids

func _load_field(floor_index: int) -> void:
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

# Loads the floor and starts a fight with the first enemy whose data is
# `enemy_path` (or the first ungrouped enemy, for ""). The fight's
# BattleController, or null (a FAIL is recorded).
func _start_fight(floor_index: int, enemy_path: String) -> Node:
	await _load_field(floor_index)
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if enemy_path != "":
			var data: Resource = node.get("enemy_data")
			if data != null and data.resource_path == enemy_path:
				target = node as Node3D
				break
		elif node.get("group") == &"":
			target = node as Node3D
			break
	if target == null:
		_fail("no enemy to fight on floor %d ('%s')" % [floor_index + 1, enemy_path])
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
		_fail("no fight started on floor %d" % (floor_index + 1))
		return null
	return overlay.get("battle_controller")

# Every member to 0 through the controller's own damage path, then the
# end check - kill_order_probe's _kill().
func _kill_all(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: RefCounted = combatants.get(member)
		if combatant == null:
			continue
		combatant.set("hp", 0)
		controller.call("_report_damage", "player", combatant, 99, "card")
	controller.call("_check_battle_end")

# A fight just won: until its reward screen is up - the killing blow and
# the last death play out first - or REWARD_WAIT_SECONDS have gone.
func _await_reward_screen() -> void:
	var start: int = Time.get_ticks_msec()
	while _child_with_script(_field, "reward_screen.gd") == null and Time.get_ticks_msec() - start < int(REWARD_WAIT_SECONDS * 1000.0):
		await process_frame

func _child_with_script(parent: Node, suffix: String) -> Node:
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 2:
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
