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

enum StackRule { REFRESH_DURATION, ADD_MAGNITUDE, REFRESH_AND_ADD, IGNORE, RESET, ADD_CHARGES }
# What happens when this exact StatusData is applied again while already
# active on the same combatant - see Status.apply_stack(). REFRESH_
# DURATION resets the clock only; ADD_MAGNITUDE/REFRESH_AND_ADD also grow
# magnitude; IGNORE does nothing at all to magnitude or duration (the
# existing instance just keeps running), though stack_count still climbs
# for those four. RESET puts the status back as if freshly applied -
# default magnitude, duration and charges, one stack - a refresh, never a
# pile-up (Come Due, No Further armed). ADD_CHARGES adds default_charges
# to the charges still waiting and leaves the rest alone - each copy
# covers one more use (Collateral). Appended: an inserted value would
# rewrite every .tres that stores one of these as an integer.

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
# Rules text, not flavor - one short sentence in card voice saying what
# this status does, shown when its holder's battle readout is hovered
# (Status.describe()). A template: these tokens are filled from the live
# Status, so the numbers move as it's spent -
#   {charges}  charges left              {turns}  turns left (a countdown's)
#   {stacks}   stack_count               {percent}  |magnitude| (a MULTIPLY %)
#   {mark}     attack_bonus_against_holder
#   {bonus}    attack_damage_bonus × stacks
#   {bonus_each} attack_damage_bonus, one stack's worth
#   {max}      attack_damage_bonus × max_stacks (the bonus at the cap)
#   {damage}   countdown_damage          {grant}  grants_on_critical's charges
#   {progress} a counter's losses so far  {count}  self_loss_trigger_count
#   {drain}    self_loss_trigger_drain × stacks
#   {hp}       replacement_hp_cost       {min_cost} replaces_cost_at_least
#   {alone_bonus} grants_when_alone's attack_damage_bonus (what it turns into)
#   {reduction} next_card_cost_reduction × stacks
#   {survive_hp} survive_hp() for the holder (only with one - describe(holder))
#   {s}        "s" unless the count token before it is 1 ("Attack{s}")
# An unknown token is left standing. "It" is the enemy holding it, "you"
# the player.

@export var category: Category = Category.INFORMATIONAL
@export var default_magnitude: int = 0
@export var default_duration_turns: int = 1
# How many times this status can be spent before it's gone - counted on
# Status.charges, apart from magnitude (which a MODIFIER needs for its
# own number). 0 = not a charge status. What spends one is the status's
# own rule: an Attack on its holder (attack_bonus_against_holder - Come
# Due), or an enemy attack against its holder (consumed_by_attack_against,
# on a status that has charges). Shown as "Name ×N" down to ×1 (Status.
# label()).
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
# The most stacks it holds: a copy applied at the cap changes nothing
# else about the count (Status.apply_stack()). Roused stops at 4. 0 = no
# cap.
@export var max_stacks: int = 0

# Which Wanderer battle clip to hold (LOOP_LINEAR) for as long as this
# status is active on the player - empty (default) means no held pose.
# Generic, not Braced-specific: Wanderer._on_status_changed() just looks
# for the first active status carrying one, so a future status gets a
# pose for free by setting this, no new wiring needed.
@export var battle_animation: StringName = &""

# Extra damage per stack each Attack card deals while this is up (Dying
# Light). Once per Attack card, like a stance's bonus - not a MODIFIER,
# which would land on every damage the player deals (a Toll spend
# included). Summed with the stance's by AttackBonus. On an enemy
# (Hungry) it is per hit instead: added to every hit of its ATTACK
# intents, before any modifier (EnemyTurn.hit_amount()). 0 = none.
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

# Its holder's next turn is skipped (Deny's Denied): whatever move is
# queued doesn't happen and the pattern moves on as if it had - lost, not
# delayed - and the turn still counts (escalation keeps its clock). Its
# statuses still tick first, so a countdown can still go off. Removed by
# that turn, whatever else it does (a pain turn on the same turn spends
# it too) - it never carries over (EnemyTurn.take_turn()). Pair it with
# DURATION_UNTIL_TRIGGERED and StackRule.IGNORE. A holder can't be
# targeted by another card applying it (BattleController).
@export var skips_next_turn: bool = false

# Extra hits its holder - an enemy - lands with every multi-hit ATTACK
# (EnemyIntent.hits above 1) while it's up; a single blow stays single
# (EnemyTurn.hit_count()). Off the rock: the Greyshelf's Tail Lash strikes
# 4 times. 0 = none.
@export var bonus_hits: int = 0

# Energy its holder gains at the start of each of their turns, on top of
# the refill, if they are Critical at that moment (Dying Light) - judged
# as the Energy refills (Combatant.turn_start_energy()); entering Critical
# later in the turn gives nothing until the next one starts. 0 = none.
@export var turn_start_energy_while_critical: int = 0

# While its holder has it, a card that applies it can't be played - the
# face fades like an unplayable one (EffectResolver.card_blocked()) - so
# it never stacks: one at a time (Dying Light).
@export var blocks_reapply_while_held: bool = false

# The mirror of consumed_by_own_attack, for a status on the one being
# attacked: spent once an enemy ATTACK against its holder has resolved -
# after every hit of it, so a status that softens that attack (No Further)
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

# A status that waits for its holder - an enemy - to be the last of its
# pack (Fed): the moment no packmate is left living in the fight
# (Combatant.pack_alone, EnemyTurn.leave_pack()) it is removed and this
# status applied in its place - once, a pack doesn't regroup. Null = none.
@export var grants_when_alone: StatusData = null

# A status that waits for its holder's next turn (Ransom): at the start of
# the player's turn, after the ticks (BattleController._start_player_
# turn(), Status.resolve_turn_start_triggers()), it is removed and this
# status applied in its place. Pair it with DURATION_UNTIL_REMOVED so no
# tick takes it first. Null = none.
@export var grants_on_turn_start: StatusData = null

# Gone the moment its holder's turn ends (BattleController.end_turn(),
# Status.remove_at_turn_end()) - "this turn" means the player's turn, not
# the enemy's that follows. Pair it with DURATION_UNTIL_REMOVED so no
# tick takes it first.
@export var ends_at_turn_end: bool = false

# While this is up, every Attack card the player plays Drains: after its
# last effect it heals ransom_heal_fraction of the HP its hits took from
# enemies, rounded down - not a killing blow's overkill, and less
# whatever Grace already reclaimed from each hit (EffectContext.record_
# hit(), EffectResolver.resolve_card()). No cap: what the Attack lands
# sets the heal.
@export var attacks_drain: bool = false
# The share of that HP an Attack heals while attacks_drain is up (Ransom:
# half). Read with attacks_drain only.
@export_range(0.0, 1.0, 0.05) var ransom_heal_fraction: float = 0.5

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
# HP while they're Critical leaves them at survive_hp() instead - raised
# to it from below - and spends one of this status's charges, each copy
# played adding one (EnemyTurn.take_turn(), Status.refuse_lethal()).
# Self-inflicted loss never reaches it - that goes through
# DamagePipeline.apply_bypass(), which doesn't ask.
@export var prevents_lethal_while_critical: bool = false
# Where a lethal guard leaves the player, as a fraction of max HP -
# rounded down, at least 1, and always still Critical (survive_hp()).
# Read only with prevents_lethal_while_critical.
@export_range(0.0, 1.0, 0.01) var survive_fraction: float = 0.15

# A counter on its holder's own HP losses (The Return): every loss to
# their own effect - one per loss, however much HP it took - advances
# Status.progress, and the one that reaches this goes off: Drain
# self_loss_trigger_drain × stacks from every enemy, and the count starts
# again. Counted in Combatant.gain_self_loss_toll(), so an enemy's hit
# never counts. Shown as "Name N/M". 0 = not a counter.
@export var self_loss_trigger_count: int = 0
# What each stack Drains when the counter above goes off - one Drain of
# the stacks' total, not one per stack (DrainEffect.drain()).
@export var self_loss_trigger_drain: int = 0


# A cost replacement (Collateral): while a charge is waiting, the next
# card whose Energy cost - after every other modifier, House Key's free
# card included - is at least this costs 0 Energy and replacement_hp_cost
# HP instead, and spends a charge. Cheaper cards pass it by and leave the
# charge. The HP is paid as the card resolves, before its effects, the
# way a stance's per-Attack cost is (EffectResolver.resolve_card()); the
# charge is spent when the play commits (BattleController._resolve_
# play()). Read through Combatant.energy_cost()/replaced_cost_hp(). 0 =
# not a cost replacement.
@export var replaces_cost_at_least: int = 0
@export var replacement_hp_cost: int = 0

# A cost reduction (Leverage): the next card played costs this much less
# Energy per stack, never below 0 - after House Key's free card, before a
# cost replacement judges what's left (Combatant.energy_cost()). The next
# card costing at least 1 Energy spends it, and the whole status goes; a
# 0-cost card passes it by (Combatant.takes_next_card_discount()), and a
# card that applies this same status adds to it instead, so two in a row
# reduce one card by both (Status.spend_cost_reduction(), at the play's
# commit in BattleController._resolve_play()). Stacks count through stack_count -
# pair it with StackRule.IGNORE and DURATION_UNTIL_REMOVED. 0 = none.
@export var next_card_cost_reduction: int = 0

# The HP a lethal guard leaves its holder at, for their max HP and
# Critical line: survive_fraction of max HP, rounded down, at least 1 -
# and if that would sit above the Critical line, the highest HP still on
# it (70 max HP: 10; a fraction past the line at 70: 21). The epsilon
# keeps a product that should be whole (0.29 x 100) off the floor below.
func survive_hp(max_hp: int, critical_fraction: float) -> int:
	var hp: int = maxi(floori(max_hp * survive_fraction + 0.0001), 1)
	if not Combatant.critical_at(hp, max_hp, critical_fraction):
		hp = maxi(floori(max_hp * critical_fraction + 0.0001), 1)
	return hp
