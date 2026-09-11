extends RefCounted
class_name ActiveStatus
# One status currently affecting a combatant - the RUNTIME half of a
# StatusEffectData (the STATIC definition, see its own header for the
# fuller split). Same idea as EnemyIntent (static, authored) vs. Battle's
# own EnemyCombatant (mutable, this specific fight): a StatusEffectData
# resource never changes, so two combatants can each independently hold
# "the same" status at different magnitudes/durations without fighting
# over one shared Resource's fields - the same reasoning encounter_
# data.gd's own comment already gives for two EnemyCombatants safely
# sharing one EnemyData.
#
# RefCounted, not Resource - never saved, never hand-authored, just a
# throwaway object that lives for as long as this status is active and
# is garbage-collected once nothing references it, same shape LootEntry
# already uses for the same reason.

var data: StatusEffectData
var magnitude: int
var turns_remaining: int

var stack_count: int = 1
# How many times THIS status has been applied while already active, plus
# the original application (starts at 1, not 0 - one application already
# happened by the time this instance exists at all). Incremented
# unconditionally in apply_stack() below, regardless of stack_rule -
# orthogonal to whether magnitude/duration actually change on reapply
# (Selfeater's own status_data.gd:attack_hp_drain_* fields are the first
# reader: StackRule.IGNORE keeps magnitude flat while this still counts
# how many copies have been played, since the drain curve and the damage
# bonus are deliberately independent numbers - see that field's own doc).
# First real use: Selfeater (2026-08-28) - no status before it needed
# anything beyond magnitude/duration, so this didn't exist yet either.

func _init(status_data: StatusEffectData) -> void:
	data = status_data
	magnitude = status_data.default_magnitude
	turns_remaining = status_data.default_duration_turns

# Called once per turn boundary this status is still active (see battle.
# gd's _tick_statuses()) - counts down, except StatusEffectData.DURATION_
# UNTIL_REMOVED or DURATION_UNTIL_TRIGGERED, neither of which expires on
# its own no matter how many turns pass (see their own docs for how the
# two differ in who removes them instead).
func tick_duration() -> void:
	if turns_remaining != StatusEffectData.DURATION_UNTIL_REMOVED and turns_remaining != StatusEffectData.DURATION_UNTIL_TRIGGERED:
		turns_remaining -= 1

func is_expired() -> bool:
	return turns_remaining == 0

# Reapplying the SAME status (same StatusEffectData) while this instance
# is already active - see data.stack_rule for which of these three
# happens. Never both refreshes duration AND drops the running magnitude,
# never adds magnitude without ALSO refreshing if the rule says to do
# both - see StatusEffectData.StackRule.
func apply_stack() -> void:
	stack_count += 1
	match data.stack_rule:
		StatusEffectData.StackRule.REFRESH_DURATION:
			turns_remaining = data.default_duration_turns
		StatusEffectData.StackRule.ADD_MAGNITUDE:
			magnitude += data.default_magnitude
		StatusEffectData.StackRule.REFRESH_AND_ADD:
			turns_remaining = data.default_duration_turns
			magnitude += data.default_magnitude
		StatusEffectData.StackRule.IGNORE:
			pass # True non-stackable - the running instance is untouched.
