extends SceneTree

# Headless probe for Grace's opening (EnemyTurn.open_grace()): an
# unblocked enemy hit opens grace_open_fraction of itself, rounded down -
# 10 opens 5 at the Wanderer's 0.5 - and the window's cap scales the same
# way (the largest hit's share, or the turn sum's); self-damage opens
# none; reclaim stays 1:1. Rules layer only, no field:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/grace_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const CASES := 5
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"

var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_check_wanderer_fraction()
	_check_hit_opens_half()
	_check_cap_scales()
	_check_self_damage_opens_none()
	_check_reclaim_one_to_one()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("grace_probe: PASSED")
		quit(0)
	else:
		print("grace_probe: %d FAILED" % _failures)
		quit(1)

# The Wanderer's own data opens half.
func _check_wanderer_fraction() -> void:
	var character := load(CHARACTER_PATH) as CharacterData
	_expect(character.has_grace, "The Wanderer has Grace")
	_expect_eq(character.grace_open_fraction, 0.5, "...opening half of a hit")
	_completed += 1

# A 10 damage hit through no Block opens 5; a 7 opens 3 (rounded down);
# at a fraction of 1 the whole hit opens, as before.
func _check_hit_opens_half() -> void:
	for case: Array in [[10, 0.5, 5], [7, 0.5, 3], [10, 1.0, 10]]:
		var player := _player(case[1], CharacterData.GraceCapMode.LARGEST_HIT)
		var result: Dictionary = _enemy_turn(player, [_attack(case[0], 1)])
		_expect_eq(result["damage_to_hp"], case[0], "A %d hit takes %d HP" % [case[0], case[0]])
		_expect_eq(player.grace, case[2], "...and opens %d Grace at %.1f" % [case[2], case[1]])
		_expect_eq(result["grace_opened"], case[2], "...reported as opened")
	# Block first: 4 Block against 10 leaves a 6 hit, which opens 3.
	var blocked := _player(0.5, CharacterData.GraceCapMode.LARGEST_HIT)
	blocked.block = 4
	_enemy_turn(blocked, [_attack(10, 1)])
	_expect_eq(blocked.grace, 3, "Block eats its share first: 10 against 4 Block opens 3")
	_completed += 1

# Two hits of 10 in one turn: the largest hit's share caps it at 5; under
# SUM the turn's 20 opens 10. A second turn's smaller hit never lowers it.
func _check_cap_scales() -> void:
	var largest := _player(0.5, CharacterData.GraceCapMode.LARGEST_HIT)
	_enemy_turn(largest, [_attack(10, 2)])
	_expect_eq(largest.grace, 5, "LARGEST_HIT: two 10 hits open 5 - the largest hit's half")
	var sum := _player(0.5, CharacterData.GraceCapMode.SUM)
	_enemy_turn(sum, [_attack(10, 2)])
	_expect_eq(sum.grace, 10, "SUM: two 10 hits open 10 - half the turn's 20")
	var held := _player(0.5, CharacterData.GraceCapMode.LARGEST_HIT)
	_enemy_turn(held, [_attack(10, 1)])
	_enemy_turn(held, [_attack(4, 1)])
	_expect_eq(held.grace, 5, "A later 4 hit leaves the open 5 as it is")
	_completed += 1

# Bite Down's own HP never opens Grace, whatever the fraction.
func _check_self_damage_opens_none() -> void:
	var player := _player(1.0, CharacterData.GraceCapMode.LARGEST_HIT)
	var enemy := Combatant.new(50)
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy] as Array[Combatant]
	EffectResolver.new().resolve_card(load(BITE_DOWN_PATH) as CardData, ctx)
	_expect(player.hp < 50, "Bite Down costs HP")
	_expect_eq(player.grace, 0, "...and opens no Grace")
	_completed += 1

# What opened is reclaimed 1:1 by damage dealt.
func _check_reclaim_one_to_one() -> void:
	var player := _player(0.5, CharacterData.GraceCapMode.LARGEST_HIT)
	_enemy_turn(player, [_attack(10, 1)])
	_expect_eq([player.hp, player.grace], [40, 5], "10 taken, 5 open")
	var ctx := EffectContext.new()
	ctx.player = player
	_expect_eq(ctx.grace_reclaim(3), 3, "Dealing 3 reclaims 3")
	_expect_eq([player.hp, player.grace], [43, 2], "...HP 43, 2 left open")
	_expect_eq(ctx.grace_reclaim(10), 2, "Dealing 10 reclaims only the 2 left")
	_expect_eq([player.hp, player.grace], [45, 0], "...HP 45 - half the hit back at most")
	_completed += 1

# --- Helpers ---

func _player(fraction: float, mode: CharacterData.GraceCapMode) -> Combatant:
	var player := Combatant.new(50)
	player.has_grace = true
	player.grace_open_fraction = fraction
	player.grace_cap_mode = mode
	player.grace_window_turns = 1
	return player

func _enemy_turn(player: Combatant, intents: Array[EnemyIntent]) -> Dictionary:
	var data := EnemyData.new()
	data.max_hp = 50
	data.intents = intents
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return EnemyTurn.take_turn(enemy, data, player)

func _attack(damage: int, hits: int) -> EnemyIntent:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.IntentType.ATTACK
	intent.value = damage
	intent.hits = hits
	return intent

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
