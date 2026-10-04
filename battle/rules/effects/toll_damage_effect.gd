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
	var consumed: int = ctx.spend_toll(ctx.player.toll)
	if ctx.target == null:
		return
	# A mark on the target (Come Due) adds to the blow, once per card, as
	# on any damage effect - so even a Toll-less Reckoning lands it.
	var base: int = consumed + ctx.take_attack_bonus() + ctx.take_mark_bonus(ctx.target)
	if base <= 0:
		return
	var hp_before: int = ctx.target.hp
	var result := DamagePipeline.resolve(DamageEffect.landed(base, ctx.player, ctx.target), ctx.target)
	ctx.report_block(ctx.target, result)
	if result["damage_to_hp"] > 0:
		ctx.report_damage(ctx.target, result["damage_to_hp"], "card")
		ctx.record_hit(hp_before - ctx.target.hp, ctx.grace_reclaim(result["damage_to_hp"]))
