extends RefCounted
class_name TollSpentDamageEffect

# Deals the Toll the player has spent this fight (Combatant.toll_spent_
# this_fight - every EffectContext.spend_toll() since it began, a replay's
# included) and spends none itself, so it hurries no Sentence. `value` is
# unused (Reckoning).
#
# Reckoning is an Attack, so the attack bonus (AttackBonus - stance,
# Keen) lands on it once, as on any damage effect, before the status
# modifiers - with nothing spent yet the blow is the bonus alone.
func resolve(_effect: CardEffect, ctx: EffectContext) -> void:
	if ctx.target == null:
		return
	var base: int = ctx.player.toll_spent_this_fight + ctx.take_attack_bonus()
	if base <= 0:
		return
	var hp_before: int = ctx.target.hp
	ctx.attack_card_extra_this_card += Status.attack_card_extra(base, ctx.player.statuses)
	var result := DamagePipeline.resolve(DamageEffect.landed(base, ctx.player, ctx.target, ctx.is_replay), ctx.target)
	ctx.report_block(ctx.target, result)
	if result["damage_to_hp"] > 0:
		ctx.report_damage(ctx.target, result["damage_to_hp"], "card")
		ctx.record_hit(hp_before - ctx.target.hp, ctx.grace_reclaim(result["damage_to_hp"]))
