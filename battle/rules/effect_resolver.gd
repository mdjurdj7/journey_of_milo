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
}

var _cache: Dictionary = {}

# The stance pass runs BEFORE the card's own effects: an Attack pays the
# active stance's price as part of being played, and the bonus it buys has
# to be on ctx before any damage effect reads it. A card that isn't an
# ATTACK leaves both at nothing, which is how a stance card can be played
# while a stance is already up without charging for itself. Nor does an
# Attack with nothing it can hit - every enemy buried (ctx.enemies is
# only the hittable ones): the stance's HP isn't paid into immunity.
func resolve_card(card: CardData, ctx: EffectContext) -> void:
	# Per card, not per effect: "if this kills" means this CARD's own
	# damage, so a kill from the card before must not still be standing.
	ctx.killed_this_card = false
	ctx.stance_attack_bonus = 0
	if card.card_type == CardData.CardType.ATTACK and ctx.player.stance != null and not ctx.enemies.is_empty():
		ctx.stance_attack_bonus = Stance.attack_bonus(ctx.player.stance)
		ctx.pay_stance_attack_cost(Stance.attack_hp_loss(ctx.player.stance))
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
	return true
