extends RefCounted
class_name GrantKeepEffect

# GRANT_KEEP (Bide): up to `value` of the cards the player chose from the
# hand (EffectContext.keep_choice, picked before the play committed) gain
# Keep - they stay in the hand at each turn's end until played (Deck.
# grant_keep()). Fewer chosen - none included - keeps fewer; a chosen card
# no longer in the hand is skipped.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if ctx.deck == null:
		return
	var granted: Array[String] = []
	for card in ctx.keep_choice:
		if granted.size() >= effect.value:
			break
		if ctx.deck.grant_keep(card):
			granted.append(card.card_name)
	RunLogger.mechanic("keep", {"cards": granted})
