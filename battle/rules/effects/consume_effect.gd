extends RefCounted
class_name ConsumeEffect

# CONSUME (Deny): the hand card picked before the play committed (Effect
# Context.consume_choice - BattleController takes the most expensive
# other card by printed cost, or the player's pick among a tie) goes to
# the Spent pile for the rest of this fight, back in the deck next fight
# like any Spent card - a CONSUMED one too: it wasn't played, so it is
# on Deck.spent_unplayed and the run keeps it. Nothing picked - no other
# card in hand - consumes nothing; the card's other effects still resolve.
func resolve(_effect: CardEffect, ctx: EffectContext) -> void:
	if ctx.deck == null or ctx.consume_choice == null or not ctx.deck.hand.has(ctx.consume_choice):
		return
	ctx.deck.exhaust(ctx.consume_choice)
	ctx.deck.spent_unplayed.append(ctx.consume_choice)

# The cards a CONSUME can take from `cards` (the hand without the card
# being played): every one at the highest printed cost (CardData.cost) -
# never the discounted cost a face shows, so Leverage, the House Key or
# Collateral can't reorder them or make a tie. One is taken outright;
# more is a tie for the player to settle.
static func candidates(cards: Array[CardData]) -> Array[int]:
	var best: int = -1
	var picked: Array[int] = []
	for i in cards.size():
		var card: CardData = cards[i]
		if card == null:
			continue
		if card.cost > best:
			best = card.cost
			picked.clear()
		if card.cost == best:
			picked.append(i)
	return picked
