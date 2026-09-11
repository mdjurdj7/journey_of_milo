extends RefCounted
class_name Combatant

# One fighter's rules-side state - the player or one enemy. Pure data;
# no signals, no view references. battle_controller.gd is what turns a
# mutation here into a signal for the overlay to react to.

var hp: int = 1
var max_hp: int = 1
var block: int = 0
var absorb: int = 0
var statuses: Array[Status] = []

# --- Player-only resources ---
#
# Left at their defaults, unused, on an enemy Combatant - same "empty
# means unaffected" idiom the old project used throughout EnemyData/
# CardEffect.
var toll: int = 0
var energy: int = 0
var max_energy: int = 3
var rally_pool: int = 0
var rally_recovery_percent: int = 50
# Placeholder value - the old project read this from CharacterData.rally_
# recovery_percent (the Wanderer's own class passive), which isn't ported
# this pass (no RunState/character selection yet - see GAME_FRAMEWORK.md's
# own settled/open notes). Retune here directly once a real class
# resource exists to read it from instead.
var took_damage_this_turn: bool = false
var took_damage_last_turn: bool = false

# --- Enemy-only ---
#
# Left at its default -1 for the player Combatant - see enemy_turn.gd.
var current_intent_index: int = -1

func _init(starting_hp: int = 1) -> void:
	hp = starting_hp
	max_hp = starting_hp
