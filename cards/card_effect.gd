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
	APPLY_STANCE, TOLL_HEAL,
}

# When the effect resolves, or with what number. Three modes, told apart
# from the fields below by CardBonus.mode() and NOWHERE else:
#   GATE    - alt_value and bonus_value both 0: condition false and the
#             effect doesn't resolve at all (With Regards' energy).
#   REPLACE - alt_value set: false uses `value`, true `alt_value`;
#             something always resolves (Left Hand, Reprisal). The old
#             project's TOLL_THRESHOLD_DAMAGE/FIRST_CARD_DAMAGE shape,
#             which its .tres files carried as threshold_value.
#   ADD     - bonus_value set: true adds bonus_value on top of `value`;
#             something always resolves (Untouched).
# The number an effect lands for is CardBonus.resolved_value(); the card
# face prints the same call, so what it says is what the rules pay.
# UNDAMAGED_LAST_TURN is appended last: an inserted value would rewrite
# every .tres that stores one of these as an integer.
enum Condition { NONE, TOLL_AT_LEAST, HP_BELOW_PERCENT, FIRST_CARD_THIS_TURN, TARGET_KILLED, HAS_GRACE, UNDAMAGED_LAST_TURN }

# Which combatant(s) an effect resolves against - lets DAMAGE_ALL collapse
# into plain DAMAGE (target_scope = ALL_ENEMIES) instead of needing its
# own resolver script. SELF is reserved for a future effect that needs to
# choose between hitting the chosen target and hitting its own caster;
# nothing reads it yet.
enum TargetScope { TARGET, ALL_ENEMIES, SELF }

# EFFECT ORDER IS LOAD-BEARING. Effects resolve top to bottom (see
# EffectResolver.resolve_card()), and TARGET_KILLED reads what an EARLIER
# effect on this same card did - so With Regards' GAIN_ENERGY has to sit
# after its DAMAGE or it will never fire. Every other condition reads
# state that exists before the card is played and doesn't care.
@export var effect_type: EffectType = EffectType.DAMAGE
@export var value: int = 0

@export var condition: Condition = Condition.NONE
@export var condition_value: float = 0.0
# TOLL_AT_LEAST reads this as an int Toll threshold; HP_BELOW_PERCENT
# reads it as a percent (0-100) of max HP. Unused when condition is NONE.

@export var alt_value: int = 0
# The number used INSTEAD of `value` when `condition` holds - the REPLACE
# mode of the Condition enum's own doc, read through CardBonus. 0 means
# "no replacement authored", which is also why a replace that wants to
# deal literally 0 can't be expressed: deal-nothing is a gate, not a
# replace. One resolution either way, so the value goes through the
# damage pipeline once - NOT two stacked effects, which would be blocked
# twice.

@export var target_scope: TargetScope = TargetScope.TARGET

@export var toll_cost: int = 0
# Fixed Toll spent by TOLL_BLOCK/TOLL_RETALIATE. Unused by every other type.

@export var stance_data: StanceData = null
# Read by APPLY_STANCE only. The stance a STANCE card takes - or deepens,
# when it is the one already held.

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
# The amount ADDED on top of `value` when `condition` holds - the ADD
# mode of the Condition enum's own doc, read through CardBonus. Authored
# on UNDAMAGED_BLOCK (Untouched) today.

@export_multiline var combat_message: String = ""
# Shown when a STUN resolves. Unused by every other type - and STUN
# itself has no real caller yet this pass (see stun_effect.gd: interrupts
# and chain payoffs are both out of scope).
