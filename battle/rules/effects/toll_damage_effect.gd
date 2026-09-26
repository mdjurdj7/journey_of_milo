extends RefCounted
class_name TollDamageEffect

# Consumes ALL current Toll and deals that much damage - `value` is
# unused (the amount is whatever Toll actually is, read fresh here). Toll
# the stance's HP price just made counts: that price is paid before any
# effect (EffectResolver.resolve_card()), so Self-Eater's 2 HP is 2 more
# Toll spent here.
#
# Reckoning is an Attack, so the attack bonus (AttackBonus - stance,
# Dying Light) lands on it once, as on any damage effect, before the
# status modifiers - with no Toll at all the blow is the bonus alone.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var consumed := ctx.player.toll
	ctx.player.toll = 0
	var base: int = consumed + ctx.take_attack_bonus()
	if base <= 0 or ctx.target == null:
		return
	var amount: int = Status.apply_modifiers(base, ctx.player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	var incoming: int = Status.apply_modifiers(amount, ctx.target.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
	var result := DamagePipeline.resolve(incoming, ctx.target)
	if result["damage_to_hp"] > 0:
		ctx.report_damage(ctx.target, result["damage_to_hp"], "card")
		ctx.grace_reclaim(result["damage_to_hp"])
