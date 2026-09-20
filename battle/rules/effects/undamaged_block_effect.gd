extends RefCounted
class_name UndamagedBlockEffect

# `value` block, PLUS `bonus_value` more when the effect's condition
# holds (UNDAMAGED_LAST_TURN on Untouched: no HP lost during the
# player's previous turn) - an ADD, not a replace. The number is
# CardBonus's reading, the same one the card face prints.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.block += CardBonus.resolved_value(effect, ctx)
