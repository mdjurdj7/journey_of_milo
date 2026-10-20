extends RefCounted
class_name DevourFromHandEffect

# DEVOUR_FROM_HAND (Take In): the hand card the player chose (EffectContext.
# devour_choice, picked before the play committed) is Devoured - out of the
# hand for the rest of this fight (Deck.devour(): to the Spent pile and
# back next fight; a fight-only copy just gone), its yield on the player
# (DevourYield.apply(), `value` per Energy of its printed cost), and it on
# the fight's Devoured list (Combatant.devoured_cards). The hand plays the
# bite (EffectContext.on_devour). Never the Devour button: no heal, no use
# of it, nothing on its jaw. A choice no longer in the hand is skipped.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var card: CardData = ctx.devour_choice
	if ctx.deck == null or card == null or not ctx.deck.hand.has(card):
		return
	ctx.deck.devour(card)
	var yielded: Dictionary = DevourYield.apply(card, effect.value, ctx.player)
	ctx.player.devoured_cards.append(card)
	if ctx.on_devour.is_valid():
		ctx.on_devour.call(card)
	RunLogger.event("devour_keyword", {"card": card.card_name, "yield": DevourYield.kind_name(int(yielded["kind"])), "amount": int(yielded["amount"])})
