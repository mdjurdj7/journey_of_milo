extends RefCounted
class_name TopFromHandEffect

# TOP_FROM_HAND (Weathered Map): asks for a hand card to go on top of the
# draw pile once the card has resolved (EffectContext.top_from_hand) -
# after its draw, so the pick can be a card just drawn. The pick is the
# controller's (BattleController._begin_top_choice()).
func resolve(_effect: CardEffect, ctx: EffectContext) -> void:
	ctx.top_from_hand = true
