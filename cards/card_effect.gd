extends Resource
class_name CardEffect

# Nineteen effect types, ported from the old project's card_effect.gd -
# resolved by battle/rules/effect_resolver.gd via a per-type script under
# battle/rules/effects/, not a match/switch. TOLL_THRESHOLD_DAMAGE,
# FIRST_CARD_DAMAGE, and DAMAGE_ALL are kept as names (old authoring
# habit, and any old .tres data that used them stays readable) but the
# resolver maps all three to the SAME script as DAMAGE - see
# damage_effect.gd, which reads `condition`/`target_scope` below to
# reproduce what used to be three separate types. Order matches the old
# enum exactly - nothing here reorders an existing value's own integer.
enum EffectType {
	DAMAGE, BLOCK, SELF_DAMAGE, DRAW, HEAL, TOLL_DAMAGE, STUN, TOLL_BLOCK,
	TOLL_RETALIATE, SELF_DAMAGE_TOLL, TOLL_THRESHOLD_DAMAGE, DAMAGE_ALL,
	APPLY_STATUS, FIRST_CARD_DAMAGE, TOLL_FRACTION_DAMAGE_ALL,
	UNDAMAGED_BLOCK, GAIN_ENERGY, ABSORB, APPLY_STATUS_TO_TARGET,
}

# When the effect resolves. Two modes, chosen by `alt_value` below rather
# than by a second enum:
#   alt_value == 0 - GATE. Condition false and the effect doesn't resolve
#                    at all. The original shape, and still what every
#                    conditional effect except a replace uses.
#   alt_value != 0 - REPLACE. Condition false uses `value`, true uses
#                    `alt_value`; something always resolves. This is the
#                    old project's TOLL_THRESHOLD_DAMAGE/FIRST_CARD_DAMAGE
#                    shape, which its .tres files carried in a field
#                    called threshold_value.
# The second mode was predicted here as future work before it existed;
# `alt_value` is that second value field, added for Left Hand (cards/
# neutral/left_hand.tres) and read by damage_effect.gd ONLY - no other
# resolver consults it, so every other type is gate-or-nothing as before.
enum Condition { NONE, TOLL_AT_LEAST, HP_BELOW_PERCENT, FIRST_CARD_THIS_TURN }

# Which combatant(s) an effect resolves against - lets DAMAGE_ALL collapse
# into plain DAMAGE (target_scope = ALL_ENEMIES) instead of needing its
# own resolver script. SELF is reserved for a future effect that needs to
# choose between hitting the chosen target and hitting its own caster;
# nothing reads it yet.
enum TargetScope { TARGET, ALL_ENEMIES, SELF }

@export var effect_type: EffectType = EffectType.DAMAGE
@export var value: int = 0

@export var condition: Condition = Condition.NONE
@export var condition_value: float = 0.0
# TOLL_AT_LEAST reads this as an int Toll threshold; HP_BELOW_PERCENT
# reads it as a percent (0-100) of max HP. Unused when condition is NONE.

@export var alt_value: int = 0
# The number used INSTEAD of `value` when `condition` holds - see the
# Condition enum's own doc for the gate/replace split this selects, and
# damage_effect.gd for the only resolver that reads it. 0 means "no
# replacement authored", which is also why a replace that wants to deal
# literally 0 can't be expressed: deal-nothing is a gate, not a replace.
# One resolution either way, so the value goes through the damage
# pipeline once - NOT two stacked effects, which would be blocked twice.

@export var target_scope: TargetScope = TargetScope.TARGET

@export var toll_cost: int = 0
# Fixed Toll spent by TOLL_BLOCK/TOLL_RETALIATE. Unused by every other type.

@export var status_data: StatusData = null
# Read by TOLL_RETALIATE, APPLY_STATUS, APPLY_STATUS_TO_TARGET. Unused by
# every other type.

@export var toll_gain: int = 0
# The flat total Toll SELF_DAMAGE_TOLL guarantees, topping up whatever the
# floor-clamped HP loss already accrued on its own. Unused by every other
# type.

@export_range(0.0, 1.0, 0.01) var toll_fraction: float = 1.0
# Portion of current Toll TOLL_FRACTION_DAMAGE_ALL spends. Unused by every
# other type.

@export var bonus_value: int = 0
# Extra block UNDAMAGED_BLOCK ADDS on top of `value` when its condition is
# met. Unused by every other type.

@export_multiline var combat_message: String = ""
# Shown when a STUN resolves. Unused by every other type - and STUN
# itself has no real caller yet this pass (see stun_effect.gd: interrupts
# and chain payoffs are both out of scope).
