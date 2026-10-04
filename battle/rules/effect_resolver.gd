extends RefCounted
class_name EffectResolver

# Registry, not a switch: each CardEffect.EffectType maps to a small
# script under battle/rules/effects/ implementing resolve(effect, ctx).
# Three old type names collapse onto DAMAGE's own script (see damage_
# effect.gd) - they're kept as distinct enum values so old-style
# authoring still reads correctly, but every one of them resolves
# identically to a plain DAMAGE effect with the right condition/
# target_scope set.
const EFFECT_SCRIPT_PATHS: Dictionary = {
	CardEffect.EffectType.DAMAGE: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.FIRST_CARD_DAMAGE: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.DAMAGE_ALL: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.BLOCK: "res://battle/rules/effects/block_effect.gd",
	CardEffect.EffectType.SELF_DAMAGE: "res://battle/rules/effects/self_damage_effect.gd",
	CardEffect.EffectType.DRAW: "res://battle/rules/effects/draw_effect.gd",
	CardEffect.EffectType.HEAL: "res://battle/rules/effects/heal_effect.gd",
	CardEffect.EffectType.TOLL_DAMAGE: "res://battle/rules/effects/toll_damage_effect.gd",
	CardEffect.EffectType.STUN: "res://battle/rules/effects/stun_effect.gd",
	CardEffect.EffectType.TOLL_BLOCK: "res://battle/rules/effects/toll_block_effect.gd",
	CardEffect.EffectType.TOLL_RETALIATE: "res://battle/rules/effects/toll_retaliate_effect.gd",
	CardEffect.EffectType.SELF_DAMAGE_TOLL: "res://battle/rules/effects/self_damage_toll_effect.gd",
	CardEffect.EffectType.APPLY_STATUS: "res://battle/rules/effects/apply_status_effect.gd",
	CardEffect.EffectType.TOLL_FRACTION_DAMAGE_ALL: "res://battle/rules/effects/toll_fraction_damage_all_effect.gd",
	CardEffect.EffectType.UNDAMAGED_BLOCK: "res://battle/rules/effects/undamaged_block_effect.gd",
	CardEffect.EffectType.GAIN_ENERGY: "res://battle/rules/effects/gain_energy_effect.gd",
	CardEffect.EffectType.ABSORB: "res://battle/rules/effects/absorb_effect.gd",
	CardEffect.EffectType.APPLY_STATUS_TO_TARGET: "res://battle/rules/effects/apply_status_to_target_effect.gd",
	CardEffect.EffectType.APPLY_STANCE: "res://battle/rules/effects/apply_stance_effect.gd",
	CardEffect.EffectType.TOLL_HEAL: "res://battle/rules/effects/toll_heal_effect.gd",
	CardEffect.EffectType.SPEND_TOLL: "res://battle/rules/effects/spend_toll_effect.gd",
	CardEffect.EffectType.DRAIN: "res://battle/rules/effects/drain_effect.gd",
	CardEffect.EffectType.SET_ASIDE: "res://battle/rules/effects/set_aside_effect.gd",
	CardEffect.EffectType.CONSUME: "res://battle/rules/effects/consume_effect.gd",
}

var _cache: Dictionary = {}

# The stance's price is paid BEFORE the card's own effects: an Attack pays
# it as part of being played. The bonus is NOT fixed here - the card's
# first damage effect takes it as it lands (EffectContext.take_attack_
# bonus()), so Critical is judged after everything the card paid first.
# A card that isn't an ATTACK pays and gets nothing, which is how a stance
# card can be played while a stance is already up without charging for
# itself. Nor does an Attack with nothing it can hit - every enemy buried
# (ctx.enemies is only the hittable ones): the stance's HP isn't paid
# into immunity.
func resolve_card(card: CardData, ctx: EffectContext) -> void:
	# Per card, not per effect: "if this kills" means this CARD's own
	# damage, so a kill from the card before must not still be standing.
	ctx.killed_this_card = false
	ctx.card_is_attack = card.card_type == CardData.CardType.ATTACK
	ctx.attack_bonus_taken = false
	ctx.mark_bonus_paid.clear()
	ctx.toll_spent_this_card = false
	ctx.hp_dealt_this_card = 0
	# A cost replacement's HP (Collateral), first of all - it is this
	# card's price. A price that kills ends the card: none of its effects
	# resolve, and the fight ends as a defeat.
	if ctx.replaced_cost_hp > 0:
		ctx.pay_upfront_hp_cost(ctx.replaced_cost_hp)
		ctx.resolve_pending_drain()
		if ctx.player.hp <= 0:
			return
	if ctx.card_is_attack and ctx.player.stance != null and not ctx.enemies.is_empty():
		ctx.pay_upfront_hp_cost(Stance.attack_hp_loss(ctx.player.stance))
		# The price can be the loss that sets off a counter (The Return):
		# its Drain lands now, before the Attack it was paid for.
		ctx.resolve_pending_drain()
	for effect in card.effects:
		# The gate lives HERE, not in each resolver - it used to be checked
		# only inside damage_effect.gd, so a condition on any other effect
		# type was silently ignored (With Regards' energy paid out whether
		# or not the blow killed). A REPLACE or an ADD still goes through:
		# its condition chooses a number rather than whether to resolve at
		# all - CardBonus tells the three apart and hands each resolver
		# the number (CardBonus.resolved_value()).
		if not CardBonus.should_resolve(effect, ctx):
			continue
		var resolver: Object = _get_resolver(effect.effect_type)
		if resolver != null:
			resolver.resolve(effect, ctx)
		# Straight after the loss that set a counter off, before the next
		# effect - Blood Arc's Drain lands before its own sweep.
		ctx.resolve_pending_drain()
	# After the whole card, once however much it spent: Toll spent hurries
	# every countdown that listens for it (Sentence), and one that reaches
	# 0 goes off now, in the player's turn - reported as damage, never as
	# the card's own blow.
	if ctx.toll_spent_this_card:
		for enemy in ctx.enemies:
			Status.advance_on_toll_spend(enemy)
			var taken: int = Status.resolve_countdowns(enemy)
			if taken > 0:
				ctx.report_damage(enemy, taken, "status")
	# After the card's last effect, once: an Attack played while its
	# Attacks Drain (Ransom) heals what its own hits took, net of Grace
	# (EffectContext.record_hit()) - all of them summed for an all-enemies
	# Attack. Never a countdown going off or a counter's Drain: neither is
	# the Attack's blow. Before the Critical triggers below, so a heal that
	# lifts the player out of Critical is seen there.
	if ctx.card_is_attack and Status.attacks_drain(ctx.player.statuses):
		ctx.heal(ctx.hp_dealt_this_card)
	# After the whole card: its own HP cost (self-damage, the stance's
	# price) may have made the player Critical, and a status waiting for
	# that (No Further) gives way now - as does one this card just applied
	# while they were already there.
	Status.resolve_critical_triggers(ctx.player)

# Whether the rules forbid playing this card right now, whatever its
# energy: it spends a fixed Toll the player doesn't hold (SPEND_TOLL - Come
# Due). Read by BattleController.
# request_play() and by the hand, which fades the card - so a copy that
# can't be paid for shows it rather than being taken and doing nothing.
# Whether `card` may land on `combatant`: living and not buried, and - for
# a card that skips its target's turn (Deny) - not one already holding
# that status, since it doesn't stack. BattleController's targeting and
# the hand's fade both ask here.
static func can_target(card: CardData, combatant: Combatant) -> bool:
	if combatant == null or combatant.hp <= 0 or combatant.buried:
		return false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS_TO_TARGET and effect.status_data != null and effect.status_data.skips_next_turn:
			if Status.skip_turn_status(combatant.statuses) != null:
				return false
	return true

# Whether any of `enemies` is one `card` may land on.
static func has_target(card: CardData, enemies: Array[Combatant]) -> bool:
	for combatant in enemies:
		if can_target(card, combatant):
			return true
	return false

# Also a card applying a status the player already holds that allows one
# at a time (StatusData.blocks_reapply_while_held - Dying Light).
static func card_blocked(card: CardData, player: Combatant) -> bool:
	if card == null or player == null:
		return false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.SPEND_TOLL and player.toll < effect.toll_cost:
			return true
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS and effect.status_data != null and effect.status_data.blocks_reapply_while_held and Status.find_in(player.statuses, effect.status_data) != null:
			return true
	return false

func _get_resolver(effect_type: CardEffect.EffectType) -> Object:
	if _cache.has(effect_type):
		return _cache[effect_type]
	var path: String = EFFECT_SCRIPT_PATHS.get(effect_type, "")
	if path == "":
		push_error("EffectResolver: no resolver registered for effect type %d" % effect_type)
		return null
	var instance: Object = load(path).new()
	_cache[effect_type] = instance
	return instance

static func condition_met(effect: CardEffect, ctx: EffectContext) -> bool:
	match effect.condition:
		CardEffect.Condition.NONE:
			return true
		CardEffect.Condition.TOLL_AT_LEAST:
			return ctx.player.toll >= int(effect.condition_value)
		CardEffect.Condition.HP_BELOW_PERCENT:
			return ctx.player.hp < ctx.player.max_hp * (effect.condition_value / 100.0)
		CardEffect.Condition.FIRST_CARD_THIS_TURN:
			return ctx.cards_played_before_this == 0
		CardEffect.Condition.TARGET_KILLED:
			return ctx.killed_this_card
		CardEffect.Condition.HAS_GRACE:
			return ctx.player.grace > 0
		CardEffect.Condition.UNDAMAGED_LAST_TURN:
			return not ctx.player.took_damage_last_turn
		CardEffect.Condition.CRITICAL:
			return ctx.player.is_critical_at(ctx.player.hp - ctx.preview_hp_cost)
	return true
