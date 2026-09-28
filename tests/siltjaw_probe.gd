extends SceneTree

# Headless probe for the Siltjaw: its Snap -> Charge loop, the Charge's
# BREAK 14 (and that 13 isn't enough), the Burrow a break earns and the
# Snap that follows it, the intent preview's break numbers, and Brace
# kept through a broken Charge. Rules layer and the real .tres; no field
# scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/siltjaw_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const CASES := 8
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"
const SNAP := 6
const CHARGE := 14
const BREAK := 14

var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_check_data()
	_check_unbroken_loop()
	_check_break_takes_fourteen()
	_check_broken_loop()
	_check_snap_cannot_break()
	_check_preview()
	_check_brace_kept_through_break()
	_check_brace_spent_by_charge()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("siltjaw_probe: PASSED")
		quit(0)
	else:
		print("siltjaw_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var data: EnemyData = _siltjaw()
	_expect_eq(data.max_hp, 38, "The Siltjaw has 38 HP")
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect_eq(data.intents.size(), 2, "...of two moves")
	var snap: EnemyIntent = data.intents[0]
	_expect_eq(snap.type, EnemyIntent.IntentType.ATTACK, "Snap is an Attack")
	_expect_eq(snap.value, SNAP, "...for 6")
	_expect_eq(snap.interrupt_threshold, 0, "...that can't be broken")
	_expect(snap.on_interrupt == null, "...with nothing on a break")
	_expect(not snap.rear_while_queued, "...and no rear")
	var charge: EnemyIntent = data.intents[1]
	_expect_eq(charge.type, EnemyIntent.IntentType.ATTACK, "Charge is an Attack")
	_expect_eq(charge.value, CHARGE, "...for 14")
	_expect_eq(charge.interrupt_threshold, BREAK, "...BREAK 14")
	_expect(charge.on_interrupt != null and charge.on_interrupt.type == EnemyIntent.IntentType.BURROW, "...burrowing when broken")
	_expect(charge.rear_while_queued, "...reared while queued")
	_completed += 1

# Nothing dealt: Snap, Charge, Snap, Charge - each landing its number,
# never under the sand.
func _check_unbroken_loop() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var dealt: Array[int] = []
	for turn in 6:
		_expect(not enemy.buried, "Unbroken turn %d: above the sand" % (turn + 1))
		var before: int = player.hp
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		_expect(bool(result["attacked"]), "Unbroken turn %d: attacks" % (turn + 1))
		dealt.append(before - player.hp)
	_expect_eq(dealt, [SNAP, CHARGE, SNAP, CHARGE, SNAP, CHARGE] as Array[int], "Opens on Snap, then Snap -> Charge looping")
	_completed += 1

func _check_break_takes_fourteen() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	_hit(enemy, BREAK - 1)
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(not bool(result["interrupted"]), "13 dealt: the Charge isn't broken")
	_expect_eq(before - player.hp, CHARGE, "...and lands its 14")
	_expect(not enemy.buried, "...no Burrow")
	_expect_eq(EnemyTurn.current_intent(enemy, data).value, SNAP, "...Snap is next")
	_completed += 1

# Snap -> Charge broken -> Burrow -> Snap -> Charge.
func _check_broken_loop() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, SNAP, "Turn 1: Snap lands 6")

	_hit(enemy, BREAK)
	before = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["interrupted"]), "Turn 2: 14 dealt breaks the Charge")
	_expect(not bool(result["attacked"]), "...it doesn't attack")
	_expect_eq(player.hp, before, "...nothing lands")
	_expect(bool(result["buried"]) and enemy.buried, "...and it goes under")
	_expect_eq(EnemyTurn.current_intent(enemy, data).type, EnemyIntent.IntentType.BURROW, "...Burrow queued")

	enemy.damage_taken_this_turn = 0
	before = player.hp
	result = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["surfaced"]), "Turn 3: Burrow resolves and it surfaces")
	_expect_eq(player.hp, before, "...doing nothing")
	_expect(not enemy.buried, "...above the sand")
	_expect_eq(EnemyTurn.current_intent(enemy, data).value, SNAP, "...Snap before any Charge")

	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, SNAP, "Turn 4: Snap lands 6")
	var next: EnemyIntent = EnemyTurn.current_intent(enemy, data)
	_expect(next.value == CHARGE and next.interrupt_threshold == BREAK, "Turn 5: the Charge again")
	_completed += 1

func _check_snap_cannot_break() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_hit(enemy, 30)
	_expect(not EnemyTurn.is_interrupted(enemy, EnemyTurn.current_intent(enemy, data)), "30 dealt on a Snap turn: not broken")
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(not bool(result["interrupted"]), "...the Snap resolves")
	_expect_eq(before - player.hp, SNAP, "...for 6")
	_expect(not enemy.buried, "...no Burrow")
	_completed += 1

# What BattleIntent draws: no ring on Snap; the Charge's ring counting
# down from 14 and full (interrupted) at 14.
func _check_preview() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(preview.get("per_hit"), SNAP, "Snap previews 6")
	_expect(not preview.has("threshold"), "...with no break ring")
	EnemyTurn.take_turn(enemy, data, player)

	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(preview.get("per_hit"), CHARGE, "Charge previews 14")
	_expect_eq(preview.get("threshold"), BREAK, "...BREAK 14")
	_expect_eq(preview.get("threshold_left"), BREAK, "...14 still to deal")
	_expect(not bool(preview.get("interrupted", true)), "...not broken")
	_hit(enemy, 9)
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(preview.get("threshold_left"), 5, "9 dealt: 5 left")
	_hit(enemy, 5)
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(preview.get("threshold_left"), 0, "14 dealt: 0 left")
	_expect(bool(preview.get("interrupted", false)), "...broken")
	_expect(not bool(preview.get("lethal", true)), "...never lethal")
	_completed += 1

# Braced on the Charge's turn, the Charge broken: it never resolved, so
# Braced stays - through the Burrow - and halves the Snap after.
func _check_brace_kept_through_break() -> void:
	var data: EnemyData = _siltjaw()
	var braced := load(BRACED_PATH) as StatusData
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	Status.apply_to(enemy.statuses, braced)
	_hit(enemy, BREAK)
	EnemyTurn.take_turn(enemy, data, player)
	_expect(Status.find_in(enemy.statuses, braced) != null, "A broken Charge leaves Braced in place")
	enemy.damage_taken_this_turn = 0
	EnemyTurn.take_turn(enemy, data, player)
	_expect(Status.find_in(enemy.statuses, braced) != null, "...and so does the Burrow")
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(preview.get("per_hit"), 3, "...the Snap after previews 3")
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, 3, "...and lands 3")
	_expect(Status.find_in(enemy.statuses, braced) == null, "...spending it")
	_completed += 1

func _check_brace_spent_by_charge() -> void:
	var data: EnemyData = _siltjaw()
	var braced := load(BRACED_PATH) as StatusData
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	Status.apply_to(enemy.statuses, braced)
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, 7, "A Braced Charge that lands deals 7")
	_expect(Status.find_in(enemy.statuses, braced) == null, "...and spends Braced")
	_completed += 1

# --- Helpers ---

func _siltjaw() -> EnemyData:
	return load(SILTJAW_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _player() -> Combatant:
	return Combatant.new(500)

# The player's cards landing on it, through the same pipeline a card
# uses - what counts toward the break.
func _hit(enemy: Combatant, amount: int) -> void:
	DamagePipeline.resolve(amount, enemy)

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
