extends RefCounted
class_name DamageEffect

# Covers DAMAGE and its three old-name aliases (TOLL_THRESHOLD_DAMAGE,
# FIRST_CARD_DAMAGE, DAMAGE_ALL) - see effect_resolver.gd's registry and
# CardEffect's own doc on condition/target_scope.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	# Gate or replace, per CardEffect.alt_value (see the Condition enum's
	# own doc). Gate is the original behaviour and still the default; a
	# replace swaps which number is dealt and always deals one. Whichever
	# it is, exactly ONE number goes through the modifiers and the damage
	# pipeline below - the reason this lives here rather than being
	# authored as two stacked DAMAGE effects, which would run the pipeline
	# twice and get blocked twice.
	# Only the REPLACE choice is made here - a pure gate has already been
	# applied by EffectResolver.resolve_card(), which is the one place
	# that decides whether an effect resolves at all.
	var replaces: bool = effect.alt_value != 0
	var base: int = effect.alt_value if (replaces and EffectResolver.condition_met(effect, ctx)) else effect.value

	# The stance's bonus is part of the attack's own number, so it goes in
	# BEFORE the status modifiers - a status that scales outgoing damage
	# scales the whole blow, stance included, rather than only the part
	# the card authored.
	var amount: int = Status.apply_modifiers(base + ctx.stance_attack_bonus, ctx.player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)

	var targets: Array[Combatant] = []
	if effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES:
		targets = ctx.enemies
	elif ctx.target != null:
		targets = [ctx.target]

	for enemy in targets:
		var incoming: int = Status.apply_modifiers(amount, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		var result := DamagePipeline.resolve(incoming, enemy)
		if enemy.hp <= 0:
			ctx.killed_this_card = true
		if result["damage_to_hp"] > 0:
			ctx.report_damage(enemy, result["damage_to_hp"], "card")
			ctx.grace_reclaim(result["damage_to_hp"])
