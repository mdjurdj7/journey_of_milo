extends RefCounted
class_name AbsorbEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.absorb += effect.value
