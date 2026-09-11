extends RefCounted
class_name TollFractionDamageAllEffect

# Spends floor(toll * toll_fraction), deals that much bonus damage to
# every living enemy.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var spent: int = floori(ctx.player.toll * effect.toll_fraction)
	ctx.player.toll -= spent
	if spent <= 0:
		return
	var amount: int = Status.apply_modifiers(spent, ctx.player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	for enemy in ctx.enemies:
		var incoming: int = Status.apply_modifiers(amount, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		var result := DamagePipeline.resolve(incoming, enemy)
		if result["damage_to_hp"] > 0:
			ctx.report_damage(enemy, result["damage_to_hp"], "card")
			ctx.contribute_to_rally(result["damage_to_hp"])
