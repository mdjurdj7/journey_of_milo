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

enum StackRule { REFRESH_DURATION, ADD_MAGNITUDE, REFRESH_AND_ADD, IGNORE, RESET, ADD_CHARGES, SEPARATE }
# What happens when this exact StatusData is applied again while already
# active on the same combatant - see Status.apply_stack(). REFRESH_
# DURATION resets the clock only; ADD_MAGNITUDE/REFRESH_AND_ADD also grow
# magnitude; IGNORE does nothing at all to magnitude or duration (the
# existing instance just keeps running), though stack_count still climbs
# for those four. RESET puts the status back as if freshly applied -
# default magnitude, duration and charges, one stack - a refresh, never a
# pile-up (No Further armed). SEPARATE never restacks: each application
# is an instance of its own, keeping its own clock (Sentence - several on
# one enemy each count down and go off on their own). ADD_CHARGES adds default_charges
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
#   {value}    magnitude (Garnished's total)
#   {bonus}    attack_damage_bonus × stacks
#   {bonus_each} attack_damage_bonus, one stack's worth
#   {max}      attack_damage_bonus × max_stacks (the bonus at the cap)
#   {damage}   countdown_damage          {grant}  grants_on_critical's charges
#   {progress} a counter's losses so far  {count}  self_loss_trigger_count
#   {drain}    self_loss_trigger_drain × stacks
#   {alone_bonus} grants_when_alone's attack_damage_bonus (what it turns into)
#   {reduction} next_card_cost_reduction × stacks
#   {block}    turn_start_block × stacks
#   {survive_hp} survive_hp() for the holder (only with one - describe(holder))
#   {decay}    tick_decay
#   {barbed}   barbed_damage
#   {critical_percent} raises_critical_percent
#   {share}    ransom_heal_fraction in words ("half") - or, with none, that
#              of the status it gives way to (grants_on_turn_start)
#   {s}      "s" unless the count token before it is 1 ("Attack{s}")
# An unknown token is left standing. "It" is the enemy holding it, "you"
# the player.

@export var category: Category = Category.INFORMATIONAL
@export var default_magnitude: int = 0
@export var default_duration_turns: int = 1
# How many times this status can be spent before it's gone - counted on
# Status.charges, apart from magnitude (which a MODIFIER needs for its
# own number). 0 = not a charge status. What spends one is the status's
# own rule: an enemy attack against its holder (consumed_by_attack_
# against, on a status that has charges), or the play it waits for
# (Collateral, Bent Nail). Shown as "Name ×N" down to ×1 (Status.
# label()).
@export var default_charges: int = 0
@export var clears_on_trigger: bool = false
# Spends a charge once an Attack card has finished resolving, whatever it
# dealt (Status.spend_on_attack_card(), from EffectResolver.resolve_card())
# - after every hit of that card, so a modifier with it (Bent Nail's
# outgoing doubling) holds for all of them: each target, each extra hit,
# a repeat.
@export var spent_by_attack_card: bool = false
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

# A TICK's decay (Venom): after each tick its magnitude - the stacks it
# holds, added by each application (Status.apply_amount()) - falls by
# this, and at 0 the status is gone (Status.tick_all()). 0 = the
# magnitude holds and the duration runs it out, as a TICK always has.
@export var tick_decay: int = 0
# Whether a TICK's loss is its holder's own doing - Toll and The Return's
# count (Combatant.gain_self_loss_toll()), as every tick's has been.
# False (Venom): an enemy's - no Toll, no count, and a lethal guard
# (Refuse the End) catches it as it catches an enemy hit (BattleController.
# _start_player_turn()). Neither way opens Grace: only an enemy attack
# does (EnemyTurn.open_grace()).
@export var tick_is_self_loss: bool = true
# The strike back (Coiled): while its holder - an enemy - has it, each
# Attack card the player plays against it is answered, once the card has
# resolved, with an attack of magnitude damage - an enemy hit in every way
# (EnemyTurn.counter_strike(), BattleController._counter_strikes()). An
# all-enemies Attack that hits it counts once.
@export var strikes_back_on_attack_card: bool = false
# Taunt (Inflated): while its holder - an enemy - has it, the player's
# Attack cards aimed at one enemy must aim at it - no other living enemy
# in the fight can be their target (EffectResolver.can_target()). Area
# Attacks still hit everything, and enemy-target Skills go where they
# like. The Glower's Inflated.
@export var taunts: bool = false
# What its enemy does as a move brings it, for the intent hover's line
# ("inflates", "coils" - BattleOverlay.intent_hover_lines' "brings"). Empty:
# the line falls back to its name.
@export var gained_verb: String = ""

# The inked mark its readout draws for it - a coil (Coiled), a drop
# (Venom) - or none: the label alone, as every status before them.
# Appended values only - the .tres stores the integer.
enum Mark { NONE, COIL, DROP }
@export var mark: Mark = Mark.NONE
# Shown beside its holder's HP numeral - its mark and magnitude, "Coiled
# 5" read at a glance while the player decides - instead of in the
# status row under the bar (BattleController.get_enemy_status_labels()
# leaves it out, get_enemy_hp_mark_status() hands it over). Its hover
# reveal is the row's, as ever. Enemy readouts only.
@export var shows_beside_hp: bool = false

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

# Energy owed (Come Due's Owed): its magnitude comes off its holder's
# next turn's refill, never below 0 (Combatant.turn_start_energy()), and
# it reads "Name N" in the row. Its amount is the applying effect's value,
# added on a restack (ApplyStatusEffect - Status.apply_amount()). Pair it
# with a duration of 1: the refill reads it before the turn's tick ends
# it, so it takes exactly the one turn.
@export var energy_debt: bool = false

# Removed from its holder once the holder's own ATTACK has resolved -
# after every hit of it, so a status that softens that attack softens all
# of it - whether or not any damage got through. An attack interrupted
# before it resolves, a Defend or a Burrow leave it in place (EnemyTurn.
# take_turn()). Pair it with DURATION_UNTIL_TRIGGERED so the turn counter
# never takes it first. One with an intent_mark is settled by its intent
# instead (below).
@export var consumed_by_own_attack: bool = false

# Lives on one enemy intent, not on the enemy (Braced, Garnished,
# Wrested): the card that puts it on (APPLY_STATUS_TO_TARGET, TAKE_FROM_
# ATTACK) targets an attack intent the enemy has queued - one that will
# deal damage when it resolves, not a strike back - and binds to it
# (Status.bound_intent). It holds every hit of the action it was put on -
# the first of Bereft's two; the second lands in full - is spent once the
# intent has landed, and is lost - with why - if the intent is replaced,
# cancelled (Stunned, a pain turn, an interrupt) or its enemy dies first
# (EnemyTurn.mark_loss(), take_turn()). An out-of-turn answer to a Signal
# neither reads nor spends it. The mark names it: one of each per intent
# ("brace", "garnish" - Garnish+'s as Garnish's), so a second of the same
# can't target an intent already carrying one. Empty: an ordinary status.
@export var intent_mark: StringName = &""

# Its holder's next ATTACK deals `magnitude` less in all, not per hit
# (Garnish's Garnished): the hits soak it in order, each down to 0 at
# most, after every modifier (Braced's 50% first) and before block
# (EnemyTurn.reduce_hit()). A total, so not a MODIFIER - leave category
# INFORMATIONAL, or apply_modifiers() would take it off every hit too.
# Copies add up through StackRule.ADD_MAGNITUDE. Pair it with
# consumed_by_own_attack and DURATION_UNTIL_TRIGGERED.
# On the player instead, it's each enemy ATTACK against them that deals
# `magnitude` less in all - the same pool, so Garnished on the attacker
# and this add up. Never consumed_by_own_attack.
@export var reduces_attack_total: bool = false

# On the player: every enemy hit against them deals `magnitude` less, each
# down to 0 at most - after every modifier and the attack's total
# reduction (Garnished's), before block (EnemyTurn.land_attack(); the
# intent's preview reads it the same way - replay_attack()). Unbroken's,
# at Critical, with default_duration_turns 1: until the player's next turn
# starts, every hit of every attack, so a 3-hit attack loses it three
# times. A strike back is a hit too - leave ignores_strike_backs off.
# Self-inflicted loss never goes through a hit. Copies add up through
# StackRule.ADD_MAGNITUDE.
@export var reduces_each_hit: bool = false

# Its holder's next turn is skipped (Stunned): whatever move is queued
# doesn't happen and the pattern moves on as if it had - lost, not
# delayed - and the turn still counts (escalation keeps its clock). Its
# statuses still tick first, so a countdown can still go off. Removed by
# that turn, whatever else it does (a pain turn on the same turn spends
# it too) - it never carries over (EnemyTurn.take_turn()). Pair it with
# DURATION_UNTIL_TRIGGERED and StackRule.IGNORE. A holder can't be
# targeted by another card applying it (BattleController).
@export var skips_next_turn: bool = false

# Its holder's next action waits a turn (Deny's Delayed): on its coming
# turn it does nothing - the queued move held where it is, the marks on
# it (Braced, Garnished) still bound to it, its turn count not moving, so
# an escalation is paused with it - and on the turn after it performs the
# held move, its loop going on from there. Its statuses still tick on the
# do-nothing turn, and a pain turn due then is spent on it. Removed by
# that turn. A Delayed packmate doesn't answer a Signal, holding its own
# move. Pair it with DURATION_UNTIL_TRIGGERED and StackRule.IGNORE; a
# holder can't be targeted by another card applying it.
@export var delays_next_action: bool = false

# Extra hits its holder - an enemy - lands with every multi-hit ATTACK
# (EnemyIntent.hits above 1) while it's up; a single blow stays single
# (EnemyTurn.hit_count()). Off the rock: the Greyshelf's Tail Lash strikes
# 4 times. 0 = none.
@export var bonus_hits: int = 0

# Added to the interrupt threshold of every breakable ATTACK its holder -
# an enemy - queues while it's up (EnemyIntent.interrupt_threshold;
# EnemyTurn.interrupt_threshold()): below 0 it breaks sooner, never below
# 1. Off the rock: the Greyshelf's Gape breaks at 20, not 26. 0 = none.
@export var interrupt_threshold_change: int = 0

# How many times its holder - an enemy - carries out its current intent
# each turn while it's up (Bereft: 2): an ATTACK lands as that many
# separate attacks, one after another, and a DEFEND gains its Block that
# many times; the loop then advances once, as for any turn (EnemyTurn.
# take_turn()). Any other intent resolves once. The display shows all of
# it (EnemyTurn.preview_intent()). 1 = once, as every enemy acts.
@export var repeats_intent: int = 1

# Dying Light: the first time each of its holder's turns they cross their
# Critical line - into Critical or back out, from HP moving or the line
# moving (On the Brink, Go Under) - they gain crossing_energy Energy and
# draw crossing_draw. Judged per status at Status.resolve_critical_
# triggers()'s beat (after a card, an enemy attack, the turn's ticks); a
# crossing on the enemy's turn resolves as the holder's next turn starts,
# once, as that turn's. BattleController resolves it (_resolve_
# crossings()). {energy} and {draw} in the description. Both 0 = none.
@export var crossing_energy: int = 0
@export var crossing_draw: int = 0

# Block its holder gains at the start of each of their turns, per stack,
# after the turn's Block reset (Marrow - a Devoured Skill's yield,
# DevourYield). Read by Status.turn_start_block(); {block} in the
# description. 0 = none.
@export var turn_start_block: int = 0

# While its holder has it, they are Critical at or below this percent of
# max HP - over their own line when it is higher (Go Under's Gone Under:
# 40), never under it. Read through Combatant.critical_fraction(), so
# everything that judges Critical moves with it. 0 = none.
@export_range(0, 100) var raises_critical_percent: int = 0

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

# Passed by a strike back - damage an enemy deals in answer to a card in
# the player's own turn (Coiled's - EnemyTurn.counter_strike()), or an
# attack that lands as one (EnemyIntent.lands_as_strike_back - the
# Siltjaw's Erupt): it neither softens that hit nor
# is spent by it, and waits, armed, for the enemy's own turn. The strike
# back lands in full past it. Braced (Brace) and Garnished (Garnish) on
# the enemy's intent; No Further's armed status on the player.
@export var ignores_strike_backs: bool = false

# Barbed (Stoneshell): the first enemy attack hit its holder's Block takes
# any of costs that attacker this much - once the attack has resolved,
# through the attacker's Block, as plain damage, not an Attack card, so
# nothing strikes back at it (EnemyTurn.land_attack()). Spent when it
# fires; a strike back never fires it (give it ignores_strike_backs
# too). 0 = none.
@export var barbed_damage: int = 0

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
# Said over its holder - an enemy - in the world voice the moment it
# gains this status in a fight (RegionField, on BattleController.enemy_
# status_gained): Bereft's "The other keeps dancing." Empty = nothing.
@export var gained_line: String = ""

# A status that waits for its holder's next turn (Ransom): at the start of
# the player's turn, after the ticks (BattleController._start_player_
# turn(), Status.resolve_turn_start_triggers()), it is removed and this
# status applied in its place. Pair it with DURATION_UNTIL_REMOVED so no
# tick takes it first. Null = none.
@export var grants_on_turn_start: StatusData = null

# Gone the moment its holder's turn ends (BattleController.end_turn(),
# Status.remove_at_turn_end()) - "this turn" means the player's turn, not
# the enemy's that follows (Ransom's turn, Leverage's unused discount).
# Pair it with DURATION_UNTIL_REMOVED so no tick takes it first.
@export var ends_at_turn_end: bool = false

# Each charge is a turn of the player's own after this one (Owed Time):
# when their turn ends, one charge goes and the enemy turn is skipped -
# the next player turn starts at once (BattleController._finish_turn(),
# Status.take_extra_turn()). Pair it with ADD_CHARGES, so every play queues
# one more, and DURATION_UNTIL_REMOVED.
@export var grants_extra_turn: bool = false

# While its holder has it, damage that gets past their Block and absorb
# takes their Toll first, 1 for 1, and only the rest reaches HP (Thick
# Skin - DamagePipeline.resolve()): enemy hits, strike backs included.
# Never their own HP loss - self-damage, a stance's price, a status tick
# go round the pipeline (apply_bypass()). Toll taken this way is spent
# (Reckoning counts it, Gnaw's "spent this turn" sees it) but hurries no
# Sentence - that is a card's spend's alone. On a card face it reads as
# Toll (CardView's keyline).
@export var toll_pays_damage: bool = false

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


# A cost reduction (Leverage): the next card played costs this much less
# Energy per stack, never below 0 - after House Key's free card
# (Combatant.energy_cost()). The next card costing at least 1 Energy
# spends it, and the whole status goes; a
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
