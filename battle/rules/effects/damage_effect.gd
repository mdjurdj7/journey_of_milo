extends RefCounted
class_name DamageEffect

# Covers DAMAGE and its three old-name aliases (TOLL_THRESHOLD_DAMAGE,
# FIRST_CARD_DAMAGE, DAMAGE_ALL) - see effect_resolver.gd's registry and
# CardEffect's own doc on condition/target_scope.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if not EffectResolver.condition_met(effect, ctx):
		return

	var amount: int = Status.apply_modifiers(effect.value, ctx.player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)

	var targets: Array[Combatant] = []
	if effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES:
		targets = ctx.enemies
	elif ctx.target != null:
		targets = [ctx.target]

	for enemy in targets:
		var incoming: int = Status.apply_modifiers(amount, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		var result := DamagePipeline.resolve(incoming, enemy)
		if result["damage_to_hp"] > 0:
			ctx.report_damage(enemy, result["damage_to_hp"], "card")
			ctx.contribute_to_rally(result["damage_to_hp"])
