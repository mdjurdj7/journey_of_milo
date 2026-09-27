extends SceneTree

# Headless probe for Sentence: the countdown it puts on an enemy, how the
# enemy's own turns and the player's Toll spends run it down, and the 40
# it deals at 0 - never as an Attack. Rules layer and the real .tres
# cards, statuses and pool; no field scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/sentence_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const MAX_HP := 70
const CASES := 16
const DAMAGE := 40
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const BELONGINGS_POOL_PATH := "res://cards/pools/belongings_pool.tres"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const ART_PATH := "res://cards/art/Wanderer/Sentence.png"
const BATTLE_CONTROLLER_PATH := "res://battle/battle_controller.gd"

var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
# What the last _play() reported, as "kind:amount" per report.
var _reports: Array[String] = []

func _initialize() -> void:
	_check_card_data()
	_check_applies_four()
	_check_natural_countdown()
	_check_toll_spends_once_each()
	_check_reckoning_once()
	_check_debt_forgiven()
	_check_gaining_toll_does_nothing()
	_check_hurried_to_zero_resolves_now()
	_check_not_an_attack()
	_check_leaves_come_due()
	_check_replay_refreshes()
	_check_separate_enemies()
	_check_death_cleans_up()
	_check_countdown_kill_ends_the_turn()
	_check_block_softens_it()
	_check_pool()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("sentence_probe: PASSED")
		quit(0)
	else:
		print("sentence_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = _card("sentence")
	_expect_eq(card.card_name, "Sentence", "The card is named Sentence")
	_expect_eq(card.cost, 2, "...costs 2")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.RARE, "...is Rare")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...and carries its art")
	_completed += 1

func _check_applies_four() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(100)
	_play("sentence", player, [enemy])
	_expect_eq(_labels(enemy), ["Sentence 4"] as Array[String], "Playing Sentence marks the target Sentence 4")
	_play("slash", player, [enemy])
	_play("endure", player, [enemy])
	_expect_eq(_labels(enemy), ["Sentence 4"] as Array[String], "...and the rest of that turn leaves it at 4")
	_expect_eq(player.statuses.size(), 0, "...nothing on the player")
	_completed += 1

func _check_natural_countdown() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(100)
	var data: EnemyData = _defender()
	EnemyTurn.pick_initial_intent(enemy, data)
	_play("sentence", player, [enemy])
	var seen: Array[String] = []
	for turn in 3:
		EnemyTurn.take_turn(enemy, data, player)
		seen.append(_labels(enemy)[0] if not _labels(enemy).is_empty() else "")
	_expect_eq(seen, ["Sentence 3", "Sentence 2", "Sentence 1"] as Array[String], "Each enemy turn takes one off: 3, 2, 1")
	_expect_eq(enemy.hp, 100, "...and nothing lands before 0")
	var hp_before: int = enemy.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(hp_before - enemy.hp, DAMAGE, "The fourth enemy turn deals exactly 40")
	_expect_eq(result.get("countdown_damage"), DAMAGE, "...reported as countdown damage")
	_expect_eq(_labels(enemy), [] as Array[String], "...and Sentence is gone")
	_completed += 1

func _check_toll_spends_once_each() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(200)
	_play("sentence", player, [enemy])
	player.toll = 5
	_play("come_due", player, [enemy])
	_expect_eq(player.toll, 0, "Come Due spends 5")
	_expect_eq(_label_of(enemy, "sentence"), "Sentence 3", "...and takes exactly one off (4 -> 3)")
	_completed += 1

func _check_reckoning_once() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(200)
	_play("sentence", player, [enemy])
	player.toll = 14
	_play("reckoning", player, [enemy])
	_expect_eq(player.toll, 0, "Reckoning spends all 14")
	_expect_eq(_labels(enemy), ["Sentence 3"] as Array[String], "...and takes only one off, not 14")
	_play("reckoning", player, [enemy])
	_expect_eq(_labels(enemy), ["Sentence 3"] as Array[String], "A Toll-less Reckoning spends nothing, and takes nothing off")
	_completed += 1

func _check_debt_forgiven() -> void:
	var player: Combatant = _player()
	player.hp = 40
	var enemy := Combatant.new(200)
	_play("sentence", player, [enemy])
	player.toll = 6
	_play("debt_forgiven", player, [enemy])
	_expect_eq(player.toll, 0, "Debt Forgiven spends the 6 there is")
	_expect_eq(_labels(enemy), ["Sentence 3"] as Array[String], "...and takes one off")
	_play("debt_forgiven", player, [enemy])
	_expect_eq(_labels(enemy), ["Sentence 3"] as Array[String], "On 0 Toll it spends nothing, and takes nothing off")
	_completed += 1

func _check_gaining_toll_does_nothing() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(200)
	_play("sentence", player, [enemy])
	_play("down_payment", player, [enemy])
	_play("bite_down", player, [enemy])
	_expect(player.toll > 0, "Down Payment and Bite Down make Toll (%d)" % player.toll)
	_expect_eq(_labels(enemy), ["Sentence 4"] as Array[String], "...and gaining it takes nothing off")
	player.toll += 7
	_expect_eq(_labels(enemy), ["Sentence 4"] as Array[String], "...nor does Toll set directly")
	_completed += 1

func _check_hurried_to_zero_resolves_now() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(100)
	_play("sentence", player, [enemy])
	for spend in 3:
		player.toll = 5
		_play("come_due", player, [enemy])
	_expect_eq(_label_of(enemy, "sentence"), "Sentence 1", "Three spends: Sentence 1")
	player.toll = 5
	_play("come_due", player, [enemy])
	_expect_eq(enemy.hp, 100 - DAMAGE, "A fourth spend takes it to 0 and it deals 40 at once, in the player's turn")
	_expect(_reports.has("status:%d" % DAMAGE), "...reported as status damage, not a card's (%s)" % str(_reports))
	_expect_eq(_label_of(enemy, "sentence"), "", "...and Sentence is gone")
	_completed += 1

# The 40 is no Attack: no attack bonus from a stance or Dying Light, even
# Critical, where both would pay.
func _check_not_an_attack() -> void:
	var player: Combatant = _player()
	player.hp = 15
	_play("dying_light", player, [Combatant.new(100)])
	_play("self_eater", player, [Combatant.new(100)])
	_expect(AttackBonus.for_player(player, player.hp) > 0, "Critical under Dying Light and Self-Eater, an Attack would get more (%d)" % AttackBonus.for_player(player, player.hp))
	var enemy := Combatant.new(100)
	_play("sentence", player, [enemy])
	var data: EnemyData = _defender()
	EnemyTurn.pick_initial_intent(enemy, data)
	for turn in 4:
		EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(enemy.hp, 100 - DAMAGE, "...but Sentence deals exactly 40")
	_completed += 1

func _check_leaves_come_due() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(100)
	_play("sentence", player, [enemy])
	player.toll = 5
	_play("come_due", player, [enemy])
	var data: EnemyData = _defender()
	EnemyTurn.pick_initial_intent(enemy, data)
	for turn in 3:
		EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(enemy.hp, 100 - DAMAGE, "With Come Due on it, Sentence still deals 40, not 44")
	_expect_eq(_label_of(enemy, "come_due"), "Come Due ×3", "...and spends no Come Due charge")
	_completed += 1

func _check_replay_refreshes() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(200)
	var data: EnemyData = _defender()
	EnemyTurn.pick_initial_intent(enemy, data)
	_play("sentence", player, [enemy])
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(_labels(enemy), ["Sentence 2"] as Array[String], "Two turns in, Sentence 2")
	_play("sentence", player, [enemy])
	_expect_eq(_labels(enemy), ["Sentence 4"] as Array[String], "Replayed, it resets to 4 - one Sentence, not two, not 6")
	for turn in 4:
		EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(enemy.hp, 200 - DAMAGE, "...and still deals 40, once")
	_completed += 1

func _check_separate_enemies() -> void:
	var player: Combatant = _player()
	var first := Combatant.new(200)
	var second := Combatant.new(200)
	# The target is the last enemy listed: first, then second.
	_play("sentence", player, [second, first])
	var data: EnemyData = _defender()
	EnemyTurn.pick_initial_intent(first, data)
	EnemyTurn.take_turn(first, data, player)
	_play("sentence", player, [first, second])
	_expect_eq(_labels(first), ["Sentence 3"] as Array[String], "Each enemy holds its own Sentence (the first, a turn in: 3)")
	_expect_eq(_labels(second), ["Sentence 4"] as Array[String], "...(the second, fresh: 4)")
	EnemyTurn.take_turn(first, data, player)
	_expect_eq(_labels(first), ["Sentence 2"] as Array[String], "...each counting down on its own turn")
	_expect_eq(_labels(second), ["Sentence 4"] as Array[String], "...the other untouched")
	player.toll = 5
	_play("come_due", player, [first, second])
	_expect_eq(_label_of(first, "sentence"), "Sentence 1", "One Toll spend hurries every Sentence: 2 -> 1")
	_expect_eq(_label_of(second, "sentence"), "Sentence 3", "...and 4 -> 3")
	_completed += 1

# A dead enemy's Sentence goes with it: the controller reads no row for it,
# and a living one isn't handed its damage.
func _check_death_cleans_up() -> void:
	var controller: Object = (load(BATTLE_CONTROLLER_PATH) as GDScript).new()
	var player: Combatant = _player()
	var marked := Combatant.new(100)
	var other := Combatant.new(100)
	_play("sentence", player, [marked])
	var field_enemy: Node = (load("res://field/field_enemy.gd") as GDScript).new()
	controller._combatants[field_enemy] = marked
	_expect_eq(controller.get_enemy_status_labels(field_enemy), PackedStringArray(["Sentence 4"]), "A living marked enemy's row reads Sentence 4")
	marked.hp = 0
	_expect_eq(controller.get_enemy_status_labels(field_enemy), PackedStringArray(), "...dead, its row is empty")
	# The living are all a card can reach: four spends over the other.
	for spend in 4:
		player.toll = 5
		_play("come_due", player, [other])
	_expect_eq(other.hp, 100, "...and its 40 never lands on anyone else")
	field_enemy.free()
	controller.free()
	_completed += 1

func _check_countdown_kill_ends_the_turn() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(100)
	enemy.hp = 30
	var data: EnemyData = _attacker(10)
	EnemyTurn.pick_initial_intent(enemy, data)
	_play("sentence", player, [enemy])
	for turn in 3:
		EnemyTurn.take_turn(enemy, data, player)
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(enemy.hp, 0, "Sentence kills a 30 HP enemy at the start of its turn")
	_expect(not result.get("attacked"), "...which then doesn't act")
	_expect_eq(player.hp, before, "...so the player takes nothing")
	_completed += 1

func _check_block_softens_it() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(100)
	_play("sentence", player, [enemy])
	enemy.block = 10
	var data: EnemyData = _defender()
	EnemyTurn.pick_initial_intent(enemy, data)
	for turn in 3:
		EnemyTurn.take_turn(enemy, data, player)
	var block_before: int = enemy.block
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(enemy.hp, 100 - (DAMAGE - block_before), "Enemy block takes its share of the 40, like any damage (%d block)" % block_before)
	_completed += 1

func _check_pool() -> void:
	var pool := load(POOL_PATH) as RewardPool
	var entry: CardData = null
	for card in pool.entries:
		if card != null and card.card_name == "Sentence":
			entry = card
	_expect(entry != null, "Sentence is in the Wanderer reward pool")
	if entry != null:
		_expect_eq(entry.rarity, CardData.CardRarity.RARE, "...as Rare")
	var belongings := load(BELONGINGS_POOL_PATH) as RewardPool
	for card in belongings.entries:
		_expect(card == null or card.card_name != "Sentence", "...not in the belongings (Keeper) pool")
	var character := load(CHARACTER_PATH) as CharacterData
	var counts: Dictionary = {}
	for card: CardData in character.starting_deck_counts:
		counts[card.card_name] = character.starting_deck_counts[card]
	_expect_eq(counts, {"Slash": 4, "Bite Down": 2, "Brace": 2, "Reckoning": 1, "Down Payment": 1}, "...and the starting deck is unchanged")
	_completed += 1

# --- Helpers ---

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.critical_hp_fraction = 0.3
	return player

# The target is the LAST enemy listed.
func _play(card_name: String, player: Combatant, enemies: Array[Combatant]) -> void:
	_reports.clear()
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = enemies
	ctx.target = enemies[enemies.size() - 1] if not enemies.is_empty() else null
	ctx.on_damage = func(_target: Combatant, amount: int, kind: String) -> void:
		_reports.append("%s:%d" % [kind, amount])
	_resolver.resolve_card(_card(card_name), ctx)

func _intent_data(type: EnemyIntent.IntentType, value: int) -> EnemyData:
	var intent := EnemyIntent.new()
	intent.type = type
	intent.value = value
	var data := EnemyData.new()
	data.max_hp = 100
	data.intents = [intent]
	return data

# An enemy that only ever Defends for 0 - its turns pass without touching
# the player or its own block.
func _defender() -> EnemyData:
	return _intent_data(EnemyIntent.IntentType.DEFEND, 0)

func _attacker(damage: int) -> EnemyData:
	return _intent_data(EnemyIntent.IntentType.ATTACK, damage)

func _labels(combatant: Combatant) -> Array[String]:
	var labels: Array[String] = []
	for active in combatant.statuses:
		labels.append(active.label())
	return labels

func _label_of(combatant: Combatant, id: String) -> String:
	for active in combatant.statuses:
		if active.data != null and active.data.id == id:
			return active.label()
	return ""

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
