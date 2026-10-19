extends RefCounted
class_name ReplayLastAttackEffect

# Second Swing: the last Attack card played this turn (Combatant.last_
# attack - recorded at a real play's commit, never by a replay) resolves
# again, its effects in full as if played - its own HP and Toll, the
# stance's price and bonus, Keen if a charge is left, Ransom's heal - but
# it isn't played: no Energy, no pile, no played-card or tag count, and
# nothing that waits for an Attack card's first blows (Bent Nail - see
# EffectContext.is_replay). Blocked with no Attack played this turn
# (EffectResolver.card_blocked()).
#
# In a fight the view replays it once this card has resolved, as a blow
# of its own (EffectContext.on_replay - BattleController._replay_attack(),
# which also picks the target). With no view (a bare rules context) it
# replays here: at the enemy it was played at while that one stands, at
# this card's target otherwise, at every enemy for an all-enemies Attack.
func resolve(_effect: CardEffect, ctx: EffectContext) -> void:
	var card: CardData = ctx.player.last_attack
	if card == null:
		return
	if ctx.on_replay.is_valid():
		ctx.on_replay.call()
		return
	var replay := EffectContext.new()
	replay.player = ctx.player
	replay.enemies = ctx.enemies
	replay.deck = ctx.deck
	var before: Combatant = ctx.player.last_attack_target
	replay.target = before if before != null and before.hp > 0 and ctx.enemies.has(before) else ctx.target
	replay.is_replay = true
	replay.cards_played_before_this = ctx.cards_played_before_this + 1
	replay.tagged_plays_before_this = ctx.player.tagged_plays_this_turn.duplicate()
	replay.on_damage = ctx.on_damage
	replay.on_heal = ctx.on_heal
	RunLogger.push_source("replay:" + card.card_name)
	EffectResolver.new().resolve_card(card, replay)
	RunLogger.pop_source()
