extends RefCounted
class_name TollHealEffect

# Spends UP TO toll_cost Toll - whatever is actually held, if that's less
# - and heals half of what it spent, capped at `value`. The only bounded
# Toll spend in the set: TOLL_DAMAGE takes all of it, TOLL_FRACTION_DAMAGE
# _ALL takes a share, TOLL_BLOCK takes a fixed amount.
#
# Integer division on purpose: an odd Toll spend rounds the heal down, so
# spending 7 heals 3 and the leftover point buys nothing. That's the
# card's own bargain, not a rounding accident.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var spent: int = mini(effect.toll_cost, ctx.player.toll)
	if spent <= 0:
		return
	ctx.player.toll -= spent
	var healed: int = mini(spent / 2, effect.value)
	if healed <= 0:
		return
	ctx.heal(healed)
