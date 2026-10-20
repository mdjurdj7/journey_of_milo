extends RefCounted
class_name TollBlockEffect

# Spends exactly toll_cost Toll for `value` more Block (Settled Account's
# second half) - all or nothing: on less Toll held it spends nothing and
# gains nothing. While Block can't be gained (Last Resort) it spends
# nothing either, so it marks no Toll spent and hurries no Sentence. A
# spend goes through EffectContext.spend_toll(), so it counts as Toll
# spent this turn (Gnaw).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if not pays(effect, ctx.player.toll, ctx.player.stance):
		return
	ctx.spend_toll(effect.toll_cost)
	ctx.gain_block(effect.value)

# Whether the effect spends - and so adds its Block - on `toll` held
# under `stance`: the face's live clause (CardBonus.state()) and the play
# sound's lift read this, so neither can promise what the resolver won't
# pay.
static func pays(effect: CardEffect, toll: int, stance: Stance) -> bool:
	if effect == null or effect.toll_cost <= 0 or Stance.prevents_block_gain(stance):
		return false
	return toll >= effect.toll_cost
