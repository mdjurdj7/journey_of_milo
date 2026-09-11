extends RefCounted
class_name HealEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.hp = mini(ctx.player.hp + effect.value, ctx.player.max_hp)
