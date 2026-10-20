extends RefCounted
class_name CopyHandCardEffect

# COPY_HAND_CARD (Countersign): a fight-only copy of the hand card the
# player chose (EffectContext.copy_choice, picked before the play
# committed) into the hand (Deck.add_copy()) - Spent when played, gone at
# the end of the turn, never in the run's deck. A choice no longer in the
# hand is skipped.
func resolve(_effect: CardEffect, ctx: EffectContext) -> void:
	if ctx.deck == null or ctx.copy_choice == null or not ctx.deck.hand.has(ctx.copy_choice):
		return
	if ctx.deck.add_copy(ctx.copy_choice) != null:
		RunLogger.mechanic("copy", {"card": ctx.copy_choice.card_name})
