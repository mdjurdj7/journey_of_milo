extends RefCounted
class_name WeaponPool
# Shared "read the weapon pool off disk, then roll one by rarity" helper
# - same small-RefCounted-utility shape as CardPool/EnemyPool/
# EncounterPool/WeightedRandom. Equipment isn't per-class the way cards
# are (see DESIGN.md's Rare Drops pillar - equipment is universal, not
# scoped to CharacterData.card_pool_folder), so this scans one fixed
# folder rather than a class-specific path.

const WEAPON_FOLDER := "res://resources/weapons/"

static func load_pool() -> Array[WeaponData]:
	var pool: Array[WeaponData] = []
	var dir := DirAccess.open(WEAPON_FOLDER)
	# Same "missing folder is a real possibility, not a crash" stance
	# CardPool.load_class_pool() already takes - DirAccess.open()
	# returns null instead of raising an error when the folder's gone.
	if dir == null:
		push_error("Weapon pool folder not found: %s" % WEAPON_FOLDER)
		return pool
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			pool.append(load(WEAPON_FOLDER + file_name))
	return pool

# Rolls a rarity via WeightedRandom, then picks a random weapon matching
# it from the pool - same shape reward_screen.gd's own _pick_card_by_
# rarity() uses for the regular card-choice roll, "consistent with how
# card rarity rolls work" per the brief this was built for. If nothing
# in the pool is that rare, steps down one tier at a time until it
# finds one that actually has a weapon (COMMON is the floor, matching
# the card system's own fallback) - today every weapon is RARE, so
# whatever tier gets rolled, this always lands there; an empty tier is
# a content gap, not a bug, same stance _pick_card_by_rarity() already
# takes toward its own thin tiers. Returns null only if the pool itself
# is completely empty (no weapons exist at all).
static func pick_weighted(common_weight: float, rare_weight: float) -> WeaponData:
	var pool := load_pool()
	if pool.is_empty():
		return null
	var rarity: CardData.Rarity = WeightedRandom.pick({
		CardData.Rarity.COMMON: common_weight,
		CardData.Rarity.RARE: rare_weight,
	})
	while rarity >= CardData.Rarity.COMMON:
		var matches := pool.filter(func(w): return w.rarity == rarity)
		if not matches.is_empty():
			return matches.pick_random()
		rarity -= 1
	return pool.pick_random()
