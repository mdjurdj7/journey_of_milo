extends RefCounted
class_name StunEffect

# Interrupts are out of scope this pass (no enemy-intent-cancel mechanism
# exists yet), and this type's only old caller was a chain payoff - chain
# roles aren't ported either (see CardData's own doc). Registered as a
# no-op so the type/registry slot exists rather than erroring, ready for
# whichever of those two lands first.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	pass
