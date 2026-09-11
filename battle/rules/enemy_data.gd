extends Resource
class_name EnemyData

# Trimmed hard from the old project's enemy_data.gd - name, max HP, and a
# move list is all this pass needs (no visual/scale/escalation/pain-turn/
# charge/growth/escape/encounter-linked/mark fields - all out of scope,
# see DESIGN.md). A FieldEnemy references one of these (field_enemy.gd's
# own enemy_data export).

@export var enemy_name: String = ""
@export var max_hp: int = 1
@export var intents: Array[EnemyIntent] = []
# The enemy's attack pattern. Fixed enemies step through this in order,
# looping; erratic ones (see below) pick freely each turn instead.

@export var erratic_intent_selection: bool = false
# False (every enemy by default): intents advance in a fixed loop. True:
# a fresh independent weighted pick every turn, repeats allowed (subject
# to each intent's own no_immediate_repeat/turn_one_locked) - see
# enemy_turn.gd.
