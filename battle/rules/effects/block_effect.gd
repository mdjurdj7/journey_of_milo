extends RefCounted
class_name BlockEffect

# `value` Block, or alt_value on a met REPLACE (Unbroken, while Critical)
# - CardBonus's reading, the same one the card face prints - and, on the
# card's first Block effect, the worn piece's bonus for the class's basic
# defence card (EffectContext.take_block_bonus() - the Harness). Through
# gain_block(), so Last Resort can refuse it.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.gain_block(CardBonus.resolved_value(effect, ctx) + ctx.take_block_bonus())
