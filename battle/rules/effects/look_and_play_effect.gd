extends RefCounted
class_name LookAndPlayEffect

# LOOK_AND_PLAY (Collateral): asks for the top `value` cards of the draw
# pile to be shown once the card has resolved (EffectContext.look_count).
# The look itself is the controller's - a pick, and a play that follows
# it, are no part of this card's own resolution (BattleController.
# _begin_look()).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.look_count = maxi(ctx.look_count, effect.value)
