extends SceneTree

# Headless probe for card rarity, the fight reward's rarity roll, Blood
# Arc, and With Regards joining the Wanderer pool. Rules layer, the real
# .tres cards and pool; no field scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/card_rarity_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# No statistical assertions: the tier roll is driven at exact points
# through RewardPool.pick_rarity(), and the seeded rolls are checked for
# what every roll must hold (three distinct, in the pool), not for shares.

const MAX_HP := 70
const CRITICAL_FRACTION := 0.3
const CASES := 14
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const CARD_DIRS: Array[String] = ["res://cards/data/", "res://cards/neutral/"]
# user:// is shared by every checkout of the project, so the file is named
# for this process: two runs at once (parallel probes, another session's
# suite) never save over or delete each other's.
const SAVE_PATH_FORMAT := "user://card_rarity_probe_ultra_%d.tres"
const SEED_COUNT := 500

# The rarity every implemented card must carry. A card on disk that isn't
# listed here fails - so a new card has to be tagged AND entered here.
const EXPECTED_RARITY: Dictionary = {
	"Slash": CardData.CardRarity.COMMON,
	"Bite Down": CardData.CardRarity.COMMON,
	"Brace": CardData.CardRarity.COMMON,
	"Carve": CardData.CardRarity.COMMON,
	"Endure": CardData.CardRarity.COMMON,
	"Hold Fast": CardData.CardRarity.COMMON,
	"Cornered": CardData.CardRarity.COMMON,
	"Unbroken": CardData.CardRarity.COMMON,
	"Small Price": CardData.CardRarity.COMMON,
	"Down Payment": CardData.CardRarity.COMMON,
	"Bide": CardData.CardRarity.COMMON,
	"Reckoning": CardData.CardRarity.UNCOMMON,
	"Debt Forgiven": CardData.CardRarity.UNCOMMON,
	"Self-Eater": CardData.CardRarity.UNCOMMON,
	"Last Wager": CardData.CardRarity.UNCOMMON,
	"Blood Arc": CardData.CardRarity.UNCOMMON,
	"With Regards": CardData.CardRarity.UNCOMMON,
	"Come Due": CardData.CardRarity.UNCOMMON,
	"Collateral": CardData.CardRarity.UNCOMMON,
	"Leverage": CardData.CardRarity.UNCOMMON,
	"Deny": CardData.CardRarity.UNCOMMON,
	"Dying Light": CardData.CardRarity.RARE,
	"Refuse the End": CardData.CardRarity.RARE,
	"Last Resort": CardData.CardRarity.RARE,
	"No Further": CardData.CardRarity.RARE,
	"Sentence": CardData.CardRarity.RARE,
	"The Return": CardData.CardRarity.RARE,
	"Ransom": CardData.CardRarity.RARE,
	"Left Hand": CardData.CardRarity.COMMON,
	"Second Thoughts": CardData.CardRarity.COMMON,
	"Untouched": CardData.CardRarity.COMMON,
}

const EXPECTED_POOL: Array[String] = [
	"Carve", "Hold Fast", "Small Price", "Debt Forgiven",
	"Self-Eater", "Cornered", "Unbroken", "Dying Light", "Last Wager",
	"Refuse the End", "Last Resort", "Blood Arc", "With Regards", "Come Due",
	"No Further", "Sentence", "The Return", "Collateral", "Ransom", "Leverage",
	"Bide", "Deny",
]
const STARTER_ONLY: Array[String] = ["Slash", "Bite Down", "Brace", "Reckoning", "Down Payment"]

var _failures: int = 0
# Cases that ran to their end. A script error aborts a case without
# failing anything, so the total is checked too.
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	_check_every_card_tagged()
	_check_ultra_rare_supported()
	_check_pool_membership()
	_check_pick_rarity_branches()
	_check_pick_rarity_renormalises()
	_check_seeded_rolls()
	_check_fallback_when_tiers_empty()
	_check_blood_arc_basics()
	_check_blood_arc_order()
	_check_blood_arc_self_eater()
	_check_blood_arc_dying_light()
	_check_blood_arc_last_resort()
	_check_with_regards()
	_check_starting_deck()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("card_rarity_probe: PASSED")
		quit(0)
	else:
		print("card_rarity_probe: %d FAILED" % _failures)
		quit(1)

# --- Rarity data ---

func _check_every_card_tagged() -> void:
	var seen: Array[String] = []
	var tiers: Array[CardData.CardRarity] = CardData.rarity_tiers()
	for card in _all_cards():
		seen.append(card.card_name)
		_expect(card.rarity != CardData.CardRarity.UNSET, "%s is UNSET (%s)" % [card.card_name, card.resource_path])
		_expect(tiers.has(card.rarity), "%s has a real tier (got %d)" % [card.card_name, card.rarity])
		_expect(EXPECTED_RARITY.has(card.card_name), "%s is in the probe's rarity table" % card.card_name)
		if EXPECTED_RARITY.has(card.card_name):
			_expect_eq(card.rarity, EXPECTED_RARITY[card.card_name], "%s's rarity" % card.card_name)
	for card_name: String in EXPECTED_RARITY:
		_expect(seen.has(card_name), "%s exists on disk" % card_name)
	_expect_eq(tiers.size(), 4, "Four real tiers")
	_expect(not tiers.has(CardData.CardRarity.UNSET), "UNSET is not a tier")
	_expect_eq(CardData.new().rarity, CardData.CardRarity.UNSET, "An untagged card reads as UNSET, not Common")
	_completed += 1

# A real tier with no cards: survives a save and load, and a pool whose
# only card is Ultra Rare offers it.
func _check_ultra_rare_supported() -> void:
	var ultra_count: int = 0
	for card in _all_cards():
		if card.rarity == CardData.CardRarity.ULTRA_RARE:
			ultra_count += 1
	_expect_eq(ultra_count, 0, "No implemented card is Ultra Rare yet")

	var card := CardData.new()
	card.card_name = "Probe Ultra"
	card.rarity = CardData.CardRarity.ULTRA_RARE
	var save_path: String = SAVE_PATH_FORMAT % OS.get_process_id()
	_expect_eq(ResourceSaver.save(card, save_path), OK, "An Ultra Rare card saves")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CardData
	_expect(loaded != null and loaded.rarity == CardData.CardRarity.ULTRA_RARE, "...and loads back Ultra Rare")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	var pool := RewardPool.new()
	pool.entries = [card]
	var rolled: Array[CardData] = pool.roll_by_rarity(3, _rng(1))
	_expect(rolled.size() == 1 and rolled[0] == card, "A lone Ultra Rare card is offered")
	_expect_eq(pool.rarity_rate(CardData.CardRarity.ULTRA_RARE), 1.0, "Ultra Rare's default rate is 1")
	_completed += 1

func _check_pool_membership() -> void:
	var pool: RewardPool = _pool()
	var names: Array[String] = []
	for card in pool.entries:
		names.append(card.card_name)
	_expect_eq(names.size(), 22, "Wanderer pool holds 22 cards")
	for card_name in EXPECTED_POOL:
		_expect(names.has(card_name), "%s is in the Wanderer pool" % card_name)
	for card_name in STARTER_ONLY:
		_expect(not names.has(card_name), "Starter %s stays out of the pool" % card_name)
	_expect(names.has("With Regards"), "With Regards is now obtainable")
	_expect_eq([pool.common_rate, pool.uncommon_rate, pool.rare_rate, pool.ultra_rare_rate], [60.0, 30.0, 9.0, 1.0], "Rates are 60/30/9/1")
	_completed += 1

# --- The tier roll ---

# Every tier available: each band of the 60/30/9/1 split, at its edges.
func _check_pick_rarity_branches() -> void:
	var pool: RewardPool = _pool()
	var all: Array[CardData.CardRarity] = CardData.rarity_tiers()
	var cases: Array = [
		[0.0, CardData.CardRarity.COMMON], [0.599, CardData.CardRarity.COMMON],
		[0.6, CardData.CardRarity.UNCOMMON], [0.899, CardData.CardRarity.UNCOMMON],
		[0.9, CardData.CardRarity.RARE], [0.989, CardData.CardRarity.RARE],
		[0.99, CardData.CardRarity.ULTRA_RARE], [0.9999, CardData.CardRarity.ULTRA_RARE],
	]
	for pair: Array in cases:
		_expect_eq(pool.pick_rarity(pair[0], all), pair[1], "All tiers, point %.4f" % pair[0])
	_completed += 1

# Ultra Rare empty: its 1% spread over the rest in proportion (60/30/9 of
# 99), not handed to Rare. 0.6 lands Common here where it lands Uncommon
# with every tier in - a step-down would leave it Uncommon.
func _check_pick_rarity_renormalises() -> void:
	var pool: RewardPool = _pool()
	var no_ultra: Array[CardData.CardRarity] = [CardData.CardRarity.COMMON, CardData.CardRarity.UNCOMMON, CardData.CardRarity.RARE]
	_expect_eq(pool.pick_rarity(0.6, no_ultra), CardData.CardRarity.COMMON, "No Ultra: 0.6 of 99 is Common")
	_expect_eq(pool.pick_rarity(0.9, no_ultra), CardData.CardRarity.UNCOMMON, "No Ultra: 0.9 of 99 is Uncommon")
	_expect_eq(pool.pick_rarity(0.95, no_ultra), CardData.CardRarity.RARE, "No Ultra: 0.95 of 99 is Rare")
	_expect_eq(pool.pick_rarity(0.9999, no_ultra), CardData.CardRarity.RARE, "No Ultra: the top is Rare, never Ultra")
	var upper: Array[CardData.CardRarity] = [CardData.CardRarity.RARE, CardData.CardRarity.UNCOMMON]
	_expect_eq(pool.pick_rarity(0.75, upper), CardData.CardRarity.UNCOMMON, "Uncommon+Rare: 0.75 of 39 is Uncommon")
	_expect_eq(pool.pick_rarity(0.8, upper), CardData.CardRarity.RARE, "Uncommon+Rare: 0.8 of 39 is Rare")
	var only_common: Array[CardData.CardRarity] = [CardData.CardRarity.COMMON]
	_expect_eq(pool.pick_rarity(0.9999, only_common), CardData.CardRarity.COMMON, "Only Common left: always Common")
	var none: Array[CardData.CardRarity] = []
	_expect_eq(pool.pick_rarity(0.5, none), CardData.CardRarity.UNSET, "Nothing available: no tier")
	_completed += 1

# The real pool on fixed seeds: three distinct cards, all pool entries,
# never a starter; the same seed rolls the same three.
func _check_seeded_rolls() -> void:
	var pool: RewardPool = _pool()
	var offered: Dictionary = {}
	for seed_value in SEED_COUNT:
		var rolled: Array[CardData] = pool.roll_by_rarity(3, _rng(seed_value))
		if rolled.size() != 3:
			_fail("seed %d: %d cards, not 3" % [seed_value, rolled.size()])
			continue
		if rolled[0] == rolled[1] or rolled[0] == rolled[2] or rolled[1] == rolled[2]:
			_fail("seed %d: a card offered twice" % seed_value)
		for card in rolled:
			offered[card.card_name] = true
			if not pool.entries.has(card):
				_fail("seed %d: %s isn't in the pool" % [seed_value, card.card_name])
			if STARTER_ONLY.has(card.card_name):
				_fail("seed %d: starter %s offered" % [seed_value, card.card_name])
	_expect(offered.has("With Regards"), "With Regards comes up across %d seeds" % SEED_COUNT)
	_expect(offered.has("Blood Arc"), "Blood Arc comes up across %d seeds" % SEED_COUNT)
	_expect_eq(pool.roll_by_rarity(3, _rng(42)), pool.roll_by_rarity(3, _rng(42)), "Same seed, same three")
	_completed += 1

# Tiers running dry mid-roll, and rates pointing at an empty tier: still
# three cards whenever three exist, and an UNSET card is never offered.
func _check_fallback_when_tiers_empty() -> void:
	var one_each := RewardPool.new()
	one_each.entries = [_tagged(CardData.CardRarity.COMMON), _tagged(CardData.CardRarity.UNCOMMON), _tagged(CardData.CardRarity.RARE)]
	for seed_value in 50:
		var rolled: Array[CardData] = one_each.roll_by_rarity(3, _rng(seed_value))
		_expect_eq(rolled.size(), 3, "One per tier, seed %d: every slot filled" % seed_value)

	# Every rate on Ultra Rare, no Ultra Rare card: the tier is dropped and
	# the zero-rated rest split evenly rather than lose the slot.
	var commons := RewardPool.new()
	commons.entries = [_tagged(CardData.CardRarity.COMMON), _tagged(CardData.CardRarity.COMMON), _tagged(CardData.CardRarity.COMMON)]
	commons.common_rate = 0.0
	commons.uncommon_rate = 0.0
	commons.rare_rate = 0.0
	commons.ultra_rare_rate = 100.0
	_expect_eq(commons.roll_by_rarity(3, _rng(7)).size(), 3, "Rates only on an empty Ultra Rare: still three")

	var short := RewardPool.new()
	var unset := CardData.new()
	short.entries = [_tagged(CardData.CardRarity.RARE), unset, _tagged(CardData.CardRarity.COMMON)]
	var rolled: Array[CardData] = short.roll_by_rarity(3, _rng(3))
	_expect_eq(rolled.size(), 2, "Two eligible cards: two offered")
	_expect(not rolled.has(unset), "An UNSET card is never offered")
	_expect_eq(short.roll(3, _rng(3)).size(), 3, "The flat roll() is untouched by rarity")
	_completed += 1

# --- Blood Arc ---

func _check_blood_arc_basics() -> void:
	var card: CardData = _card("blood_arc")
	_expect_eq(card.cost, 2, "Blood Arc costs 2")
	_expect_eq(card.card_type, CardData.CardType.ATTACK, "Blood Arc is an Attack")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "Blood Arc is Uncommon")

	var player: Combatant = _player(50)
	player.block = 10
	player.absorb = 4
	var enemies: Array[Combatant] = [Combatant.new(100), Combatant.new(100), Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(player.hp, 47, "Blood Arc loses 3 HP past Block and absorb")
	_expect_eq(player.block, 10, "...Block untouched")
	_expect_eq(player.absorb, 4, "...absorb untouched")
	_expect_eq(player.toll, 3, "...and makes 3 Toll")
	_expect_eq(player.grace, 0, "...and opens no Grace")
	for index in enemies.size():
		_expect_eq(enemies[index].hp, 91, "Blood Arc deals 9 to enemy %d" % index)

	player = _player(2)
	_play_into(card, player, [Combatant.new(100)])
	_expect_eq(player.hp, 0, "Blood Arc at 2 HP kills, like any self-damage")
	_completed += 1

# The HP is lost before the blow - the reports come in that order, and
# the blow is judged Critical at the HP the loss left.
func _check_blood_arc_order() -> void:
	var card: CardData = _card("blood_arc")
	var player: Combatant = _player(24)
	var enemy := Combatant.new(100)
	var reports: Array[String] = []
	var ctx: EffectContext = _ctx(player, [enemy])
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		reports.append("%s:%d" % [kind, amount])
	_resolver.resolve_card(card, ctx)
	_expect_eq(reports, ["self:3", "card:9"] as Array[String], "Self-loss reported before the blow")
	_expect(player.is_critical(), "24 -> 21 is Critical")
	_completed += 1

func _check_blood_arc_self_eater() -> void:
	var card: CardData = _card("blood_arc")
	var player: Combatant = _player(50)
	_play_into(_card("self_eater"), player, [Combatant.new(100)])
	var enemies: Array[Combatant] = [Combatant.new(100), Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(player.hp, 45, "Self-Eater's 2 and Blood Arc's 3")
	_expect_eq(player.toll, 5, "...all Toll")
	_expect_eq(enemies[0].hp, 88, "Self-Eater +3 on Blood Arc: 12")
	_expect_eq(enemies[1].hp, 88, "...to every enemy")

	# Self-Eater and Blood Arc together pay 26 -> 21 into Critical, where
	# Dying Light lights for the blow.
	player = _player(26)
	_play_into(_card("dying_light"), player, [Combatant.new(100)])
	_play_into(_card("self_eater"), player, [Combatant.new(100)])
	enemies = [Combatant.new(100), Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(player.hp, 21, "26 - 2 - 3 = 21")
	_expect_eq(enemies[0].hp, 85, "Self-Eater + Dying Light paid into: 9 + 3 + 3")
	_expect_eq(enemies[1].hp, 85, "...to every enemy")
	_completed += 1

func _check_blood_arc_dying_light() -> void:
	var card: CardData = _card("blood_arc")
	var player: Combatant = _player(24)
	_play_into(_card("dying_light"), player, [Combatant.new(100)])
	var enemies: Array[Combatant] = [Combatant.new(100), Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(enemies[0].hp, 88, "Blood Arc pays 24 -> 21, Dying Light +3: 12")
	_expect_eq(enemies[1].hp, 88, "...to every enemy")

	player = _player(30)
	_play_into(_card("dying_light"), player, [Combatant.new(100)])
	enemies = [Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(enemies[0].hp, 91, "30 -> 27 stays above: no Dying Light")
	_completed += 1

func _check_blood_arc_last_resort() -> void:
	var card: CardData = _card("blood_arc")
	var player: Combatant = _player(24)
	_play_into(_card("last_resort"), player, [Combatant.new(100)])
	var enemies: Array[Combatant] = [Combatant.new(100), Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(player.hp, 21, "Last Resort charges no HP")
	_expect_eq(enemies[0].hp, 85, "Blood Arc pays into Critical, Last Resort +6: 15")
	_expect_eq(enemies[1].hp, 85, "...to every enemy")

	player = _player(30)
	_play_into(_card("last_resort"), player, [Combatant.new(100)])
	enemies = [Combatant.new(100)]
	_play_into(card, player, enemies)
	_expect_eq(enemies[0].hp, 91, "Above the line: no Last Resort bonus")
	_completed += 1

# --- With Regards ---

func _check_with_regards() -> void:
	var card: CardData = _card("with_regards")
	_expect_eq(card.cost, 1, "With Regards costs 1")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "With Regards is Uncommon")

	var player: Combatant = _player(50)
	player.energy = 1
	var enemy := Combatant.new(8)
	_play_into(card, player, [enemy])
	_expect_eq(enemy.hp, 0, "With Regards kills an 8 HP enemy")
	_expect_eq(player.energy, 2, "...and refunds 1 Energy")

	player.energy = 1
	enemy = Combatant.new(20)
	_play_into(card, player, [enemy])
	_expect_eq(enemy.hp, 12, "With Regards deals 8")
	_expect_eq(player.energy, 1, "No kill, no Energy")

	# A kill by an earlier card doesn't carry over into this one.
	player.energy = 1
	_play_into(_card("carve"), player, [Combatant.new(6), Combatant.new(100)])
	enemy = Combatant.new(20)
	_play_into(card, player, [enemy])
	_expect_eq(player.energy, 1, "An earlier card's kill pays nothing")

	# The attack bonus is part of its blow: Self-Eater's +3 kills 11 HP.
	player = _player(50)
	_play_into(_card("self_eater"), player, [Combatant.new(100)])
	player.energy = 0
	enemy = Combatant.new(11)
	_play_into(card, player, [enemy])
	_expect_eq(enemy.hp, 0, "With Regards + Self-Eater kills 11")
	_expect_eq(player.energy, 1, "...and refunds 1")
	_completed += 1

func _check_starting_deck() -> void:
	var character: CharacterData = load(CHARACTER_PATH) as CharacterData
	var counts: Dictionary = {}
	for card: CardData in character.starting_deck_counts:
		counts[card.card_name] = character.starting_deck_counts[card]
	_expect_eq(counts, {"Slash": 4, "Bite Down": 2, "Brace": 2, "Reckoning": 1, "Down Payment": 1}, "Starting deck unchanged")
	_completed += 1

# --- Helpers ---

func _all_cards() -> Array[CardData]:
	var cards: Array[CardData] = []
	for dir in CARD_DIRS:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tres"):
				var card := load(dir + file) as CardData
				if card == null:
					_fail("%s%s isn't a CardData" % [dir, file])
				else:
					cards.append(card)
	return cards

func _pool() -> RewardPool:
	return load(POOL_PATH) as RewardPool

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

func _tagged(rarity: CardData.CardRarity) -> CardData:
	var card := CardData.new()
	card.rarity = rarity
	return card

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = CRITICAL_FRACTION
	return player

func _ctx(player: Combatant, enemies: Array[Combatant]) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = enemies
	ctx.target = enemies[0] if not enemies.is_empty() else null
	return ctx

func _play_into(card: CardData, player: Combatant, enemies: Array[Combatant]) -> void:
	_resolver.resolve_card(card, _ctx(player, enemies))

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
