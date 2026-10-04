extends RefCounted
class_name DrainEffect

# Drain X: deal X to each target, then heal up to X - once, however many
# targets it hit: the heal is the HP the targets actually lost, summed,
# and never more than X. Not an Attack and not a card's blow - no attack
# bonus, no mark (Come Due), no Attack charge, no Grace reclaimed; only
# what softens any damage (the modifiers, block, absorb). Its heal goes
# through EffectContext.heal(), so it accrues no Toll and opens no Grace.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var targets: Array[Combatant] = []
	if effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES:
		targets = ctx.enemies
	elif ctx.target != null:
		targets = [ctx.target]
	if drain(effect.value, targets, ctx):
		ctx.killed_this_card = true

# The Drain itself, shared by the card effect above and a counter going
# off (EffectContext.resolve_pending_drain()). Skips a target already at
# 0. Returns whether it killed anything.
static func drain(amount: int, targets: Array[Combatant], ctx: EffectContext) -> bool:
	if amount <= 0:
		return false
	var dealt: int = 0
	var killed: bool = false
	var outgoing: int = Status.apply_modifiers(amount, ctx.player.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	for enemy in targets.duplicate():
		if enemy.hp <= 0:
			continue
		var incoming: int = Status.apply_modifiers(outgoing, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		var hp_before: int = enemy.hp
		var result := DamagePipeline.resolve(incoming, enemy)
		var damage_to_hp: int = result["damage_to_hp"]
		# The heal counts HP the enemy actually lost - not a killing blow's
		# overkill, which the number shown still carries like any hit's.
		dealt += hp_before - enemy.hp
		if enemy.hp <= 0:
			killed = true
		ctx.report_block(enemy, result)
		if damage_to_hp > 0:
			ctx.report_damage(enemy, damage_to_hp, "drain")
	ctx.heal(mini(dealt, amount))
	return killed
