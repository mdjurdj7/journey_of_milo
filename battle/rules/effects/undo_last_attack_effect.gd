extends RefCounted
class_name UndoLastAttackEffect

# UNDO_LAST_ATTACK (Not So): the newest enemy attack on the player's record
# not yet undone (Combatant.last_undoable_hit() - every hit of it, Block
# already taken out) is undone - once:
# - its HP restored, a heal (EffectContext.heal(): never past max HP, no
#   Toll) - which can lift the player out of Critical;
# - its share of the Grace window still open closed (close_grace()), so
#   the same hit can't be won back twice;
# - as much dealt back to its attacker, living: not an Attack - no attack
#   bonus, nothing that waits for one - through the attacker's own
#   incoming modifiers (Covered, Exposed) and Block, as a Sentence's blow
#   is. A dead attacker takes nothing; the HP is restored all the same.
# What it did is on the last call's `undone` (for the run log).
func resolve(_effect: CardEffect, ctx: EffectContext) -> void:
	var entry: Dictionary = ctx.player.last_undoable_hit()
	if entry.is_empty():
		return
	entry["undone"] = true
	var before: int = ctx.player.hp
	ctx.heal(int(entry["hp"]))
	var restored: int = ctx.player.hp - before
	var grace_closed: bool = close_grace(ctx.player, entry)
	var dealt: int = 0
	var attacker: Combatant = entry["attacker"]
	if attacker != null and attacker.hp > 0:
		var amount: int = Status.apply_modifiers(int(entry["hp"]), attacker.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		var result := DamagePipeline.resolve(amount, attacker)
		ctx.report_block(attacker, result)
		dealt = result["damage_to_hp"]
		if dealt > 0:
			ctx.report_damage(attacker, dealt, "status")
	ctx.last_undo = {"intent": entry["intent"], "attacker": attacker, "restored": restored, "dealt": dealt, "grace_closed": grace_closed}

# `entry`'s share of the Grace window, if that window is still open and it
# opened some: off the window's list, and the pool down to what the rest
# of the window opened - the best other share (LARGEST_HIT), or less this
# share (SUM) - never up. True when the pool went down.
static func close_grace(player: Combatant, entry: Dictionary) -> bool:
	var index: int = player.grace_window_hits.find(entry)
	if index < 0:
		return false
	player.grace_window_hits.remove_at(index)
	if player.grace <= 0:
		return false
	var before: int = player.grace
	if player.grace_cap_mode == CharacterData.GraceCapMode.SUM:
		player.grace = maxi(player.grace - int(entry["grace_share"]), 0)
	else:
		var best: int = 0
		for other in player.grace_window_hits:
			best = maxi(best, int(other["grace_share"]))
		player.grace = mini(player.grace, best)
	if player.grace <= 0:
		player.grace_turns_left = 0
	return player.grace < before
