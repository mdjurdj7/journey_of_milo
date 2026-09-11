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
}

var _cache: Dictionary = {}

func resolve_card(card: CardData, ctx: EffectContext) -> void:
	for effect in card.effects:
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
			return ctx.cards_played_this_turn == 0
	return true
