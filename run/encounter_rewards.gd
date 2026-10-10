extends Resource
class_name EncounterRewards

# A won fight's reward by its encounter role - the strongest any member
# is (BattleController.encounter_role()): region_end, elite, required, else
# basic. Cards only from the fights that matter; an optional basic fight
# pays more gold and sometimes an extra instead (RoleReward). Loaded by
# RegionField when the reward screen opens; nothing is set per enemy.
# Glassbone, keepsakes and belongings are their own.

enum Extra { NONE, REMOVAL, SAMPHIRE }

@export var region_end: RoleReward = null
@export var elite: RoleReward = null
@export var required: RoleReward = null
@export var basic: RoleReward = null
# The card a SAMPHIRE extra offers.
@export var samphire_card: CardData = null

# The entry for `role` (BattleController.encounter_role()'s names), null for an
# unknown one.
func for_role(role: String) -> RoleReward:
	match role:
		"region_end":
			return region_end
		"elite":
			return elite
		"required":
			return required
		"basic":
			return basic
	return null

# Whether `reward` leaves an extra, and which: one draw against its
# extra_chance, then one by weight. Draws nothing from `rng` when the
# chance is 0, so a role without extras rolls exactly as it did.
func roll_extra(reward: RoleReward, rng: RandomNumberGenerator) -> Extra:
	if reward == null or reward.extra_chance <= 0.0:
		return Extra.NONE
	if rng.randf() >= reward.extra_chance:
		return Extra.NONE
	var removal: int = maxi(reward.removal_weight, 0)
	var samphire: int = maxi(reward.samphire_weight, 0) if samphire_card != null else 0
	if removal + samphire <= 0:
		return Extra.NONE
	return Extra.REMOVAL if rng.randi_range(1, removal + samphire) <= removal else Extra.SAMPHIRE
