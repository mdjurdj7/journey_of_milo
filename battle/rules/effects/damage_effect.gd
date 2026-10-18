extends RefCounted
class_name DamageEffect

# Covers DAMAGE and its three old-name aliases (TOLL_THRESHOLD_DAMAGE,
# FIRST_CARD_DAMAGE, DAMAGE_ALL) - see effect_resolver.gd's registry and
# CardEffect's own doc on condition/target_scope.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	# The number this lands for - value, or alt_value on a met REPLACE or
	# a met DRAIN that sets one - is CardBonus's reading, the same one the card face prints. A pure
	# gate has already been applied by EffectResolver.resolve_card(), the
	# one place that decides whether an effect resolves at all. Exactly
	# ONE number goes through the modifiers and the damage pipeline below
	# - the reason a replace lives here rather than being authored as two
	# stacked DAMAGE effects, which would run the pipeline twice and get
	# blocked twice.
	var base: int = CardBonus.resolved_value(effect, ctx)

	var targets: Array[Combatant] = []
	if effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES:
		targets = ctx.enemies
	elif ctx.target != null:
		targets = [ctx.target]

	# The attack bonus (stance, Keen) is part of the attack's own
	# number, so it goes in BEFORE the status modifiers - a status that
	# scales outgoing damage scales the whole blow, bonus included, rather
	# than only the part the card authored. Taken once per card: a second
	# damage effect on the same Attack gets 0 (take_attack_bonus()).
	# Whether its hits drain is judged now, before they land
	# (CardBonus.drains() - always for `drains`, on a met condition for
	# drain_on_condition).
	var drains: bool = CardBonus.drains(effect, ctx)
	_drain(drains, _land(base + ctx.take_attack_bonus(), targets, ctx), ctx)

	# Lash's further hits (repeat_per_earlier_play_tag): one for each
	# card of its tag played earlier this turn, each a repeat as Second
	# Swing's is below - on what the hit before left standing, so a kill
	# ends the chain, and a broken mound hands it to the enemy under it.
	var struck: Array[Combatant] = targets
	for i in hit_count(effect, ctx) - 1:
		struck = _standing_after(struck, ctx)
		if struck.is_empty():
			return
		if ctx.on_extra_hit.is_valid():
			ctx.on_extra_hit.call()
		ctx.repeat_mark_bonus(struck)
		_drain(drains, _land(base + ctx.take_repeat_attack_bonus(), struck, ctx), ctx)

	# A repeat (Second Swing): judged as the first hit resolves, on what
	# it left standing - a first hit that killed everything it struck
	# skips the repeat and spends nothing. Otherwise a player holding the
	# Toll spends it and the same hit lands again: the same number, with
	# the ongoing bonus again (take_repeat_attack_bonus()) and a mark's
	# bonus again, spending another charge (repeat_mark_bonus()), but not
	# a one-shot charge, which the first hit had. One card all the same -
	# counted once by whatever counts cards.
	if effect.repeat_toll_cost <= 0:
		return
	var standing: Array[Combatant] = _standing_after(struck, ctx)
	if standing.is_empty() or ctx.player.toll < effect.repeat_toll_cost:
		return
	if ctx.on_repeat.is_valid():
		ctx.on_repeat.call()
	ctx.spend_toll(effect.repeat_toll_cost)
	ctx.repeat_mark_bonus(standing)
	_drain(drains, _land(base + ctx.take_repeat_attack_bonus(), standing, ctx), ctx)

# How many times this effect's hit lands as it resolves: once, and once
# more for each card of its repeat_per_earlier_play_tag played earlier
# this turn (EffectContext.earlier_plays_tagged()) - before Second
# Swing's Toll repeat, which isn't counted here. The card face reads the
# same call (CardView's {hits}).
static func hit_count(effect: CardEffect, ctx: EffectContext) -> int:
	if effect == null or effect.repeat_per_earlier_play_tag == &"" or ctx == null:
		return 1
	return 1 + maxi(ctx.earlier_plays_tagged(effect.repeat_per_earlier_play_tag), 0)

# What hits on `struck` left to hit again: a mound broken under its
# target is the enemy it was over, or nothing (EffectContext.landing_
# for()); the dead are left out.
func _standing_after(struck: Array[Combatant], ctx: EffectContext) -> Array[Combatant]:
	var standing: Array[Combatant] = []
	for target in struck:
		var enemy: Combatant = ctx.landing_for(target)
		if enemy != null and enemy.hp > 0 and not standing.has(enemy):
			standing.append(enemy)
	return standing

# A Draining hit (CardEffect.drains - Claw Back; drain_on_condition -
# Gnaw) heals what it took.
func _drain(drains: bool, taken: int, ctx: EffectContext) -> void:
	if drains:
		ctx.heal(taken)

# One hit of `blow` on each of `targets`. Returns the HP the hits took,
# less what Grace reclaimed from them - what a Drain on them heals.
func _land(blow: int, targets: Array[Combatant], ctx: EffectContext) -> int:
	var taken: int = 0
	for enemy in targets:
		# A mound gone since the card began - broken, or its row gone with
		# the enemy coming up under another - takes nothing.
		if enemy.mound_owner != null and not EnemyTurn.mound_standing(enemy):
			continue
		# A mark on this enemy (Come Due) adds to the blow against it
		# alone, once per card and again for a repeated hit - so it's per
		# target, and like the attack bonus it goes in before the
		# modifiers.
		var hp_before: int = enemy.hp
		var full_blow: int = blow + ctx.take_mark_bonus(enemy)
		ctx.attack_card_extra_this_card += Status.attack_card_extra(full_blow, ctx.player.statuses)
		var result := DamagePipeline.resolve(landed(full_blow, ctx.player, enemy), enemy)
		# A broken mound is no kill.
		if enemy.hp <= 0 and enemy.mound_owner == null:
			ctx.killed_this_card = true
		ctx.report_block(enemy, result)
		if result["damage_to_hp"] > 0:
			ctx.report_damage(enemy, result["damage_to_hp"], "card")
			var reclaimed: int = ctx.grace_reclaim(result["damage_to_hp"])
			ctx.record_hit(hp_before - enemy.hp, reclaimed)
			taken += maxi(hp_before - enemy.hp - reclaimed, 0)
	return taken

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
