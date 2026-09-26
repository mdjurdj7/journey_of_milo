extends Resource
class_name EnemyIntent

# ATTACK/DEFEND, and BURROW for the Siltjaw - the old project's IDLE/
# WIND_UP/GROWTH/CHARGE_ATTACK/MARK types all belonged to mechanics this
# pass explicitly drops (wind-up telegraphs, growth tracks, boss charge,
# mark attacks - see DESIGN.md's own parked-items note). Extend this enum
# the same way the old project did, when a real enemy needs one of them
# back - BUFF/DEBUFF (a status on self / on the Wanderer) are the expected
# next two; the BattleIntent display draws only what exists here.
#
# BURROW: while this is the enemy's queued intent it is under the sand -
# it can't be targeted and takes no damage (Combatant.buried, kept in
# step by EnemyTurn) - and its turn does nothing; it surfaces at the end
# of it. Reached as an ATTACK's on_interrupt (below), not from the loop.
enum IntentType { ATTACK, DEFEND, BURROW }

@export var type: IntentType = IntentType.ATTACK
@export var value: int = 0
# Damage dealt PER HIT if ATTACK, block gained if DEFEND.

@export var hits: int = 1
# ATTACK only: how many separate hits of `value` this intent lands in one
# turn - each one goes through the player's block/absorb on its own, and
# one-shot statuses (StatusData.clears_on_trigger) are consumed by the
# first. BattleIntent shows this as "N x M". 1 for every existing enemy.

@export var erratic_weight: float = 1.0
# Only consulted when EnemyData.erratic_intent_selection is true - this
# intent's relative likelihood among candidates (double the weight,
# double the odds - not a percentage on its own).

@export var turn_one_locked: bool = false
# Excludes this intent from an erratic enemy's very first pick only -
# from turn two on it's a fully normal candidate again.

@export var no_immediate_repeat: bool = false
# Excludes this intent from being picked as the very next turn's free
# choice if it was ALSO the intent picked last turn.

@export var simultaneous: bool = false
# A pack's shared move (the dragonflies' Swarm): when every living member
# of a fight's cluster is queued on an intent with this set, they act as
# one - lunges started together, one wait, every hit landed in the same
# beat (BattleController._run_enemy_turn()). The rules are unchanged:
# each member's take_turn() runs on its own, so Grace still sees three
# separate hits. False = the ordinary one-after-another turn.

@export var interrupt_threshold: int = 0
# ATTACK only: damage the player has to deal this enemy during the turn
# this intent is queued for (Combatant.damage_taken_this_turn) for it to
# be interrupted - checked when the enemy's turn comes, so everything
# played that turn counts and the enemy is still hittable after the
# number is reached. Interrupted, the attack doesn't land and on_interrupt
# is queued in its place. BattleIntent shows it beside the damage,
# counting down. 0 = can't be interrupted (every enemy but the Siltjaw).

@export var on_interrupt: EnemyIntent = null
# What the enemy does on its NEXT turn when this one is interrupted - an
# interjection outside the intents loop (Combatant.interjected_intent),
# which carries on where it was once this has resolved. The Siltjaw's is
# a BURROW. Null = the interrupted turn is simply lost.
