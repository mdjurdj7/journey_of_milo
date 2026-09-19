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

# Extra damage the active stance grants THIS card's attacks, set by
# EffectResolver.resolve_card() and read by damage_effect.gd. Zero unless
# the card being resolved is an ATTACK and a stance is up, so no damage
# effect needs to know what a stance is.
var stance_attack_bonus: int = 0

# Did this card's damage finish something off? Set by damage_effect.gd,
# cleared per card by EffectResolver.resolve_card(), read by
# Condition.TARGET_KILLED - the one condition that depends on what an
# earlier effect on the same card did rather than on state that already
# existed.
var killed_this_card: bool = false

# HP put back by a card (HEAL, TOLL_HEAL). The rules mutate the
# Combatant; this is how battle_controller.gd learns to mirror it onto
# the run's own HP and tell the readouts - the same split report_damage()
# already uses, and the same one Grace's reclaim uses.
var on_heal: Callable = Callable()

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
# The HP an Attack costs while a stance is held. Self-inflicted, so it
# takes the same route SELF_DAMAGE does: past block and absorb, accruing
# Toll, reported as "self" - and opening no Grace, because Grace only
# ever opens on an enemy's hit.
func pay_stance_attack_cost(amount: int) -> void:
	if amount <= 0:
		return
	var lost: int = DamagePipeline.apply_bypass(amount, player)
	if lost > 0:
		player.toll += lost
		player.took_damage_this_turn = true
		report_damage(player, lost, "self")

# Heals the player and reports it. Callers mutate through this rather
# than touching hp directly, so the run's HP can't drift from the
# fight's - it silently did for HEAL before this existed.
func heal(amount: int) -> void:
	if amount <= 0:
		return
	var before: int = player.hp
	player.hp = mini(player.hp + amount, player.max_hp)
	var gained: int = player.hp - before
	if gained > 0 and on_heal.is_valid():
		on_heal.call(gained)

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
