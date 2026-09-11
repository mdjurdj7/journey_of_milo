extends RefCounted
class_name TollBlockEffect

# Spends a FIXED toll_cost (not all of it - contrast TollDamageEffect) and
# gains `value` block, doubled if the player is below half HP.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.toll -= effect.toll_cost
	var block_gained := effect.value
	if ctx.player.hp < ctx.player.max_hp / 2.0:
		block_gained *= 2
	ctx.player.block += block_gained
