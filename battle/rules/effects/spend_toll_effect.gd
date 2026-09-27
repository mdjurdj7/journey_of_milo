extends RefCounted
class_name SpendTollEffect

# Spends exactly toll_cost Toll - the card's price, not a share of what's
# held (contrast TOLL_DAMAGE, TOLL_FRACTION_DAMAGE_ALL, TOLL_HEAL). A card
# carrying one can't be played on less (EffectResolver.card_blocked()), so
# the full cost is always there; EffectContext.spend_toll() clamps all the
# same, so Toll never goes negative whatever reaches here.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.spend_toll(effect.toll_cost)
