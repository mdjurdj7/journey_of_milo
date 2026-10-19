extends SceneTree

# Headless probe for a status that repeats its holder's intent
# (StatusData.repeats_intent - Bereft's 2): rules only, on an enemy built
# here with a fixed loop Bow (Defend 4), Step (Attack 6), Leap (Attack
# 10). Held, a Defend gains its Block twice and an Attack lands as two
# separate attacks - previewed and resolved alike, each attack its own
# entry in the turn's "actions", the loop advancing once. The preview's
# lethal flag and the player's Block are read across both attacks, and
# a status an attack spends (Garnished on the enemy) softens each of
# them, as garnish_probe has it. Without it every turn is as it always was.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/repeat_intent_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const GARNISHED_PATH := "res://battle/rules/statuses/garnished.tres"
const PLAYER_HP := 999

var _failures: int = 0

func _initialize() -> void:
	_check_once()
	_check_twice()
	_check_lethal_and_block()
	_check_garnish_each_action()
	if _failures == 0:
		print("repeat_intent_probe: PASSED")
		quit(0)
	else:
		print("repeat_intent_probe: %d FAILED" % _failures)
		quit(1)

# No repeat: Bow 4, Step 6, Leap 10, one action each, the loop in order.
func _check_once() -> void:
	var data := _crane()
	var enemy := _enemy(data)
	var player := Combatant.new(PLAYER_HP)
	_expect_eq(EnemyTurn.repeats(enemy, EnemyTurn.current_intent(enemy, data)), 1, "Unheld: once")
	var bow: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(bow["block_gained"]), 4, "Bow: 4 Block")
	var step_preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect(not step_preview.has("repeats"), "Step: no repeats in the preview")
	_expect_eq(int(step_preview["hits"]), 1, "...one hit")
	var step: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(step["damage_to_hp"]), 6, "Step: 6")
	_expect_eq((step["actions"] as Array).size(), 1, "...one action")
	_expect_eq(int(EnemyTurn.take_turn(enemy, data, player)["damage_to_hp"]), 10, "Leap: 10")
	_expect_eq(int(EnemyTurn.take_turn(enemy, data, player)["block_gained"]), 4, "...and Bow again")

# Held: Bow 8 in one turn, Step 6 and 6 as two attacks, Leap 10 and 10 -
# previews equal to what lands, the loop one step per turn.
func _check_twice() -> void:
	var data := _crane()
	var enemy := _enemy(data)
	Status.apply_to(enemy.statuses, _bereft())
	var player := Combatant.new(PLAYER_HP)
	var bow_preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(int(bow_preview.get("repeats", 1)), 2, "Held: Bow previews twice")
	_expect_eq(int(bow_preview["per_hit"]), 8, "...as 8 Block")
	var bow: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(bow["block_gained"]), 8, "...and gains 8")
	_expect_eq(enemy.block, 8, "...its Block 8")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Step", "...then the loop moves one step, to Step")
	var step_preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(step_preview["hits"]), int(step_preview["per_hit"])], [2, 6], "Step previews 6x2")
	_expect_eq(step_preview["hit_amounts"], [6, 6], "...hit by hit")
	_expect_eq(int(step_preview["damage_to_hp"]), 12, "...12 in all")
	var hp_before: int = player.hp
	var step: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	var actions: Array = step["actions"]
	_expect_eq(actions.size(), 2, "Step lands as two attacks")
	_expect_eq([int(actions[0]["damage_to_hp"]), int(actions[1]["damage_to_hp"])], [6, 6], "...6, then 6")
	_expect_eq(int(step["damage_to_hp"]), 12, "...the turn's total 12")
	_expect_eq(hp_before - player.hp, 12, "...12 off the player")
	_expect_eq((step["hits"] as Array).size(), 2, "...both hits in the turn's own list")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Leap", "...and the loop moves one step, to Leap")
	_expect_eq(int(EnemyTurn.take_turn(enemy, data, player)["damage_to_hp"]), 20, "Leap: 10 and 10")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Bow", "...then Bow")

# Both attacks against the player's Block and HP: 6 and 6 into 8 Block
# is 4 through; lethal when the two together finish them, not when one
# would leave them standing.
func _check_lethal_and_block() -> void:
	var data := _crane()
	var enemy := _enemy(data)
	Status.apply_to(enemy.statuses, _bereft())
	EnemyTurn._advance_intent(enemy, data)
	var guarded := Combatant.new(PLAYER_HP)
	guarded.block = 8
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, guarded)
	_expect_eq(int(preview["damage_to_hp"]), 4, "Step 6x2 into 8 Block: 4 through, previewed")
	var landed: Dictionary = EnemyTurn.take_turn(enemy, data, guarded)
	_expect_eq(int(landed["damage_to_hp"]), 4, "...and landed")
	_expect_eq(int(landed["actions"][0]["damage_to_hp"]), 0, "...the first all blocked")
	_expect_eq(int(landed["actions"][1]["damage_to_hp"]), 4, "...the second 4 through")
	var fresh := _enemy(data)
	Status.apply_to(fresh.statuses, _bereft())
	EnemyTurn._advance_intent(fresh, data)
	_expect(bool(EnemyTurn.preview_intent(fresh, data, Combatant.new(12))["lethal"]), "6x2 at 12 HP: lethal")
	_expect(not bool(EnemyTurn.preview_intent(fresh, data, Combatant.new(13))["lethal"]), "...at 13: not")
	_expect(not bool(EnemyTurn.preview_intent(_stepping(data), data, Combatant.new(12))["lethal"]), "...and unheld, one 6 at 12: not")

# Garnished (4 off its next attack) on a held enemy: each Step loses
# the full 4 and lands 2 - previewed and resolved.
func _check_garnish_each_action() -> void:
	var data := _crane()
	var enemy := _enemy(data)
	Status.apply_to(enemy.statuses, _bereft())
	Status.apply_amount(enemy.statuses, load(GARNISHED_PATH) as StatusData, 4)
	EnemyTurn._advance_intent(enemy, data)
	var player := Combatant.new(PLAYER_HP)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(preview["hit_amounts"], [2, 2], "Garnished 4: each Step 2, previewed")
	var landed: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq([int(landed["actions"][0]["damage_to_hp"]), int(landed["actions"][1]["damage_to_hp"])], [2, 2], "...and landed")

# --- Helpers ---

func _crane() -> EnemyData:
	var data := EnemyData.new()
	data.enemy_name = "Probe crane"
	data.max_hp = 32
	data.intents = [_intent("Bow", EnemyIntent.IntentType.DEFEND, 4), _intent("Step", EnemyIntent.IntentType.ATTACK, 6), _intent("Leap", EnemyIntent.IntentType.ATTACK, 10)] as Array[EnemyIntent]
	return data

func _intent(intent_name: String, type: EnemyIntent.IntentType, value: int) -> EnemyIntent:
	var intent := EnemyIntent.new()
	intent.intent_name = intent_name
	intent.type = type
	intent.value = value
	return intent

func _bereft() -> StatusData:
	var bereft := StatusData.new()
	bereft.id = "probe_bereft"
	bereft.display_name = "Bereft"
	bereft.category = StatusData.Category.INFORMATIONAL
	bereft.default_duration_turns = -1
	bereft.repeats_intent = 2
	return bereft

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _stepping(data: EnemyData) -> Combatant:
	var enemy := _enemy(data)
	EnemyTurn._advance_intent(enemy, data)
	return enemy

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
