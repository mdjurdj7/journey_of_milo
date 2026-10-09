extends RefCounted
class_name TollSpentBlockEffect

# TOLL_SPENT_BLOCK (Settled Account): `value` Block, plus 1 for every
# toll_per_block Toll spent earlier this turn - through gain_block(), so
# Last Resort refuses it like any Block.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.gain_block(amount(effect, ctx.player))

# The Block it gives `player` now: `value` + Combatant.toll_spent_amount_
# this_turn / toll_per_block, rounded down. The rules and the card face
# both read this; a null player (a face outside a fight) has spent
# nothing.
static func amount(effect: CardEffect, player: Combatant) -> int:
	var spent: int = player.toll_spent_amount_this_turn if player != null else 0
	if effect.toll_per_block <= 0:
		return effect.value
	return effect.value + floori(float(spent) / float(effect.toll_per_block))
