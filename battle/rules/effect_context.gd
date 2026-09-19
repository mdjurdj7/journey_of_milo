extends RefCounted
class_name EffectContext

# What one CardEffect resolution needs to see and do - assembled fresh by
# battle_controller.gd for each card played, handed to whichever effect
# script resolves it (see effect_resolver.gd). Deliberately signal-free:
# effects report what happened by calling report_damage()/grace_reclaim()
# below, and battle_controller.gd decides what that becomes (a signal, a
# log call) - nothing under battle/rules/ knows signals exist.

var player: Combatant
var target: Combatant = null
var enemies: Array[Combatant] = []
var deck: Deck
var cards_played_this_turn: int = 0
# Called with the amount reclaimed, so battle_controller.gd can mirror it
# onto RunState and tell the readouts. Grace itself is spent here, in the
# rules, the same way damage is dealt here and only REPORTED outward.
var on_grace_reclaimed: Callable = Callable()

var on_damage: Callable = Callable()
# Called as on_damage.call(target_combatant, amount, kind) whenever an
# effect actually lands damage.

func report_damage(target_combatant: Combatant, amount: int, kind: String) -> void:
	if on_damage.is_valid():
		on_damage.call(target_combatant, amount, kind)

# Damage this player just dealt takes Grace back 1:1, per hit as it
# lands, never past max HP and never more Grace than is left. Silent and
# free when the player has none open, which is every fight for a class
# without the passive.
func grace_reclaim(damage_to_hp: int) -> void:
	if damage_to_hp <= 0 or player.grace <= 0:
		return
	var reclaimed: int = mini(damage_to_hp, player.grace)
	reclaimed = mini(reclaimed, player.max_hp - player.hp)
	if reclaimed <= 0:
		return
	player.grace -= reclaimed
	player.hp += reclaimed
	if on_grace_reclaimed.is_valid():
		on_grace_reclaimed.call(reclaimed)
