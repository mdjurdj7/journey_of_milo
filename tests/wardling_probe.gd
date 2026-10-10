extends SceneTree

# Headless probe for the Wardling: its loop, its escalation (and that the
# intent preview always equals what lands), its once-per-fight pain turn,
# its data and its place on floor 3. Rules layer and the real .tres; no
# field scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/wardling_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const CASES := 9
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const DRAGONFLY_PATH := "res://battle/rules/enemies/dragonfly.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const SOUND_PATH := "res://assets/audio/enemies_old/Works_Wardling/Ragged Breath.mp3"
const MODEL_PATH := "res://assets/models/enemies/Wardling/Wardling.glb"
const POST_SCENE_PATH := "res://field/hitching_post.tscn"
const WAGON_SCENE_PATH := "res://field/wagon.tscn"
const HEAD_TURN_PATH := "res://field/head_turn.tscn"
# Turns 1-9: 9, 5, 11 looping, times 1.0 / 1.3 / 1.6 / 2.0 by twos, held
# at 2.0 - roundi(11 x 1.3) = 14, roundi(9 x 1.3) = 12, roundi(11 x 1.6)
# = 18.
const ESCALATED: Array[int] = [9, 5, 14, 12, 8, 18, 18, 10, 22]
const STAGES: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3, 3]

var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_check_data()
	_check_loop_order()
	_check_escalation()
	_check_preview_is_what_lands()
	_check_pain_turn_on_players_turn()
	_check_pain_turn_on_its_own_turn()
	_check_no_second_pain_turn()
	_check_others_untouched()
	_check_floor_3()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("wardling_probe: PASSED")
		quit(0)
	else:
		print("wardling_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var data: EnemyData = _wardling()
	_expect_eq(data.enemy_name, "Wardling", "The Wardling's name")
	_expect_eq(data.max_hp, 70, "...70 HP")
	_expect_eq(data.escalation_multipliers, [1.0, 1.3, 1.6, 2.0] as Array[float], "...escalates 1.0 / 1.3 / 1.6 / 2.0")
	_expect_eq(data.escalation_stage_length, 2, "...every 2 turns")
	_expect_eq(data.pain_turn_hp_threshold, 0.5, "...a pain turn below 50%")
	_expect_eq(data.pain_turn_line, "A ragged breath. It isn't moving.", "...its pain line")
	_expect(data.pain_turn_sound != null and data.pain_turn_sound.resource_path == SOUND_PATH, "...the Ragged Breath")
	_expect_eq(data.defeat_line, "The Wardling is still.", "...its defeat line")
	_expect(data.is_elite, "...an elite")
	_expect_eq(data.model_scene_path, MODEL_PATH, "...wears its own model")
	_expect_eq(data.model_scale, 1.68, "...at 1.68")
	_expect_eq(data.contact_radius_m, 2.0, "...the default contact radius")
	_expect_eq(data.harness_point, Vector3(-0.25, 1.15, 0.0), "...a harness for the hitching post's rope")
	_expect_eq(data.attachment_scene_path, HEAD_TURN_PATH, "...turns its head, not its body (HeadTurn)")
	var head_turn: Node = (load(HEAD_TURN_PATH) as PackedScene).instantiate()
	_expect_eq(head_turn.get("max_angle_degrees"), 70.0, "...up to 70 degrees either side")
	_expect_eq(head_turn.get("neck_bones"), 4, "...bent over four neck bones")
	head_turn.free()
	for intent in data.intents:
		_expect_eq(intent.type, EnemyIntent.IntentType.ATTACK, "Every intent is an Attack")
		_expect_eq(intent.hits, 1, "...of one hit")
	_completed += 1

func _check_loop_order() -> void:
	var data: EnemyData = _wardling()
	var values: Array[int] = []
	for intent in data.intents:
		values.append(intent.value)
	_expect_eq(values, [9, 5, 11] as Array[int], "The loop, as authored: 9, 5, 11")
	_expect(not data.erratic_intent_selection, "...in a fixed order")
	var enemy: Combatant = _enemy(data)
	var seen: Array[int] = []
	for turn in 6:
		seen.append(EnemyTurn.current_intent(enemy, data).value)
		EnemyTurn.take_turn(enemy, data, _player())
	_expect_eq(seen, [9, 5, 11, 9, 5, 11] as Array[int], "...repeating")
	_completed += 1

func _check_escalation() -> void:
	var data: EnemyData = _wardling()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var dealt: Array[int] = []
	var stages: Array[int] = []
	for turn in 9:
		stages.append(EnemyTurn.escalation_stage(enemy, data))
		var before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		dealt.append(before - player.hp)
	_expect_eq(dealt, ESCALATED, "Turns 1-9 land 9, 5, 14, 12, 8, 18, 18, 10, 22")
	_expect_eq(stages, STAGES, "...at stages 0, 0, 1, 1, 2, 2, 3, 3, 3 - held at the last")
	_expect_eq(enemy.turns_taken, 9, "...nine turns counted")
	_completed += 1

func _check_preview_is_what_lands() -> void:
	var data: EnemyData = _wardling()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	for turn in 9:
		var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
		var before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		_expect_eq(preview.get("per_hit"), before - player.hp, "Turn %d: the preview shows what lands" % (turn + 1))
		_expect_eq(preview.get("escalation_stage"), STAGES[turn], "Turn %d: the preview's stage" % (turn + 1))
		_expect_eq(preview.get("escalation_stages"), 4, "Turn %d: out of four" % (turn + 1))
	_completed += 1

# The drop on the player's turn - BattleController._report_damage() calls
# EnemyTurn.check_pain_turn() as the hit lands.
func _check_pain_turn_on_players_turn() -> void:
	var data: EnemyData = _wardling()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_turn(enemy, data, player)
	enemy.hp = 35
	_expect(not EnemyTurn.check_pain_turn(enemy, data), "At 35 of 70 - exactly half - no pain turn")
	enemy.hp = 34
	_expect(EnemyTurn.check_pain_turn(enemy, data), "At 34, below half, the pain turn is set")
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview.get("pain_turn", false)), "...the preview shows the cancelled action")
	_expect_eq(preview.get("per_hit"), 0, "...with no number")
	_expect(not bool(preview.get("lethal", true)), "...never lethal")
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result.get("pain_turn", false)), "Turn 3 is the pain turn")
	_expect_eq(player.hp, before, "...and does nothing")
	# Turn 4: the loop moved on past turn 3's 11, and the stage is turn 4's.
	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, ESCALATED[3], "Turn 4 carries on: 12 - the loop and escalation unreset")
	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, ESCALATED[4], "Turn 5: 8")
	_expect_eq(enemy.turns_taken, 5, "...five turns counted, the cancelled one too")
	_completed += 1

# The drop between turns that no hit announced (a countdown at its turn's
# start, say): take_turn() finds it and cancels that same turn's action.
func _check_pain_turn_on_its_own_turn() -> void:
	var data: EnemyData = _wardling()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	enemy.hp = 30
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result.get("pain_turn_triggered", false)), "Found below half at its own turn: set there")
	_expect(bool(result.get("pain_turn", false)), "...and that turn's action is the one cancelled")
	_expect_eq(player.hp, before, "...doing nothing")
	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, ESCALATED[1], "The next turn is turn 2's 5")
	_completed += 1

func _check_no_second_pain_turn() -> void:
	var data: EnemyData = _wardling()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	enemy.hp = 30
	_expect(EnemyTurn.check_pain_turn(enemy, data), "First crossing: a pain turn")
	EnemyTurn.take_turn(enemy, data, player)
	enemy.hp = 70
	_expect(not EnemyTurn.check_pain_turn(enemy, data), "Healed above half: nothing")
	enemy.hp = 20
	_expect(not EnemyTurn.check_pain_turn(enemy, data), "A second crossing: no second pain turn")
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(not bool(result.get("pain_turn", false)), "...its next turn acts")
	_expect_eq(before - player.hp, ESCALATED[1], "...for turn 2's 5")
	_completed += 1

# The defaults leave everyone else as they were: no escalation in their
# previews, their numbers as authored, no pain turn at any HP.
func _check_others_untouched() -> void:
	for path in [SPUTTER_PATH, DRAGONFLY_PATH]:
		var data := load(path) as EnemyData
		var enemy: Combatant = _enemy(data)
		var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, _player())
		_expect(not preview.has("escalation_stage") and not preview.has("escalation_stages"), "%s's preview carries no escalation" % data.enemy_name)
		for turn in 7:
			var intent: EnemyIntent = EnemyTurn.current_intent(enemy, data)
			_expect_eq(EnemyTurn.intent_value(enemy, data, intent), intent.value, "%s turn %d: its value as authored" % [data.enemy_name, turn + 1])
			enemy.turns_taken += 1
		enemy.hp = 1
		_expect(not EnemyTurn.check_pain_turn(enemy, data), "%s never has a pain turn" % data.enemy_name)
		_expect(not data.is_elite, "%s isn't elite" % data.enemy_name)
		_expect(data.attachment_scene_path != HEAD_TURN_PATH, "%s turns no head" % data.enemy_name)
	_completed += 1

func _check_floor_3() -> void:
	var floor_data := load(FLOOR_3_PATH) as Resource
	var slots: Array = floor_data.get("slots")
	_expect_eq(slots.size(), 2, "Floor 3 has two encounter slots")
	var first: Resource = ((slots[0].get("options") as Array)[0].get("members") as Array)[0]
	_expect_eq((first.get("enemy_data") as EnemyData).enemy_name, "Blackback", "...the required Blackback's first - the gate measures from it")
	var slot: Resource = slots[1]
	var option: Resource = (slot.get("options") as Array)[0]
	var entry: Resource = (option.get("members") as Array)[0]
	_expect_eq((entry.get("enemy_data") as EnemyData).enemy_name, "Wardling", "...then the Wardling's")
	_expect_eq(slot.call("to_floor", entry.get("position")), Vector2(17.6, -13.6), "...in the east lobe at (17.6, -13.6)")
	_expect_eq(entry.get("face_prop_index"), 0, "...facing its encounter's first prop")
	_expect_eq(float(slot.get("yaw_degrees")) + float(entry.get("yaw_degrees")), 0.0, "...straight at it")
	_expect(not bool(slot.get("required")), "...not required")
	var props: Array = option.get("props")
	_expect_eq(props.size(), 1, "The Wardling's encounter has one prop")
	if props.size() == 1:
		_expect_eq((props[0].get("scene") as PackedScene).resource_path, POST_SCENE_PATH, "...the hitching post")
		var post: Vector3 = props[0].get("position")
		_expect_eq(slot.call("to_floor", Vector2(post.x, post.z)), Vector2(15.879, -16.057), "...north-west of the Wardling, 3.0 m off")
		_expect_eq((props[0].get("overrides") as Dictionary).get("tether_member_index"), 0, "...its rope tied to the Wardling, its encounter's first member")
	var floor_props: Array = floor_data.get("props")
	_expect_eq(floor_props.size(), 1, "Floor 3 has one prop of its own")
	if floor_props.size() == 1:
		_expect_eq((floor_props[0].get("scene") as PackedScene).resource_path, WAGON_SCENE_PATH, "...the wagon")
	_completed += 1

# --- Helpers ---

func _wardling() -> EnemyData:
	return load(WARDLING_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _player() -> Combatant:
	return Combatant.new(500)

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
