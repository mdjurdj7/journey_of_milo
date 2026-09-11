extends RefCounted
class_name EffectContext

# What one CardEffect resolution needs to see and do - assembled fresh by
# battle_controller.gd for each card played, handed to whichever effect
# script resolves it (see effect_resolver.gd). Deliberately signal-free:
# effects report what happened by calling report_damage()/contribute_to_
# rally() below, and battle_controller.gd decides what that becomes
# (a signal, a log call) - nothing under battle/rules/ knows signals
# exist.

var player: Combatant
var target: Combatant = null
var enemies: Array[Combatant] = []
var deck: Deck
var cards_played_this_turn: int = 0
var rally_window: RallyWindow = null

var on_damage: Callable = Callable()
# Called as on_damage.call(target_combatant, amount, kind) whenever an
# effect actually lands damage.

func report_damage(target_combatant: Combatant, amount: int, kind: String) -> void:
	if on_damage.is_valid():
		on_damage.call(target_combatant, amount, kind)

func contribute_to_rally(damage_to_hp: int) -> void:
	if rally_window != null:
		rally_window.contribute(player, damage_to_hp)
