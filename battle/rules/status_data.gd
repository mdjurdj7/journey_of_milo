extends Resource
class_name StatusData

# The STATIC definition of a status - a plain data container, define once
# as a .tres. The RUNTIME half (current magnitude, turns remaining, how
# many times it's been reapplied) lives in Status instead - see status.gd.

enum Category { TICK, MODIFIER, INFORMATIONAL }
# TICK: deals `magnitude` un-blockable damage to its own holder at a turn
# boundary (see status.gd's tick_all()). MODIFIER: adjusts incoming or
# outgoing damage by magnitude (see modifier_target/modifier_operation
# below and status.gd's apply_modifiers()). INFORMATIONAL: no mechanical
# effect of its own - displays, ticks, expires.

enum ModifierTarget { INCOMING_DAMAGE, OUTGOING_DAMAGE }
enum ModifierOperation { ADD, MULTIPLY }
# Only meaningful when category == MODIFIER. ADD adds magnitude directly
# to the running damage total; MULTIPLY treats magnitude as a PERCENTAGE
# (-50 means "half", 50 means "+50%") rather than a raw multiplier.

enum StackRule { REFRESH_DURATION, ADD_MAGNITUDE, REFRESH_AND_ADD, IGNORE }
# What happens when this exact StatusData is applied again while already
# active on the same combatant - see Status.apply_stack(). REFRESH_
# DURATION resets the clock only; ADD_MAGNITUDE/REFRESH_AND_ADD also grow
# magnitude; IGNORE does nothing at all to magnitude or duration (the
# existing instance just keeps running), though stack_count still climbs
# regardless of which rule is chosen.

const DURATION_UNTIL_REMOVED := -1
# A status with this exact duration never expires on its own - something
# else (a cleanse, defeat, end of combat) has to remove it instead.
const DURATION_UNTIL_TRIGGERED := -2
# A second "doesn't expire via the turn counter" sentinel, distinct from
# DURATION_UNTIL_REMOVED - this one is for a status waiting to proc once,
# expected to be removed synchronously the instant it fires (see
# clears_on_trigger below for the actual mechanism that does that).

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
# Rules text, not flavor - what this status actually does, including its
# consumption rule where relevant (see braced.tres for the wording this
# was added for: consumed by the next hit whether or not it deals damage).

@export var category: Category = Category.INFORMATIONAL
@export var default_magnitude: int = 0
@export var default_duration_turns: int = 1
@export var clears_on_trigger: bool = false
# Made REAL this pass (the old project's own version was decorative - see
# Phase 1 report's flagged items): status.gd's consume_triggered() removes
# every status with this flag set, unconditionally, whenever a trigger
# fires - a generic path, not a hardcoded pair of named statuses. The one
# trigger that exists today is an enemy attack resolving against the
# player (see battle/rules/enemy_turn.gd).

@export var modifier_target: ModifierTarget = ModifierTarget.INCOMING_DAMAGE
@export var modifier_operation: ModifierOperation = ModifierOperation.ADD
@export var stack_rule: StackRule = StackRule.REFRESH_DURATION
