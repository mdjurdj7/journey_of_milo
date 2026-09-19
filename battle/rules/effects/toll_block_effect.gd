extends RefCounted
class_name TollBlockEffect

# Spends a FIXED toll_cost (not all of it - contrast TollDamageEffect) and
# gains `value` block, doubled if the player is below half HP.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	# Clamped: spending more Toll than is held used to leave it negative,
	# which then read as a debt every later Toll effect had to climb out
	# of. Spend what there is.
	ctx.player.toll = maxi(ctx.player.toll - effect.toll_cost, 0)
	var block_gained := effect.value
	if ctx.player.hp < ctx.player.max_hp / 2.0:
		block_gained *= 2
	ctx.player.block += block_gained
