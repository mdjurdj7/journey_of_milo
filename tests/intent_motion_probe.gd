extends SceneTree

# Headless probe for the per-intent move (EnemyIntent.motion): the enemy
# turn hands each intent's move to the body (FieldEnemy.play_intent_
# motion()), which its attachment plays (play_motion()) - an Attack's in
# place of the lunge, a Defend's as its Block goes up - once per time the
# turn carries the intent out, so twice under a repeat (StatusData.
# repeats_intent). What the intent does is unchanged: the damage and the
# Block land as before. A body with no such move answers -1, and an empty
# move is never asked for.
#
# The fight is floor 1's Sputter, through BattleController's own end_
# turn(); its Block and Strike are given moves for the probe (the loaded
# EnemyData, put back after), and its attachment is a recorder.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/intent_motion_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against what names the RunState autoload, as the other fight
# probes are.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const BLOCK := 0
const STRIKE := 1
const PLAYER_HP := 999
const SAFETY_SECONDS := 240.0
const RECORDER_SOURCE := """extends Node3D
var moves: Array[StringName] = []
func play_motion(motion: StringName, _target: Node3D) -> float:
	moves.append(motion)
	return 0.05
"""

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var data := load(SPUTTER_PATH) as EnemyData
	var authored: Array[StringName] = []
	for intent in data.intents:
		authored.append(intent.motion)
	_expect_eq(authored, [&"", &"", &""] as Array[StringName], "The Sputter's intents name no move")
	data.intents[BLOCK].motion = &"bow"
	data.intents[STRIKE].motion = &"step"
	await _check_turn(STRIKE, 1, [&"step"])
	await _check_turn(STRIKE, 2, [&"step", &"step"])
	await _check_turn(BLOCK, 1, [&"bow"])
	await _check_turn(BLOCK, 2, [&"bow", &"bow"])
	await _check_no_move()
	for intent in data.intents:
		intent.motion = &""
	if _failures == 0:
		print("intent_motion_probe: PASSED")
		quit(0)
	else:
		print("intent_motion_probe: %d FAILED" % _failures)
		quit(1)

# One enemy turn with `index` queued and its intent carried out `times`
# times: the moves the recorder heard, and what the intent did.
func _check_turn(index: int, times: int, expected: Array) -> void:
	var controller: Node = await _start_fight()
	if controller == null:
		return
	var sputter: Node = (controller.get("enemies") as Array)[0]
	var combatant: Combatant = (controller.get("_combatants") as Dictionary).get(sputter)
	var recorder: Node = _recorder(sputter)
	combatant.current_intent_index = index
	if times > 1:
		var repeat := StatusData.new()
		repeat.id = "probe_repeat"
		repeat.category = StatusData.Category.INFORMATIONAL
		repeat.default_duration_turns = -1
		repeat.repeats_intent = times
		Status.apply_to(combatant.statuses, repeat)
	var intent: EnemyIntent = (sputter.get("enemy_data") as EnemyData).intents[index]
	var player: Combatant = controller.get("player")
	var hp_before: int = player.hp
	var block_before: int = combatant.block
	await controller.call("end_turn")
	var label: String = "%s x%d" % [intent.intent_name, times]
	_expect_eq(recorder.get("moves"), expected, "%s: the body is handed its move %d time(s)" % [label, times])
	if intent.type == EnemyIntent.IntentType.ATTACK:
		_expect(hp_before - player.hp > 0, "%s: ...and the attack still lands (%d)" % [label, hp_before - player.hp])
	else:
		_expect_eq(combatant.block - block_before, intent.value * times, "%s: ...and its Block goes up %d" % [label, intent.value * times])
	await _teardown()

# A body whose attachment has no move answers -1; an empty move is never
# asked for.
func _check_no_move() -> void:
	var controller: Node = await _start_fight()
	if controller == null:
		return
	var sputter: Node = (controller.get("enemies") as Array)[0]
	var plain := Node3D.new()
	sputter.add_child(plain)
	sputter.set("_attachment", plain)
	_expect_eq(float(sputter.call("play_intent_motion", &"step", null)), -1.0, "No move on the body: -1")
	var recorder: Node = _recorder(sputter)
	_expect_eq(float(sputter.call("play_intent_motion", &"", null)), -1.0, "An empty move: -1")
	_expect_eq((recorder.get("moves") as Array).size(), 0, "...never asked for")
	await _teardown()

func _recorder(enemy: Node) -> Node:
	var script := GDScript.new()
	script.source_code = RECORDER_SOURCE
	script.reload()
	var recorder := Node3D.new()
	recorder.set_script(script)
	enemy.add_child(recorder)
	enemy.set("_attachment", recorder)
	_expect(enemy.get("_attachment") == recorder, "The recorder is the body's attachment")
	return recorder

func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == SPUTTER_PATH:
			target = node as Node3D
	if target == null:
		_fail("no Sputter on floor 1")
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
		_fail("no fight started on floor 1")
		return null
	await create_timer(2.5).timeout
	return overlay.get("battle_controller")

func _teardown() -> void:
	if _field != null:
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
