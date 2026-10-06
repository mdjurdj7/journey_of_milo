extends Resource
class_name RewardPool

# What a fight can drop. An explicit list of CardData, never a folder
# scan: a scan would sweep in the starters, the Keeper's neutral cards
# and anything else that happens to live under cards/, and adding a
# folder would silently change what every fight drops (see DESIGN.md).
#
# Deliberately not the reward RULES - who rolls, when, how many, and
# where the cards land is RewardSpread's and RegionField's business. This
# resource only answers "what could come out, and how likely".

# The cards this pool can produce. Order is meaningless; weights below
# are matched by index.
@export var entries: Array[CardData] = []

# Parallel to entries. Short or empty is fine - any entry without a
# weight uses 1.0, so an unweighted pool is a flat roll and a pool that
# only wants ONE card nudged can author a single leading value and stop.
# Zero or negative excludes an entry from the roll entirely, which is a
# useful way to shelve a card without deleting the line.
@export var weights: Array[float] = []

# EnemyData -> Array[CardData]: cards this particular enemy is likelier
# to drop, multiplied by enemy_bias_multiplier on top of their base
# weight. Empty in every authored pool today - the hook exists so a
# themed drop ("the crab drops Ballast more often") is data rather than a
# code change, and roll() already honours it.
@export var enemy_bias: Dictionary = {}
@export var enemy_bias_multiplier: float = 2.0

# Per-slot odds of each CardData.CardRarity tier in roll_by_rarity() -
# what a fight's own reward uses; roll() ignores them. Relative weights,
# so they needn't sum to 100. Provisional (60/30/9/1), to be settled in
# playtest. A tier with no eligible card left is dropped and the rest
# renormalised (pick_rarity()), so an empty ULTRA_RARE doesn't hand its
# share to RARE alone.
@export_group("Rarity rates")
@export var common_rate: float = 60.0
@export var uncommon_rate: float = 30.0
@export var rare_rate: float = 9.0
@export var ultra_rare_rate: float = 1.0
# The same, for a fight with an elite in it (EnemyData.is_elite) or a
# placement marked FloorEnemy.elite_card_rates - roll_by_rarity(...,
# elite = true). Common 0 = no Common while a higher tier has a card
# left; renormalised the same way when a tier is empty.
@export_group("Elite rarity rates")
@export var elite_common_rate: float = 0.0
@export var elite_uncommon_rate: float = 75.0
@export var elite_rare_rate: float = 23.0
@export var elite_ultra_rare_rate: float = 2.0
@export_group("")

# `count` distinct cards, weighted, without duplicates within the roll -
# the same card twice in one spread reads as a bug rather than as luck.
# Returns fewer than `count` only when the pool itself holds fewer
# eligible entries. rng is passed in rather than taken from RunState here
# so this stays a pure data object (and so a test can hand it a fixed
# seed); enemy may be null, which simply skips the bias.
func roll(count: int, rng: RandomNumberGenerator, enemy: EnemyData = null) -> Array[CardData]:
	var picked: Array[CardData] = []
	# Index-based so an entry's own weight stays findable as the remaining
	# set shrinks; removing from these two in step is what keeps them
	# parallel through the draw.
	var remaining: Array[int] = []
	for index in entries.size():
		if entries[index] != null and _weight_of(index, enemy) > 0.0:
			remaining.append(index)

	while picked.size() < count and not remaining.is_empty():
		var total: float = 0.0
		for index in remaining:
			total += _weight_of(index, enemy)
		var roll_point: float = rng.randf() * total
		var chosen: int = remaining.size() - 1
		for position in remaining.size():
			roll_point -= _weight_of(remaining[position], enemy)
			if roll_point <= 0.0:
				chosen = position
				break
		picked.append(entries[remaining[chosen]])
		remaining.remove_at(chosen)
	return picked

# A fight's card reward: `count` distinct cards, each slot rolling a
# rarity tier first (pick_rarity()) and then a card of that tier, by the
# same weights and bias roll() uses. Pool membership still decides what
# can drop at all - rarity never adds a card that isn't an entry. Only
# tiers with an eligible card left are rolled, so a tier running dry
# (or ULTRA_RARE, empty today) never costs a slot: this returns fewer
# than `count` only when the pool itself runs out. An UNSET card is
# never offered - see CardData.CardRarity.
# `elite` rolls the tiers at the elite rates instead.
func roll_by_rarity(count: int, rng: RandomNumberGenerator, enemy: EnemyData = null, elite: bool = false) -> Array[CardData]:
	var picked: Array[CardData] = []
	var remaining: Array[int] = []
	for index in entries.size():
		var entry: CardData = entries[index]
		if entry != null and entry.rarity != CardData.CardRarity.UNSET and _weight_of(index, enemy) > 0.0:
			remaining.append(index)

	while picked.size() < count and not remaining.is_empty():
		var available: Array[CardData.CardRarity] = []
		for index in remaining:
			if not available.has(entries[index].rarity):
				available.append(entries[index].rarity)
		var tier: CardData.CardRarity = pick_rarity(rng.randf(), available, elite)
		var in_tier: Array[int] = []
		for index in remaining:
			if entries[index].rarity == tier:
				in_tier.append(index)
		var total: float = 0.0
		for index in in_tier:
			total += _weight_of(index, enemy)
		var roll_point: float = rng.randf() * total
		var chosen: int = in_tier[in_tier.size() - 1]
		for index in in_tier:
			roll_point -= _weight_of(index, enemy)
			if roll_point <= 0.0:
				chosen = index
				break
		picked.append(entries[chosen])
		remaining.erase(chosen)
	return picked

# Which tier a slot rolls, from `point` in [0, 1) and the tiers that
# still have an eligible card. The rates of the available tiers only,
# renormalised - never a step down to the next tier. Split out of
# roll_by_rarity() and handed the point rather than the rng so a probe
# can land each branch exactly. Available tiers whose rates are all zero
# fall back to an even split, so a slot is never lost to tuning.
func pick_rarity(point: float, available: Array[CardData.CardRarity], elite: bool = false) -> CardData.CardRarity:
	var tiers: Array[CardData.CardRarity] = []
	var total: float = 0.0
	for tier in CardData.rarity_tiers():
		if available.has(tier):
			tiers.append(tier)
			total += maxf(rarity_rate(tier, elite), 0.0)
	if tiers.is_empty():
		return CardData.CardRarity.UNSET
	if total <= 0.0:
		return tiers[mini(int(point * float(tiers.size())), tiers.size() - 1)]
	var target: float = point * total
	for tier in tiers:
		target -= maxf(rarity_rate(tier, elite), 0.0)
		if target < 0.0:
			return tier
	return tiers[tiers.size() - 1]

func rarity_rate(tier: CardData.CardRarity, elite: bool = false) -> float:
	if elite:
		match tier:
			CardData.CardRarity.COMMON:
				return elite_common_rate
			CardData.CardRarity.UNCOMMON:
				return elite_uncommon_rate
			CardData.CardRarity.RARE:
				return elite_rare_rate
			CardData.CardRarity.ULTRA_RARE:
				return elite_ultra_rare_rate
		return 0.0
	match tier:
		CardData.CardRarity.COMMON:
			return common_rate
		CardData.CardRarity.UNCOMMON:
			return uncommon_rate
		CardData.CardRarity.RARE:
			return rare_rate
		CardData.CardRarity.ULTRA_RARE:
			return ultra_rare_rate
	return 0.0

func _weight_of(index: int, enemy: EnemyData) -> float:
	var weight: float = weights[index] if index < weights.size() else 1.0
	if enemy != null and enemy_bias.has(enemy):
		var favoured: Array = enemy_bias[enemy]
		if favoured.has(entries[index]):
			weight *= enemy_bias_multiplier
	return weight
