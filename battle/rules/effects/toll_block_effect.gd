extends RefCounted
class_name TollBlockEffect

# Spends UP TO toll_cost Toll - whatever is held, if that's less - and
# gains 1 Block for each Toll spent (Settled Account's second half). Like
# TOLL_HEAL it spends only what it converts: while Block can't be gained
# (Last Resort) it spends nothing, so it marks no Toll spent and hurries
# no Sentence. Anything it does spend goes through EffectContext.spend_
# toll(), so it counts as Toll spent this turn (Gnaw).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var spent: int = ctx.spend_toll(spendable(effect, ctx.player.toll, ctx.player.stance))
	if spent > 0:
		ctx.gain_block(spent)

# What the effect will spend - and so the Block it will add - on `toll`
# held under `stance`: the face's number (CardView's {toll_block}) and
# the play sound's lift read this, so neither can promise what the
# resolver won't pay.
static func spendable(effect: CardEffect, toll: int, stance: Stance) -> int:
	if effect == null or Stance.prevents_block_gain(stance):
		return 0
	return clampi(toll, 0, maxi(effect.toll_cost, 0))

# The Toll `card` will spend through its TOLL_BLOCK effects if played on
# `toll` under `stance` - 0 with none.
static func spendable_by_card(card: CardData, toll: int, stance: Stance) -> int:
	if card == null:
		return 0
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.TOLL_BLOCK:
			return spendable(effect, toll, stance)
	return 0
