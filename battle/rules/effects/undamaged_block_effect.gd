extends RefCounted
class_name UndamagedBlockEffect

# `value` block, PLUS `bonus_value` more if the player took no HP loss
# during their previous turn - ADDS, doesn't replace.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var block_gained := effect.value
	if not ctx.player.took_damage_last_turn:
		block_gained += effect.bonus_value
	ctx.player.block += block_gained
