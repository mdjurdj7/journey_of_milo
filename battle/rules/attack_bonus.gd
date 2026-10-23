extends RefCounted
class_name AttackBonus

# The flat extra damage ONE Attack card deals: the stance's bonus plus
# every status's (Self-Eater, Last Resort, Keen), each gated on
# Critical where its data says so. Once per Attack card, not per hit or
# per damage effect - EffectContext.take_attack_bonus() hands it to the
# card's first damage effect and nothing after - save a repeated hit
# (CardEffect.repeat_per_earlier_play_tag), which takes the ongoing part again
# (ongoing_for_player()). The resolver and the card
# face both call this, so the face can't print a bonus the rules won't
# pay.
#
# `at_hp` is the HP Critical is judged at: the player's own when the
# attack lands, what it will be once the card's own costs are paid when a
# face previews it (see CardBonus.upfront_hp_cost()).
static func for_player(player: Combatant, at_hp: int) -> int:
	return add_for_player(NumberBreakdown.new(), player, at_hp).total

# The same, each source a part of `into`.
static func add_for_player(into: NumberBreakdown, player: Combatant, at_hp: int) -> NumberBreakdown:
	if player == null:
		return into
	return add_when_critical(into, player, player.is_critical_at(at_hp))

# The same sum with Critical given rather than read - what each half of a
# Critical card's face prints: the {else} half as if not Critical, the
# {if} half as if Critical, so neither shows a bonus that can't apply in
# its own state.
static func when_critical(player: Combatant, critical: bool) -> int:
	return add_when_critical(NumberBreakdown.new(), player, critical).total

# The same, the stance and each status a part of `into`.
static func add_when_critical(into: NumberBreakdown, player: Combatant, critical: bool) -> NumberBreakdown:
	if player == null:
		return into
	Stance.add_attack_bonus(into, player.stance, critical)
	return Status.add_attack_bonus(into, player.statuses, critical)

# The part of the bonus that holds for every hit rather than being spent
# by one - the stance's and every status's without charges (Self-Eater,
# Last Resort, Hungry), Keen's charge left out. What a repeated hit of
# the same card takes (CardEffect.repeat_per_earlier_play_tag - Lash); an
# ordinary Attack still takes the whole bonus once, above.
static func ongoing_for_player(player: Combatant, at_hp: int) -> int:
	if player == null:
		return 0
	var critical: bool = player.is_critical_at(at_hp)
	return Stance.attack_bonus(player.stance, critical) + Status.attack_bonus(player.statuses, critical, null, true)
