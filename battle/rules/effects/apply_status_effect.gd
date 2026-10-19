extends RefCounted
class_name ApplyStatusEffect

func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if effect.status_data == null:
		return
	# Energy owed (Come Due's Owed) carries the card's own amount, added
	# up over plays.
	if effect.status_data.energy_debt:
		Status.apply_amount(ctx.player.statuses, effect.status_data, effect.value)
		return
	Status.apply_to(ctx.player.statuses, effect.status_data)
