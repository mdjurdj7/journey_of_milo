extends Resource
class_name FightRarityTable

# The rarity rates a normal fight's card offer rolls with, by depth: each
# step's rates hold from its from_floor until a later step's. Elite and
# region-end offers never read it (their own rates, and the top tier
# first); nor do the collector, bundles or belongings. Hooked onto
# EncounterRewards.fight_rarity_by_floor and read by RegionField for the
# floor being played, so whichever pool the run draws from - a class's,
# shared across floors, or the floor's own - takes the floor's rates.

@export var steps: Array[FightRarityStep] = []:
	set(value):
		steps = value
		emit_changed()

# The rates for the region's `floor_number` (1 = its first): the step with
# the highest from_floor at or below it; null with none - the pool's own
# rates then.
func rates_for_floor(floor_number: int) -> RarityRates:
	var best: FightRarityStep = null
	for step in steps:
		if step == null or step.rates == null or step.from_floor > floor_number:
			continue
		if best == null or step.from_floor > best.from_floor:
			best = step
	return best.rates if best != null else null
