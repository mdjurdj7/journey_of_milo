extends SceneTree

# Headless probe for No Further: the waiting status it leaves, the
# Critical crossing that arms it, and the one enemy Attack it then turns
# to 0. Rules layer and the real .tres cards, statuses and pool; no field
# scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/no_further_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Max HP 70 at a 0.3 Critical line: Critical is 21 HP and below.

const MAX_HP := 70
const CRITICAL_FRACTION := 0.3
const CASES := 14
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const BELONGINGS_POOL_PATH := "res://cards/pools/belongings_pool.tres"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const ART_PATH := "res://cards/art/Wanderer/No Further.png"
const WAITING_PATH := "res://battle/rules/statuses/no_further.tres"
const ARMED_PATH := "res://battle/rules/statuses/no_further_armed.tres"
const WAITING := "No Further"
const ARMED := "No Further — Ready"

var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	_check_card_data()
	_check_waits_above_critical()
	_check_enemy_crossing()
	_check_self_damage_crossing()
	_check_already_critical()
	_check_next_attack_deals_nothing()
	_check_non_attacks_leave_it()
	_check_multi_hit()
	_check_once_per_play()
	_check_rearming_keeps_one()
	_check_preview_shows_it()
	_check_pool()
	_check_other_powers_unchanged()
	_check_the_crossing_hit_is_whole()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("no_further_probe: PASSED")
		quit(0)
	else:
		print("no_further_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = _card("no_further")
	_expect_eq(card.card_name, "No Further", "The card is named No Further")
	_expect_eq(card.cost, 1, "...costs 1")
	_expect_eq(card.card_type, CardData.CardType.POWER, "...is a Power")
	_expect_eq(card.rarity, CardData.CardRarity.RARE, "...is Rare")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...targets the player")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...is Spent")
	_expect_eq(card.description, "When you next enter Critical, the next enemy Attack deals 0 damage.\nSpent.", "...and says so")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...and carries its art")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.POWER, "...and its face reads POWER")
	var waiting := load(WAITING_PATH) as StatusData
	var armed := load(ARMED_PATH) as StatusData
	_expect_eq(waiting.display_name, WAITING, "The waiting status reads No Further")
	_expect_eq(waiting.description, "Next time you enter Critical, the next enemy Attack deals 0 damage.", "...and says what it waits for")
	_expect_eq(waiting.grants_on_critical, armed, "...and arms the Ready status")
	_expect_eq(armed.display_name, ARMED, "The armed status reads No Further — Ready")
	_expect_eq(armed.description, "The next enemy Attack deals 0 damage.", "...and says what it does")
	_expect_eq(armed.default_magnitude, -100, "...all of it: -100%")
	_expect_eq(armed.default_charges, 0, "...with no charge count")
	_expect(armed.consumed_by_attack_against, "...spent by the enemy Attack it meets")
	_completed += 1

func _check_waits_above_critical() -> void:
	var player: Combatant = _player(50)
	_play("no_further", player)
	_expect_eq(_labels(player), [WAITING] as Array[String], "Played at 50 HP, it reads No Further - waiting")
	_completed += 1

func _check_enemy_crossing() -> void:
	var player: Combatant = _player(30)
	_play("no_further", player)
	_attack(player, 12)
	_expect_eq(player.hp, 18, "The hit that crosses into Critical lands in full (30 -> 18)")
	_expect_eq(_labels(player), [ARMED] as Array[String], "...and No Further is armed: No Further — Ready")
	_completed += 1

func _check_self_damage_crossing() -> void:
	var player: Combatant = _player(23)
	_play("no_further", player)
	# Bite Down: deal 8, then lose 2 - its own HP cost takes 23 to 21, Critical.
	_play("bite_down", player)
	_expect_eq(player.hp, 21, "Bite Down's self-damage lands in full (23 -> 21)")
	_expect_eq(_labels(player), [ARMED] as Array[String], "...and that crossing arms it")
	_completed += 1

func _check_already_critical() -> void:
	var player: Combatant = _player(15)
	_play("no_further", player)
	_expect_eq(_labels(player), [ARMED] as Array[String], "Played while Critical, it arms at once - nothing left waiting")
	_completed += 1

# The whole Attack deals 0: block untouched, no Grace opened, and then it's
# gone - the next Attack lands as usual.
func _check_next_attack_deals_nothing() -> void:
	var player: Combatant = _player(15)
	player.has_grace = true
	_play("no_further", player)
	player.hp = 60
	player.block = 5
	var result: Dictionary = _attack(player, 10)
	_expect_eq(player.hp, 60, "The next Attack deals 0")
	_expect_eq(player.block, 5, "...Block untouched")
	_expect_eq(player.grace, 0, "...no Grace opened")
	_expect_eq(result.get("damage_to_hp"), 0, "...nothing reached HP")
	_expect_eq(_labels(player), [] as Array[String], "...and No Further is gone")
	_attack(player, 10)
	_expect_eq(player.hp, 55, "The Attack after lands as usual (5 blocked, 5 taken)")
	_completed += 1

func _check_non_attacks_leave_it() -> void:
	var player: Combatant = _player(15)
	_play("no_further", player)
	for type in [EnemyIntent.IntentType.DEFEND, EnemyIntent.IntentType.BURROW]:
		var data: EnemyData = _intent_data(type, 5, 1)
		EnemyTurn.take_turn(_enemy(data), data, player)
	_expect_eq(_labels(player), [ARMED] as Array[String], "A Defend and a Burrow leave it armed")
	# An Attack interrupted before it lands doesn't resolve, so it doesn't spend.
	var interrupted: EnemyData = _intent_data(EnemyIntent.IntentType.ATTACK, 10, 1)
	interrupted.intents[0].interrupt_threshold = 1
	var enemy: Combatant = _enemy(interrupted)
	enemy.damage_taken_this_turn = 1
	EnemyTurn.take_turn(enemy, interrupted, player)
	_expect_eq(_labels(player), [ARMED] as Array[String], "...and so does an interrupted Attack")
	_completed += 1

func _check_multi_hit() -> void:
	var player: Combatant = _player(15)
	_play("no_further", player)
	player.hp = 60
	var data: EnemyData = _intent_data(EnemyIntent.IntentType.ATTACK, 6, 3)
	EnemyTurn.take_turn(_enemy(data), data, player)
	_expect_eq(player.hp, 60, "A 3 x 6 Attack deals 0 on every hit")
	_expect_eq(_labels(player), [] as Array[String], "...and that one Attack spends it")
	_completed += 1

func _check_once_per_play() -> void:
	var player: Combatant = _player(30)
	_play("no_further", player)
	_attack(player, 12)
	_attack(player, 2)
	_expect_eq(_labels(player), [] as Array[String], "Armed at the crossing, spent by the next Attack")
	player.hp = 40
	_attack(player, 25)
	_expect_eq(player.hp, 15, "Healed out and back into Critical: the hit lands in full")
	_expect_eq(_labels(player), [] as Array[String], "...and the same No Further doesn't arm again")
	_completed += 1

func _check_rearming_keeps_one() -> void:
	var player: Combatant = _player(15)
	_play("no_further", player)
	Status.apply_to(player.statuses, load(ARMED_PATH) as StatusData)
	_expect_eq(_labels(player), [ARMED] as Array[String], "Armed again while armed: still one No Further — Ready")
	_completed += 1

func _check_preview_shows_it() -> void:
	var player: Combatant = _player(15)
	_play("no_further", player)
	var data: EnemyData = _intent_data(EnemyIntent.IntentType.ATTACK, 6, 3)
	var preview: Dictionary = EnemyTurn.preview_intent(_enemy(data), data, player)
	_expect_eq(preview.get("per_hit"), 0, "The intent preview shows 0 - the Attack still comes")
	_expect_eq(preview.get("damage_to_hp"), 0, "...on every hit")
	_expect(not bool(preview.get("lethal", true)), "...never lethal")
	_expect_eq(_labels(player), [ARMED] as Array[String], "...and previewing spends nothing")
	_completed += 1

func _check_pool() -> void:
	var pool := load(POOL_PATH) as RewardPool
	var entry: CardData = null
	for card in pool.entries:
		if card != null and card.card_name == "No Further":
			entry = card
	_expect(entry != null, "No Further is in the Wanderer reward pool")
	if entry != null:
		_expect_eq(entry.rarity, CardData.CardRarity.RARE, "...as Rare")
	var belongings := load(BELONGINGS_POOL_PATH) as RewardPool
	for card in belongings.entries:
		_expect(card == null or card.card_name != "No Further", "...not in the belongings (Keeper) pool")
	var character := load(CHARACTER_PATH) as CharacterData
	var counts: Dictionary = {}
	for card: CardData in character.starting_deck_counts:
		counts[card.card_name] = character.starting_deck_counts[card]
	_expect_eq(counts, {"Slash": 4, "Bite Down": 2, "Brace": 2, "Reckoning": 1, "Down Payment": 1}, "...and the starting deck is unchanged")
	_completed += 1

# The Critical check after a card is general; it mustn't disturb the other
# Powers' statuses, which wait for nothing.
func _check_other_powers_unchanged() -> void:
	var player: Combatant = _player(15)
	_play("dying_light", player)
	_play("refuse_the_end", player)
	_expect_eq(_labels(player), ["Dying Light", "Refuse the End ×1"] as Array[String], "Dying Light and Refuse the End (one save, ×1) stay put while Critical")
	_completed += 1

# The crossing blow is never softened by what it arms, even a multi-hit one:
# every hit of the Attack that crosses the line lands in full.
func _check_the_crossing_hit_is_whole() -> void:
	var player: Combatant = _player(30)
	_play("no_further", player)
	var data: EnemyData = _intent_data(EnemyIntent.IntentType.ATTACK, 6, 3)
	EnemyTurn.take_turn(_enemy(data), data, player)
	_expect_eq(player.hp, 12, "A 3 x 6 Attack that crosses the line lands all 18 (30 -> 12)")
	_expect_eq(_labels(player), [ARMED] as Array[String], "...and arms No Further only after")
	_completed += 1

# --- Helpers ---

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = CRITICAL_FRACTION
	return player

func _play(card_name: String, player: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = Combatant.new(100)
	ctx.enemies = [ctx.target]
	_resolver.resolve_card(_card(card_name), ctx)

func _intent_data(type: EnemyIntent.IntentType, value: int, hits: int) -> EnemyData:
	var intent := EnemyIntent.new()
	intent.type = type
	intent.value = value
	intent.hits = hits
	var data := EnemyData.new()
	data.max_hp = 50
	data.intents = [intent]
	return data

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

# One single-hit enemy Attack for `damage` against the player.
func _attack(player: Combatant, damage: int) -> Dictionary:
	var data: EnemyData = _intent_data(EnemyIntent.IntentType.ATTACK, damage, 1)
	return EnemyTurn.take_turn(_enemy(data), data, player)

func _labels(player: Combatant) -> Array[String]:
	var labels: Array[String] = []
	for active in player.statuses:
		labels.append(active.label())
	return labels

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
