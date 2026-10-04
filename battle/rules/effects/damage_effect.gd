extends RefCounted
class_name DamageEffect

# Covers DAMAGE and its three old-name aliases (TOLL_THRESHOLD_DAMAGE,
# FIRST_CARD_DAMAGE, DAMAGE_ALL) - see effect_resolver.gd's registry and
# CardEffect's own doc on condition/target_scope.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	# The number this lands for - value, or alt_value on a met REPLACE -
	# is CardBonus's reading, the same one the card face prints. A pure
	# gate has already been applied by EffectResolver.resolve_card(), the
	# one place that decides whether an effect resolves at all. Exactly
	# ONE number goes through the modifiers and the damage pipeline below
	# - the reason a replace lives here rather than being authored as two
	# stacked DAMAGE effects, which would run the pipeline twice and get
	# blocked twice.
	var base: int = CardBonus.resolved_value(effect, ctx)

	# The attack bonus (stance, Dying Light) is part of the attack's own
	# number, so it goes in BEFORE the status modifiers - a status that
	# scales outgoing damage scales the whole blow, bonus included, rather
	# than only the part the card authored. Taken once per card: a second
	# damage effect on the same Attack gets 0 (take_attack_bonus()).
	var blow: int = base + ctx.take_attack_bonus()

	var targets: Array[Combatant] = []
	if effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES:
		targets = ctx.enemies
	elif ctx.target != null:
		targets = [ctx.target]

	for enemy in targets:
		# A mark on this enemy (Come Due) adds to the blow against it
		# alone, once per card - so it's per target, and like the attack
		# bonus it goes in before the modifiers.
		var hp_before: int = enemy.hp
		var result := DamagePipeline.resolve(landed(blow + ctx.take_mark_bonus(enemy), ctx.player, enemy), enemy)
		if enemy.hp <= 0:
			ctx.killed_this_card = true
		ctx.report_block(enemy, result)
		if result["damage_to_hp"] > 0:
			ctx.report_damage(enemy, result["damage_to_hp"], "card")
			ctx.record_hit(hp_before - enemy.hp, ctx.grace_reclaim(result["damage_to_hp"]))

# The number one blow lands for once the statuses have had their say -
# the attacker's outgoing modifiers, then `enemy`'s incoming ones - ahead
# of block and the damage pipeline. `blow` is everything the card itself
# adds up to: its value, the attack bonus and the mark bonus. A null
# `enemy` (a card face with no one to read against) skips the incoming
# half. The resolvers and the card face both call this, so the face can't
# print a number the rules won't land.
static func landed(blow: int, player: Combatant, enemy: Combatant) -> int:
	var amount: int = Status.apply_modifiers(blow, player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	if enemy == null:
		return amount
	return Status.apply_modifiers(amount, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
