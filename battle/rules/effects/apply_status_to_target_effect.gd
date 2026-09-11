extends RefCounted
class_name ApplyStatusToTargetEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if effect.status_data == null or ctx.target == null:
		return
	Status.apply_to(ctx.target.statuses, effect.status_data)
