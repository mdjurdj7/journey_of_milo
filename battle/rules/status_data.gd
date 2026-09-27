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

enum StackRule { REFRESH_DURATION, ADD_MAGNITUDE, REFRESH_AND_ADD, IGNORE, RESET }
# What happens when this exact StatusData is applied again while already
# active on the same combatant - see Status.apply_stack(). REFRESH_
# DURATION resets the clock only; ADD_MAGNITUDE/REFRESH_AND_ADD also grow
# magnitude; IGNORE does nothing at all to magnitude or duration (the
# existing instance just keeps running), though stack_count still climbs
# for those four. RESET puts the status back as if freshly applied -
# default magnitude, duration and charges, one stack - a refresh, never a
# pile-up (Come Due, Deflection). Appended: an inserted value would rewrite every
# .tres that stores one of these as an integer.

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
# consumption rule where relevant (see braced.tres: gone once the
# enemy's next attack lands, whether or not it deals damage).

@export var category: Category = Category.INFORMATIONAL
@export var default_magnitude: int = 0
@export var default_duration_turns: int = 1
# How many times this status can be spent before it's gone - counted on
# Status.charges, apart from magnitude (which a MODIFIER needs for its
# own number). 0 = not a charge status. What spends one is the status's
# own rule: an Attack on its holder (attack_bonus_against_holder - Come
# Due), or an enemy attack against its holder (consumed_by_attack_against
# - Deflection). Shown as "Name ×N" down to ×1 (Status.label()).
@export var default_charges: int = 0
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

# Which Wanderer battle clip to hold (LOOP_LINEAR) for as long as this
# status is active on the player - empty (default) means no held pose.
# Generic, not Braced-specific: Wanderer._on_status_changed() just looks
# for the first active status carrying one, so a future status gets a
# pose for free by setting this, no new wiring needed.
@export var battle_animation: StringName = &""

# Extra damage per stack each Attack card deals while this is up (Dying
# Light). Once per Attack card, like a stance's bonus - not a MODIFIER,
# which would land on every damage the player deals (a Toll spend
# included). Summed with the stance's by AttackBonus. 0 = none.
@export var attack_damage_bonus: int = 0
# The bonus above only while the player is Critical.
@export var bonus_requires_critical: bool = false

# Extra damage each of the player's Attack cards deals to this status's
# HOLDER - an enemy - while it's up (Come Due). Once per Attack card, like
# the attack bonus (EffectContext.take_mark_bonus()), and to the holder
# alone: an all-enemies Attack pays it to this enemy, not its neighbours.
# Each Attack card that lands on the holder spends one charge (default_
# charges to start) and the status is gone at 0. Pair it with DURATION_UNTIL_REMOVED so no turn takes it
# first. 0 = none.
@export var attack_bonus_against_holder: int = 0

# Removed from its holder once the holder's own ATTACK has resolved -
# after every hit of it, so a status that softens that attack (Braced, on
# an enemy) softens all of it - whether or not any damage got through.
# An attack interrupted before it resolves, a Defend or a Burrow leave it
# in place (EnemyTurn.take_turn()). Pair it with DURATION_UNTIL_TRIGGERED
# so the turn counter never takes it first.
@export var consumed_by_own_attack: bool = false

# The mirror of consumed_by_own_attack, for a status on the one being
# attacked: spent once an enemy ATTACK against its holder has resolved -
# after every hit of it, so a status that softens that attack (Deflection)
# softens all of it - whether or not any damage got through. One charge
# per attack for a charge status, the whole status otherwise. A Defend, a
# Burrow or an interrupted attack leave it in place (EnemyTurn.take_turn()).
@export var consumed_by_attack_against: bool = false

# A status that waits for its holder to be Critical (No Further): the
# first time the holder is Critical after an action - an enemy's attack,
# a card, a turn's ticks (Status.resolve_critical_triggers()) - it is
# removed and this status applied in its place. After the action, so the
# blow that crossed the line is never softened by what it grants. Applied
# while already Critical, it gives way at once, at the end of that card.
@export var grants_on_critical: StatusData = null

# A countdown (Sentence): turns_remaining counts the turns left - ticked
# on its holder's turn like any duration - and when it reaches 0 the
# status goes off, dealing this to its holder and leaving (Status.
# resolve_countdowns()). Not an Attack and not a card's blow: no attack
# bonus, no mark, no Grace - only what softens any damage the holder takes
# (its incoming modifiers, its block). Shown as "Name N", the turns left.
# 0 = not a countdown.
@export var countdown_damage: int = 0
# A countdown that spending Toll hurries: each card that actually spends
# Toll takes one turn off it, whatever the amount (EffectContext.spend_
# toll(), Status.advance_on_toll_spend()) - and at 0 it goes off then and
# there, in the player's turn.
@export var toll_spend_advances: bool = false

# The Refuse the End rule: an ENEMY hit that would take the player to 0
# HP while they're Critical leaves them at 1 instead, and removes this
# status (EnemyTurn.take_turn()). Self-inflicted loss never reaches it -
# that goes through DamagePipeline.apply_bypass(), which doesn't ask.
@export var prevents_lethal_while_critical: bool = false

# Can be held at most once per fight: while it's active, or once it has
# fired (Combatant.spent_statuses), a card that would apply it can't be
# played (EffectResolver.card_blocked()).
@export var once_per_combat: bool = false
