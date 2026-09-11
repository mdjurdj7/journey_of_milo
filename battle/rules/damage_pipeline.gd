extends RefCounted
class_name DamagePipeline

# Block first, then absorb, then whatever's left spills onto HP. Mutates
# `combatant` directly and returns what happened, for the caller to
# report/signal.
static func resolve(amount: int, combatant: Combatant) -> Dictionary:
	var blocked: int = min(combatant.block, amount)
	var after_block: int = amount - blocked
	var absorbed: int = min(combatant.absorb, after_block)
	var damage_to_hp: int = after_block - absorbed
	combatant.block -= blocked
	combatant.absorb -= absorbed
	combatant.hp = max(combatant.hp - damage_to_hp, 0)
	return {
		"damage_to_hp": damage_to_hp,
		"blocked": blocked,
		"absorbed": absorbed,
	}

# Self-damage and status ticks bypass block AND absorb entirely, straight
# to HP. Returns the amount actually lost (can be less than `amount` if
# HP was already below it).
static func apply_bypass(amount: int, combatant: Combatant) -> int:
	var before := combatant.hp
	combatant.hp = max(combatant.hp - amount, 0)
	return before - combatant.hp
