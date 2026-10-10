extends Resource
class_name RoleReward

# What a won fight of one encounter role leaves on the reward screen
# (EncounterRewards, one of these per role - BattleController.encounter_role()).
# Read when the screen opens, so an edit applies from the next win.

# The one-of-three card offer (RewardScreen's "A card" line). Off for a
# fight that doesn't matter: an optional basic fight pays in gold.
@export var offers_cards: bool = true
# The floor's gold roll (FloorData.gold_min/max) times this, rounded.
@export var gold_multiplier: float = 1.0
# The chance (0..1) of one extra beside the gold, drawn by weight from
# the two below: a card removal (pick one from the deck, or walk on) or a
# Samphire (EncounterRewards.samphire_card) to take. 0 = never - and then
# nothing is drawn from the run's RNG for it.
@export_range(0.0, 1.0) var extra_chance: float = 0.0
@export var removal_weight: int = 0
@export var samphire_weight: int = 0
