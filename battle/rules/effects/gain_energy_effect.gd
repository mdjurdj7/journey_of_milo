extends RefCounted
class_name GainEnergyEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.energy = mini(ctx.player.energy + effect.value, ctx.player.max_energy)
