extends RefCounted
class_name ApplyStatusEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if effect.status_data == null:
		return
	Status.apply_to(ctx.player.statuses, effect.status_data)
