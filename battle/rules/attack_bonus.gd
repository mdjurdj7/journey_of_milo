extends RefCounted
class_name AttackBonus

# The flat extra damage ONE Attack card deals: the stance's bonus plus
# every status's (Self-Eater, Last Resort, Dying Light), each gated on
# Critical where its data says so. Once per Attack card, not per hit or
# per damage effect - EffectContext.take_attack_bonus() hands it to the
# card's first damage effect and nothing after. The resolver and the card
# face both call this, so the face can't print a bonus the rules won't
# pay.
#
# `at_hp` is the HP Critical is judged at: the player's own when the
# attack lands, what it will be once the card's own costs are paid when a
# face previews it (see CardView._upfront_hp_cost()).
static func for_player(player: Combatant, at_hp: int) -> int:
	if player == null:
		return 0
	return when_critical(player, player.is_critical_at(at_hp))

# The same sum with Critical given rather than read - what each half of a
# Critical card's face prints: the {else} half as if not Critical, the
# {if} half as if Critical, so neither shows a bonus that can't apply in
# its own state.
static func when_critical(player: Combatant, critical: bool) -> int:
	if player == null:
		return 0
	return Stance.attack_bonus(player.stance, critical) + Status.attack_bonus(player.statuses, critical)
