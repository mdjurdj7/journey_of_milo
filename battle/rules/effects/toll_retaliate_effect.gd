extends RefCounted
class_name TollRetaliateEffect

# Spends a fixed toll_cost and applies status_data to the player - a
# complete no-op (no spend either) if that exact status is already
# active, checked BEFORE the spend.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if effect.status_data == null:
		return
	if Status.find_in(ctx.player.statuses, effect.status_data) != null:
		return
	ctx.player.toll -= effect.toll_cost
	Status.apply_to(ctx.player.statuses, effect.status_data)
