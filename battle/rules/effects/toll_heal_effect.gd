extends RefCounted
class_name TollHealEffect

# Spends UP TO toll_cost Toll - whatever is actually held, if that's less
# - and heals half of what it spent, capped at `value`. The only bounded
# Toll spend in the set: TOLL_DAMAGE takes all of it, TOLL_FRACTION_DAMAGE
# _ALL takes a share, TOLL_BLOCK takes a fixed amount.
#
# It spends only what it converts: an even amount, 2 Toll per HP, never
# past what `value` HP takes. An odd point is left held, not spent for
# nothing - on 13 Toll it spends 12, heals 6 and leaves 1. One Toll alone
# spends nothing at all (so it hurries no Sentence).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var convertible: int = mini(mini(effect.toll_cost, ctx.player.toll), effect.value * 2)
	convertible -= convertible % 2
	var spent: int = ctx.spend_toll(convertible)
	if spent <= 0:
		return
	var healed: int = mini(spent / 2, effect.value)
	if healed <= 0:
		return
	ctx.heal(healed)
