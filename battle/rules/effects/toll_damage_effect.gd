extends RefCounted
class_name TollDamageEffect

# Consumes ALL current Toll and deals that much damage - `value` is
# unused (the amount is whatever Toll actually is, read fresh here).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var consumed := ctx.player.toll
	ctx.player.toll = 0
	if consumed <= 0 or ctx.target == null:
		return
	var amount: int = Status.apply_modifiers(consumed, ctx.player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	var incoming: int = Status.apply_modifiers(amount, ctx.target.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
	var result := DamagePipeline.resolve(incoming, ctx.target)
	if result["damage_to_hp"] > 0:
		ctx.report_damage(ctx.target, result["damage_to_hp"], "card")
		ctx.contribute_to_rally(result["damage_to_hp"])
