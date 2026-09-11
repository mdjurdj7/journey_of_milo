extends RefCounted
class_name BlockEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.block += effect.value
