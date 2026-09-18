extends Resource
class_name EnemyIntent

# ATTACK/DEFEND only - the old project's IDLE/WIND_UP/GROWTH/CHARGE_
# ATTACK/MARK types all belonged to mechanics this pass explicitly drops
# (wind-up telegraphs, growth tracks, boss charge, mark attacks - see
# DESIGN.md's own parked-items note). Extend this enum the same way the
# old project did, when a real enemy needs one of them back - BUFF/DEBUFF
# (a status on self / on the Wanderer) are the expected next two; the
# BattleIntent display draws only what exists here.
enum IntentType { ATTACK, DEFEND }

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
