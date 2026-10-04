extends SceneTree

# Headless probe for The Return and the Drain keyword: the counter it
# leaves, the self-inflicted losses that move it (one per loss, never an
# enemy's hit), the Drain its fifth sets off - once from every enemy, the
# heal capped at the printed number - and what Drain is not: an Attack,
# a mark's payoff, a Grace reclaim. Rules layer and the real .tres cards,
# statuses and pool; no field scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/the_return_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Max HP 70 at a 0.3 Critical line: Critical is 21 HP and below.

const MAX_HP := 70
const CRITICAL_FRACTION := 0.3
const CASES := 19
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const BELONGINGS_POOL_PATH := "res://cards/pools/belongings_pool.tres"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const ART_PATH := "res://cards/art/Wanderer/The Return.png"
const STATUS_PATH := "res://battle/rules/statuses/the_return.tres"
const COME_DUE_PATH := "res://battle/rules/statuses/come_due.tres"
const KEEN_PATH := "res://battle/rules/statuses/keen.tres"
const DRAIN := 10
const COUNT := 5

var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
# Every report_damage() of the last _play(), as [combatant, amount, kind].
var _reports: Array = []

func _initialize() -> void:
	_check_card_data()
	_check_play_creates_counter()
	_check_first_four_count()
	_check_fifth_drains_and_resets()
	_check_big_loss_counts_once()
	_check_enemy_damage_doesnt_count()
	_check_triggers_again()
	_check_heal_follows_damage_dealt()
	_check_heal_capped_at_max_hp()
	_check_not_an_attack()
	_check_come_due_untouched()
	_check_toll_and_grace()
	_check_lethal_loss_not_rescued()
	_check_stacks_share_one_counter()
	_check_blood_arc_order()
	_check_stance_price_counts()
	_check_real_self_damage_cards()
	_check_drain_card_effect()
	_check_pool()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("the_return_probe: PASSED")
		quit(0)
	else:
		print("the_return_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = _card("the_return")
	_expect_eq(card.card_name, "The Return", "The card is named The Return")
	_expect_eq(card.cost, 2, "...costs 2")
	_expect_eq(card.card_type, CardData.CardType.POWER, "...is a Power")
	_expect_eq(card.rarity, CardData.CardRarity.RARE, "...is Rare")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...targets the player")
	_expect_eq(card.removal_scope, CardData.RemovalScope.NONE, "...leaves rotation as a Power does, nothing more")
	_expect_eq(card.description, "Every 5 times you damage yourself:\nDrain 10 from all enemies.", "...and says so")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...and carries its art")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.POWER, "...and its face reads POWER")
	_expect(CardView.KEYWORDS.has("Drain"), "Drain is a bold rules keyword")
	var data := load(STATUS_PATH) as StatusData
	_expect_eq(data.display_name, "The Return", "The status reads The Return")
	_expect_eq(data.self_loss_trigger_count, COUNT, "...counts to 5")
	_expect_eq(data.self_loss_trigger_drain, DRAIN, "...and Drains 10")
	_expect_eq(data.default_duration_turns, StatusData.DURATION_UNTIL_REMOVED, "...for the rest of the fight")
	_completed += 1

func _check_play_creates_counter() -> void:
	var player: Combatant = _player(50)
	_play(_card("the_return"), player, [_enemy(100)])
	_expect_eq(_labels(player), ["The Return 0/5"] as Array[String], "Played, it reads The Return 0/5")
	_expect_eq(player.statuses[0].describe(), "Every 5 times you damage yourself:\nDrain 10 from all enemies.", "...and its reveal says what it counts")
	_completed += 1

func _check_first_four_count() -> void:
	var player: Combatant = _armed(50)
	var enemies: Array[Combatant] = [_enemy(100), _enemy(100)]
	for event in range(1, COUNT):
		_play(_self_damage(1), player, enemies)
		_expect_eq(_labels(player), ["The Return %d/5" % event] as Array[String], "Loss %d reads %d/5" % [event, event])
	_expect_eq(enemies[0].hp + enemies[1].hp, 200, "...and the first four Drain nothing")
	_expect_eq(player.hp, 46, "...nor heal (50 -> 46)")
	_completed += 1

func _check_fifth_drains_and_resets() -> void:
	var player: Combatant = _armed(40)
	var enemies: Array[Combatant] = [_enemy(100), _enemy(100), _enemy(100)]
	_losses(player, enemies, COUNT - 1)
	_play(_self_damage(1), player, enemies)
	for enemy in enemies:
		_expect_eq(enemy.hp, 90, "The fifth loss Drains 10 from every enemy")
	_expect_eq(player.hp, 45, "...and heals 10 in total, not 10 per enemy (40 - 5 + 10)")
	_expect_eq(_labels(player), ["The Return 0/5"] as Array[String], "...and the count starts again at 0/5")
	_expect_eq(_kinds(), ["self", "drain", "drain", "drain"] as Array[String], "...reported as Drain, after the loss")
	_completed += 1

func _check_big_loss_counts_once() -> void:
	var player: Combatant = _armed(50)
	_play(_self_damage(4), player, [_enemy(100)])
	_expect_eq(_labels(player), ["The Return 1/5"] as Array[String], "Losing 4 HP in one effect counts once")
	# The funnel every loss goes through - a status tick included.
	player.gain_self_loss_toll(3)
	_play(_self_damage(0), player, [_enemy(100)])
	_expect_eq(_labels(player), ["The Return 2/5"] as Array[String], "...as does any one self-inflicted loss (a tick's route)")
	player.gain_self_loss_toll(0)
	_expect_eq(_labels(player), ["The Return 2/5"] as Array[String], "...and a loss of 0 HP counts nothing")
	_completed += 1

func _check_enemy_damage_doesnt_count() -> void:
	var player: Combatant = _armed(50)
	_attack(player, 6)
	_attack(player, 6)
	_expect_eq(player.hp, 38, "Two enemy Attacks land")
	_expect_eq(_labels(player), ["The Return 0/5"] as Array[String], "...and count nothing")
	_completed += 1

func _check_triggers_again() -> void:
	var player: Combatant = _armed(50)
	var enemy: Combatant = _enemy(100)
	_losses(player, [enemy], COUNT)
	_expect_eq(enemy.hp, 90, "The first five Drain once")
	_losses(player, [enemy], COUNT - 1)
	_expect_eq(enemy.hp, 90, "...the next four nothing")
	_losses(player, [enemy], 1)
	_expect_eq(enemy.hp, 80, "...and the tenth Drains again")
	_expect_eq(_labels(player), ["The Return 0/5"] as Array[String], "...still up, back at 0/5")
	_completed += 1

func _check_heal_follows_damage_dealt() -> void:
	var player: Combatant = _armed(40)
	var blocked: Combatant = _enemy(100)
	blocked.block = 6
	_losses(player, [blocked], COUNT)
	_expect_eq(blocked.hp, 96, "Drain goes through Block like any damage (6 blocked, 4 taken)")
	_expect_eq(player.hp, 39, "...and heals only the 4 it dealt (40 - 5 + 4)")
	var low: Combatant = _enemy(3)
	var full: Combatant = _enemy(100)
	full.block = 100
	_losses(player, [low, full], COUNT)
	_expect_eq(low.hp, 0, "A 3 HP enemy dies to it")
	_expect_eq(player.hp, 37, "...and the heal is the 3 HP it took (39 - 5 + 3)")
	var buried: Combatant = _enemy(100)
	buried.buried = true
	var open: Combatant = _enemy(100)
	_losses(player, [buried, open], COUNT)
	_expect_eq(buried.hp, 100, "A buried enemy takes none")
	_expect_eq(open.hp, 90, "...its neighbour takes 10")
	_completed += 1

func _check_heal_capped_at_max_hp() -> void:
	var player: Combatant = _armed(MAX_HP)
	_losses(player, [_enemy(100)], COUNT)
	_expect_eq(player.hp, MAX_HP, "The heal stops at max HP (70 - 5 + 5, not + 10)")
	_completed += 1

# Self-Eater's bonus and Keen's charge: none of it lands on a Drain, and
# none of it is spent by one.
func _check_not_an_attack() -> void:
	var player: Combatant = _armed(20)
	_play(_card("self_eater"), player, [_enemy(100)])
	Status.apply_to(player.statuses, load(KEEN_PATH) as StatusData)
	_expect(AttackBonus.for_player(player, player.hp) > 0, "Self-Eater and Keen are up, and an Attack would get a bonus")
	var enemy: Combatant = _enemy(100)
	_losses(player, [enemy], COUNT)
	_expect_eq(enemy.hp, 90, "...but the Drain deals 10 flat")
	var keen: Status = Status.find_in(player.statuses, load(KEEN_PATH) as StatusData)
	_expect(keen != null and keen.charges == 1, "...and Keen's charge is left for an Attack")
	_expect_eq(player.hp, 25, "...and Self-Eater charges nothing for it (20 - 5 + 10)")
	_completed += 1

func _check_come_due_untouched() -> void:
	var player: Combatant = _armed(50)
	var marked: Combatant = _enemy(100)
	Status.apply_to(marked.statuses, load(COME_DUE_PATH) as StatusData)
	_losses(player, [marked], COUNT)
	_expect_eq(marked.hp, 90, "A Come Due mark adds nothing to a Drain")
	var mark: Status = Status.find_in(marked.statuses, load(COME_DUE_PATH) as StatusData)
	_expect(mark != null and mark.charges == 3, "...and keeps all 3 charges")
	_completed += 1

func _check_toll_and_grace() -> void:
	var player: Combatant = _armed(40)
	player.has_grace = true
	player.grace = 5
	player.grace_turns_left = 1
	var enemy: Combatant = _enemy(100)
	_losses(player, [enemy], COUNT)
	_expect_eq(player.toll, COUNT, "Toll: 1 per HP lost, nothing from the Drain or its heal")
	_expect_eq(player.grace, 5, "Grace: the Drain reclaims none")
	_expect_eq(player.hp, 45, "...its own heal is the whole of it (40 - 5 + 10)")
	_completed += 1

func _check_lethal_loss_not_rescued() -> void:
	var player: Combatant = _armed(10)
	var enemy: Combatant = _enemy(100)
	_losses(player, [enemy], COUNT - 1)
	_expect_eq(player.hp, 6, "Four losses in (10 -> 6)")
	_play(_self_damage(6), player, [enemy])
	_expect_eq(player.hp, 0, "A fifth that kills leaves the player at 0")
	_expect_eq(enemy.hp, 100, "...and no Drain lands to rescue them")
	_expect_eq(player.pending_drain, 0, "...nor is one kept for later")
	_completed += 1

func _check_stacks_share_one_counter() -> void:
	var player: Combatant = _armed(30)
	_losses(player, [_enemy(100)], 2)
	_play(_card("the_return"), player, [_enemy(100)])
	_expect_eq(_labels(player), ["The Return ×2 2/5"] as Array[String], "A second copy joins the count: The Return ×2 2/5")
	_expect_eq(player.statuses.size(), 1, "...one status, one counter")
	var enemies: Array[Combatant] = [_enemy(100), _enemy(100)]
	_losses(player, enemies, COUNT - 2)
	for enemy in enemies:
		_expect_eq(enemy.hp, 80, "Two copies Drain 20 from every enemy")
	_expect_eq(_kinds().count("drain"), 2, "...as one Drain, not two")
	_expect_eq(player.hp, 45, "...heal capped at 20 in total, not 40 (30 - 5 + 20)")
	_expect_eq(player.statuses[0].describe(), "Every 5 times you damage yourself:\nDrain 20 from all enemies.", "...and the reveal reads Drain 20")
	_play(_card("the_return"), player, [_enemy(100)])
	var third: Combatant = _enemy(100)
	_losses(player, [third], COUNT)
	_expect_eq(third.hp, 70, "Three copies Drain 30")
	_completed += 1

# Blood Arc loses 3 then sweeps for 9: a fifth loss Drains BEFORE the
# sweep, and what the Drain kills isn't swept again.
func _check_blood_arc_order() -> void:
	var player: Combatant = _armed(50)
	var weak: Combatant = _enemy(10)
	var strong: Combatant = _enemy(100)
	var enemies: Array[Combatant] = [weak, strong]
	_losses(player, enemies, COUNT - 1)
	_play(_card("blood_arc"), player, enemies)
	_expect_eq(weak.hp, 0, "Blood Arc's loss sets it off: the Drain kills the 10 HP enemy")
	_expect_eq(_reports_on(weak), 1, "...which is struck once, by the Drain alone")
	_expect_eq(strong.hp, 81, "...and the sweep lands after it (100 - 10 - 9)")
	_expect_eq(_kinds(), ["self", "drain", "drain", "card"] as Array[String], "...loss, Drain, then the sweep")
	_completed += 1

# Self-Eater's price for an Attack is a loss like any other; its Drain
# lands before the Attack, and a target it kills isn't struck again.
func _check_stance_price_counts() -> void:
	var player: Combatant = _armed(50)
	_play(_card("self_eater"), player, [_enemy(100)])
	var target: Combatant = _enemy(10)
	_losses(player, [target], COUNT - 1)
	_play(_card("slash"), player, [target], target)
	_expect_eq(target.hp, 0, "Self-Eater's price is the fifth loss: the Drain kills the target")
	_expect_eq(_reports_on(target), 1, "...and Slash doesn't strike the body")
	_expect_eq(_labels(player), ["The Return 0/5"] as Array[String], "...back to 0/5")
	_completed += 1

func _check_real_self_damage_cards() -> void:
	var player: Combatant = _armed(60)
	var enemy: Combatant = _enemy(500)
	_play(_card("bite_down"), player, [enemy], enemy)
	_play(_card("last_wager"), player, [enemy], enemy)
	_play(_card("down_payment"), player, [enemy])
	_expect_eq(_labels(player), ["The Return 3/5"] as Array[String], "Bite Down, Last Wager and Down Payment count once each")
	player.hp = 1
	_play(_card("down_payment"), player, [enemy])
	_expect_eq(_labels(player), ["The Return 3/5"] as Array[String], "...Down Payment at 1 HP loses nothing and counts nothing")
	_completed += 1

# Drain as a card effect, for a later card: the same rule, with no counter.
func _check_drain_card_effect() -> void:
	var effect := CardEffect.new()
	effect.effect_type = CardEffect.EffectType.DRAIN
	effect.value = DRAIN
	effect.target_scope = CardEffect.TargetScope.ALL_ENEMIES
	var card := CardData.new()
	card.card_type = CardData.CardType.ATTACK
	card.effects = [effect]
	var player: Combatant = _player(40)
	Status.apply_to(player.statuses, load(KEEN_PATH) as StatusData)
	var enemies: Array[Combatant] = [_enemy(100), _enemy(100), _enemy(100), _enemy(100)]
	_play(card, player, enemies)
	for enemy in enemies:
		_expect_eq(enemy.hp, 90, "A Drain 10 effect deals 10 to each of four enemies")
	_expect_eq(player.hp, 50, "...and heals 10, not 40")
	var keen: Status = Status.find_in(player.statuses, load(KEEN_PATH) as StatusData)
	_expect(keen != null and keen.charges == 1, "...and takes no Attack bonus, even on an Attack card")
	_completed += 1

func _check_pool() -> void:
	var pool := load(POOL_PATH) as RewardPool
	var entry: CardData = null
	for card in pool.entries:
		if card != null and card.card_name == "The Return":
			entry = card
	_expect(entry != null, "The Return is in the Wanderer reward pool")
	if entry != null:
		_expect_eq(entry.rarity, CardData.CardRarity.RARE, "...as Rare")
	var belongings := load(BELONGINGS_POOL_PATH) as RewardPool
	for card in belongings.entries:
		_expect(card == null or card.card_name != "The Return", "...not in the belongings (Keeper) pool")
	var character := load(CHARACTER_PATH) as CharacterData
	for card: CardData in character.starting_deck_counts:
		_expect(card.card_name != "The Return", "...nor the starting deck")
	_completed += 1

# --- Helpers ---

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = CRITICAL_FRACTION
	return player

# A player at `hp` with The Return already played.
func _armed(hp: int) -> Combatant:
	var player: Combatant = _player(hp)
	_play(_card("the_return"), player, [_enemy(100)])
	return player

func _enemy(hp: int) -> Combatant:
	return Combatant.new(hp)

# A bare Skill that loses `amount` HP - one self-inflicted loss.
func _self_damage(amount: int) -> CardData:
	var effect := CardEffect.new()
	effect.effect_type = CardEffect.EffectType.SELF_DAMAGE
	effect.value = amount
	var card := CardData.new()
	card.card_type = CardData.CardType.SKILL
	card.effects = [effect]
	return card

func _losses(player: Combatant, enemies: Array[Combatant], count: int) -> void:
	for i in count:
		_play(_self_damage(1), player, enemies)

# Resolves `card` as BattleController does: the living, unburied enemies
# in reach, reports recorded in _reports.
func _play(card: CardData, player: Combatant, enemies: Array[Combatant], target: Combatant = null) -> void:
	_reports.clear()
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = target
	var hittable: Array[Combatant] = []
	for enemy in enemies:
		if enemy.hp > 0 and not enemy.buried:
			hittable.append(enemy)
	ctx.enemies = hittable
	ctx.on_damage = func(combatant: Combatant, amount: int, kind: String) -> void:
		_reports.append([combatant, amount, kind])
	_resolver.resolve_card(card, ctx)

func _kinds() -> Array[String]:
	var kinds: Array[String] = []
	for report: Array in _reports:
		kinds.append(report[2] as String)
	return kinds

func _reports_on(combatant: Combatant) -> int:
	var count: int = 0
	for report: Array in _reports:
		if report[0] == combatant:
			count += 1
	return count

# One single-hit enemy Attack for `damage` against the player.
func _attack(player: Combatant, damage: int) -> Dictionary:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.IntentType.ATTACK
	intent.value = damage
	intent.hits = 1
	var data := EnemyData.new()
	data.max_hp = 50
	data.intents = [intent]
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return EnemyTurn.take_turn(enemy, data, player)

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
