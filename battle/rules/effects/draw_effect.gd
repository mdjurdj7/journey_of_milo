extends RefCounted
class_name DrawEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.deck.draw(effect.value)
