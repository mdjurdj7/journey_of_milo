extends Resource
class_name EnemyIntent

# ATTACK/DEFEND only - the old project's IDLE/WIND_UP/GROWTH/CHARGE_
# ATTACK/MARK types all belonged to mechanics this pass explicitly drops
# (wind-up telegraphs, growth tracks, boss charge, mark attacks - see
# DESIGN.md's own parked-items note). Extend this enum the same way the
# old project did, when a real enemy needs one of them back.
enum IntentType { ATTACK, DEFEND }

@export var type: IntentType = IntentType.ATTACK
@export var value: int = 0
# Damage dealt if ATTACK, block gained if DEFEND.

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
