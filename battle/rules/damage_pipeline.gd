extends RefCounted
class_name DamagePipeline

# Block first, then absorb, then - while its holder has a status that has
# Toll pay (StatusData.toll_pays_damage - Thick Skin) - their Toll, then
# whatever's left spills onto HP. Mutates `combatant` directly and returns
# what happened, for the caller to report/signal. A combatant out of
# reach (Combatant.is_out_of_reach() - the buried) takes none of it -
# every card's damage comes through here, so that is the whole of its
# immunity. What reaches HP counts toward damage_taken_this_turn.
#
# Toll paid here is spent, as a card's spend is (EffectContext.spend_
# toll()): toll_spent_this_fight (Reckoning) and toll_spent_this_turn
# (Gnaw) - logged against the status ("status:<id>") - but no card spent
# it, so no Sentence is hurried.
static func resolve(amount: int, combatant: Combatant) -> Dictionary:
	if combatant.is_out_of_reach():
		return {"damage_to_hp": 0, "blocked": 0, "absorbed": 0, "tolled": 0}
	var blocked: int = min(combatant.block, amount)
	var after_block: int = amount - blocked
	var absorbed: int = min(combatant.absorb, after_block)
	var past: int = after_block - absorbed
	var tolled: int = 0
	var payer: Status = Status.toll_payer(combatant.statuses)
	if payer != null and past > 0:
		tolled = mini(maxi(combatant.toll, 0), past)
		if tolled > 0:
			RunLogger.push_source("status:" + payer.data.id)
			combatant.toll -= tolled
			RunLogger.pop_source()
			combatant.toll_spent_this_fight += tolled
			combatant.toll_spent_this_turn = true
	var damage_to_hp: int = past - tolled
	combatant.block -= blocked
	combatant.absorb -= absorbed
	combatant.last_overkill = maxi(damage_to_hp - combatant.hp, 0)
	combatant.hp = max(combatant.hp - damage_to_hp, 0)
	combatant.damage_taken_this_turn += damage_to_hp
	return {
		"damage_to_hp": damage_to_hp,
		"blocked": blocked,
		"absorbed": absorbed,
		"tolled": tolled,
	}

# Self-damage and status ticks bypass block AND absorb entirely, straight
# to HP - and never Toll (Thick Skin pays enemy damage only). Returns the
# amount actually lost (can be less than `amount` if HP was already below
# it).
static func apply_bypass(amount: int, combatant: Combatant) -> int:
	var before := combatant.hp
	combatant.hp = max(combatant.hp - amount, 0)
	return before - combatant.hp
