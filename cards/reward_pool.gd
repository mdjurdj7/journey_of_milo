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

func _weight_of(index: int, enemy: EnemyData) -> float:
	var weight: float = weights[index] if index < weights.size() else 1.0
	if enemy != null and enemy_bias.has(enemy):
		var favoured: Array = enemy_bias[enemy]
		if favoured.has(entries[index]):
			weight *= enemy_bias_multiplier
	return weight
