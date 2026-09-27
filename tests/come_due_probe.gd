extends SceneTree

# Headless probe for Come Due: the Toll it requires and spends, the mark
# it leaves on an enemy, and how Attacks spend that mark. Rules layer and
# the real .tres cards, status and pool; no field scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/come_due_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const MAX_HP := 70
const CASES := 13
const BONUS := 4
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const BELONGINGS_POOL_PATH := "res://cards/pools/belongings_pool.tres"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BATTLE_CONTROLLER_PATH := "res://battle/battle_controller.gd"

var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	_check_card_data()
	_check_toll_requirement()
	_check_spend_and_mark()
	_check_single_target_attack()
	_check_three_attacks_spend_it()
	_check_aoe_attack()
	_check_multi_hit_attack()
	_check_non_attacks_leave_it()
	_check_replay_refreshes()
	_check_reckoning()
	_check_death_clears_row()
	_check_pool()
	_check_toll_never_negative()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("come_due_probe: PASSED")
		quit(0)
	else:
		print("come_due_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = _card("come_due")
	_expect_eq(card.card_name, "Come Due", "The card is named Come Due")
	_expect_eq(card.cost, 1, "...costs 1")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...is Uncommon")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect(card.art == null, "...has no art yet (the glyph stands in)")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...and its face reads TOLL")
	_completed += 1

func _check_toll_requirement() -> void:
	var card: CardData = _card("come_due")
	var player: Combatant = _player()
	player.toll = 4
	_expect(EffectResolver.card_blocked(card, player), "Can't be played on 4 Toll")
	player.toll = 5
	_expect(not EffectResolver.card_blocked(card, player), "...can on 5")
	player.toll = 12
	_expect(not EffectResolver.card_blocked(card, player), "...and on 12")
	_completed += 1

func _check_spend_and_mark() -> void:
	var player: Combatant = _player()
	player.toll = 7
	var enemy := Combatant.new(100)
	_play(_card("come_due"), player, [enemy])
	_expect_eq(player.toll, 2, "Played on 7 Toll, it spends exactly 5")
	var mark: Status = _mark(enemy)
	_expect(mark != null, "...and marks the target")
	if mark != null:
		_expect_eq(mark.magnitude, 3, "...with 3 charges")
		_expect_eq(mark.label(), "Come Due ×3", "...shown as Come Due ×3")
	_expect_eq(player.statuses.size(), 0, "...and nothing on the player")
	player.toll = 5
	_play(_card("come_due"), player, [Combatant.new(100)])
	_expect_eq(player.toll, 0, "Played on exactly 5, it leaves 0")
	_completed += 1

func _check_single_target_attack() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	var slash: CardData = _card("slash")
	_play(slash, player, [enemy])
	_expect_eq(enemy.hp, 100 - _damage(slash) - BONUS, "Slash on the mark deals 4 more")
	_expect_eq(_charges(enemy), 2, "...and spends one charge")
	_expect_eq(_mark(enemy).label(), "Come Due ×2", "...shown as Come Due ×2")
	_completed += 1

func _check_three_attacks_spend_it() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	var slash: CardData = _card("slash")
	var bite: CardData = _card("bite_down")
	_play(slash, player, [enemy])
	_play(bite, player, [enemy])
	_expect_eq(_mark(enemy).label(), "Come Due ×1", "Two Attacks in, Come Due ×1")
	_play(slash, player, [enemy])
	_expect(_mark(enemy) == null, "The third Attack spends the last charge and the mark is gone")
	var expected: int = 100 - 3 * BONUS - 2 * _damage(slash) - _damage(bite)
	_expect_eq(enemy.hp, expected, "...each of the three dealt 4 more")
	_play(slash, player, [enemy])
	_expect_eq(enemy.hp, expected - _damage(slash), "A fourth Attack gets no bonus")
	_completed += 1

func _check_aoe_attack() -> void:
	for card_name in ["carve", "blood_arc"]:
		var card: CardData = _card(card_name)
		var player: Combatant = _player()
		var marked: Combatant = _marked(player)
		var other := Combatant.new(100)
		_play(card, player, [other, marked])
		_expect_eq(marked.hp, 100 - _damage(card) - BONUS, "%s: the marked enemy takes 4 more" % card.card_name)
		_expect_eq(other.hp, 100 - _damage(card), "%s: the other takes normal damage" % card.card_name)
		_expect_eq(_charges(marked), 2, "%s: exactly one charge spent" % card.card_name)
	_completed += 1

# No card deals damage twice yet, so the probe builds one: two 3-damage
# effects on one Attack.
func _check_multi_hit_attack() -> void:
	var card := CardData.new()
	card.card_name = "Probe Twice"
	card.card_type = CardData.CardType.ATTACK
	card.effects = [_damage_effect(3), _damage_effect(3)] as Array[CardEffect]
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	_play(card, player, [enemy])
	_expect_eq(enemy.hp, 100 - 3 - 3 - BONUS, "A two-hit Attack gets 4 more once, not per hit")
	_expect_eq(_charges(enemy), 2, "...and spends one charge")
	_completed += 1

func _check_non_attacks_leave_it() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	for card_name in ["endure", "brace", "down_payment"]:
		_play(_card(card_name), player, [enemy])
	_expect_eq(_charges(enemy), 3, "Skills leave every charge in place")
	# And damage from a non-Attack - none exists yet, so built here.
	var jab := CardData.new()
	jab.card_name = "Probe Skill Damage"
	jab.card_type = CardData.CardType.SKILL
	jab.effects = [_damage_effect(6)] as Array[CardEffect]
	var before: int = enemy.hp
	_play(jab, player, [enemy])
	_expect_eq(before - enemy.hp, 6, "Non-Attack damage gets no bonus")
	_expect_eq(_charges(enemy), 3, "...and spends no charge")
	_completed += 1

func _check_replay_refreshes() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	var slash: CardData = _card("slash")
	_play(slash, player, [enemy])
	_expect_eq(_charges(enemy), 2, "One Attack in, 2 charges")
	player.toll = 5
	_play(_card("come_due"), player, [enemy])
	var mark: Status = _mark(enemy)
	_expect_eq(mark.magnitude, 3, "Replaying refreshes to 3 charges")
	_expect_eq(mark.stack_count, 1, "...one mark, not a second stack")
	_expect_eq(enemy.statuses.size(), 1, "...one status on the enemy")
	player.toll = 5
	_play(_card("come_due"), player, [enemy])
	_expect_eq(_charges(enemy), 3, "Replaying at full is still 3, never 6")
	var before: int = enemy.hp
	_play(slash, player, [enemy])
	_expect_eq(before - enemy.hp, _damage(slash) + BONUS, "...and the bonus stays 4")
	_completed += 1

func _check_reckoning() -> void:
	var reckoning: CardData = _card("reckoning")
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	player.toll = 6
	_play(reckoning, player, [enemy])
	_expect_eq(enemy.hp, 100 - 6 - BONUS, "Reckoning on 6 Toll deals 6 + 4")
	_expect_eq(_charges(enemy), 2, "...and spends one charge")
	_play(reckoning, player, [enemy])
	_expect_eq(enemy.hp, 100 - 6 - 2 * BONUS, "A Toll-less Reckoning still lands the 4")
	_expect_eq(_charges(enemy), 1, "...spending a charge")
	_completed += 1

# A dead enemy's status goes with it: BattleController reads no row for it
# (the fight's combatants are rebuilt next fight, so nothing carries over).
func _check_death_clears_row() -> void:
	var controller: Object = (load(BATTLE_CONTROLLER_PATH) as GDScript).new()
	var player: Combatant = _player()
	var enemy: Combatant = _marked(player)
	# Loaded, not named: FieldEnemy compiles against the RunState autoload,
	# which a -s probe can't see at compile time.
	var field_enemy: Node = (load("res://field/field_enemy.gd") as GDScript).new()
	controller._combatants[field_enemy] = enemy
	_expect_eq(controller.get_enemy_status_labels(field_enemy), PackedStringArray(["Come Due ×3"]), "A living marked enemy's row reads Come Due ×3")
	enemy.hp = 2
	_play(_card("slash"), player, [enemy])
	_expect_eq(enemy.hp, 0, "Slash kills it")
	_expect_eq(controller.get_enemy_status_labels(field_enemy), PackedStringArray(), "...and its row is empty")
	field_enemy.free()
	controller.free()
	_completed += 1

func _check_pool() -> void:
	var pool := load(POOL_PATH) as RewardPool
	var entry: CardData = null
	for card in pool.entries:
		if card != null and card.card_name == "Come Due":
			entry = card
	_expect(entry != null, "Come Due is in the Wanderer reward pool")
	if entry != null:
		_expect_eq(entry.rarity, CardData.CardRarity.UNCOMMON, "...as Uncommon")
	var belongings := load(BELONGINGS_POOL_PATH) as RewardPool
	for card in belongings.entries:
		_expect(card == null or card.card_name != "Come Due", "...not in the belongings (Keeper) pool")
	var character := load(CHARACTER_PATH) as CharacterData
	for card: CardData in character.starting_deck_counts:
		_expect(card.card_name != "Come Due", "...nor the starting deck")
	_completed += 1

func _check_toll_never_negative() -> void:
	# Past the gate - straight to the effect - it still can't dig below 0.
	var player: Combatant = _player()
	player.toll = 3
	var ctx: EffectContext = _ctx(player, [Combatant.new(100)])
	var spend: CardEffect = _card("come_due").effects[0]
	(load("res://battle/rules/effects/spend_toll_effect.gd") as GDScript).new().resolve(spend, ctx)
	_expect_eq(player.toll, 0, "Spending 5 of 3 Toll leaves 0, never -2")
	_completed += 1

# --- Helpers ---

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.critical_hp_fraction = 0.3
	return player

# A fresh 100 HP enemy with Come Due freshly on it.
func _marked(player: Combatant) -> Combatant:
	var enemy := Combatant.new(100)
	player.toll = 5
	_play(_card("come_due"), player, [enemy])
	return enemy

func _mark(enemy: Combatant) -> Status:
	for active in enemy.statuses:
		if active.data != null and active.data.id == "come_due":
			return active
	return null

func _charges(enemy: Combatant) -> int:
	var mark: Status = _mark(enemy)
	return mark.magnitude if mark != null else 0

# The first damage effect's authored value.
func _damage(card: CardData) -> int:
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.DAMAGE:
			return effect.value
	return 0

func _damage_effect(value: int) -> CardEffect:
	var effect := CardEffect.new()
	effect.effect_type = CardEffect.EffectType.DAMAGE
	effect.value = value
	return effect

# The target is the LAST enemy listed, so an all-enemies card can be
# checked with the marked enemy after an unmarked one.
func _ctx(player: Combatant, enemies: Array[Combatant]) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = enemies
	ctx.target = enemies[enemies.size() - 1] if not enemies.is_empty() else null
	return ctx

func _play(card: CardData, player: Combatant, enemies: Array[Combatant]) -> void:
	_resolver.resolve_card(card, _ctx(player, enemies))

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
