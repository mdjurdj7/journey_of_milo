extends RefCounted
class_name HealEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.heal(effect.value)
