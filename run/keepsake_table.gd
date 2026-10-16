extends Resource
class_name KeepsakeTable

# A source's own small drop table - what one source (an enemy, today:
# EnemyData.keepsake_table) can leave. There is no universal pool and no
# rarity: weighted entries, an optional guarantee, and per-entry
# uniqueness.

@export var entries: Array[KeepsakeEntry] = []
# Always drops something when anything can be drawn. Off: drop_chance
# decides first whether anything drops at all.
@export var guaranteed: bool = true
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 1.0

# One drop, or null. Never the trinket already held (`equipped`), never a
# unique entry already offered this run (`offered`, trinket ids). Draws
# from `rng` - the run's own (RunState.rng) in play.
func roll(rng: RandomNumberGenerator, equipped: TrinketData, offered: Array[StringName]) -> TrinketData:
	if not guaranteed and rng.randf() >= drop_chance:
		return null
	var candidates: Array[KeepsakeEntry] = []
	var total: float = 0.0
	for entry in entries:
		if entry == null or entry.trinket == null or entry.weight <= 0.0:
			continue
		if entry.trinket == equipped:
			continue
		if entry.unique_per_run and offered.has(entry.trinket.id):
			continue
		candidates.append(entry)
		total += entry.weight
	if candidates.is_empty():
		return null
	var pick: float = rng.randf() * total
	for entry in candidates:
		pick -= entry.weight
		if pick < 0.0:
			return entry.trinket
	return candidates.back().trinket

# One worn piece (an elite's EnemyData.armor_table), or null: RARE entries
# with `rare_chance` (0..1), else COMMON - by weight within the tier, never
# the piece already worn (`worn`). A tier with nothing left to give falls
# back to the other, so a win never leaves nothing while the table holds
# a piece he isn't wearing. guaranteed / drop_chance as roll()'s; uniqueness
# isn't read - a worn piece can come up again. Draws from `rng`.
func roll_by_rarity(rng: RandomNumberGenerator, rare_chance: float, worn: TrinketData) -> TrinketData:
	if not guaranteed and rng.randf() >= drop_chance:
		return null
	var rare: Array[KeepsakeEntry] = []
	var common: Array[KeepsakeEntry] = []
	for entry in entries:
		if entry == null or entry.trinket == null or entry.weight <= 0.0 or entry.trinket == worn:
			continue
		if entry.trinket.rarity == CardData.CardRarity.RARE:
			rare.append(entry)
		else:
			common.append(entry)
	var rare_drawn: bool = rng.randf() < clampf(rare_chance, 0.0, 1.0)
	var tier: Array[KeepsakeEntry] = rare if rare_drawn else common
	if tier.is_empty():
		tier = common if rare_drawn else rare
	if tier.is_empty():
		return null
	return _pick_weighted(rng, tier)

func _pick_weighted(rng: RandomNumberGenerator, candidates: Array[KeepsakeEntry]) -> TrinketData:
	var total: float = 0.0
	for entry in candidates:
		total += entry.weight
	var pick: float = rng.randf() * total
	for entry in candidates:
		pick -= entry.weight
		if pick < 0.0:
			return entry.trinket
	return candidates.back().trinket
