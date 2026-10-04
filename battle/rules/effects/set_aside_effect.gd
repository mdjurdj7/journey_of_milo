extends RefCounted
class_name SetAsideEffect

# SET_ASIDE (Bide): up to `value` of the cards the player chose from the
# hand (EffectContext.set_aside_choice, picked before the play committed)
# leave it for the deck's set-aside pile, and come back at the start of
# the next turn (Deck.return_set_aside(), from BattleController). Fewer
# chosen - none included - sets aside fewer; a chosen card no longer in
# the hand is skipped.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if ctx.deck == null:
		return
	var chosen: Array[CardData] = []
	for card in ctx.set_aside_choice:
		if chosen.size() >= effect.value:
			break
		chosen.append(card)
	ctx.deck.set_aside(chosen)
