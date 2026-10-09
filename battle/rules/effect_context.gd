extends RefCounted
class_name EffectContext

# What one CardEffect resolution needs to see and do - assembled fresh by
# battle_controller.gd for each card played, handed to whichever effect
# script resolves it (see effect_resolver.gd). Deliberately signal-free:
# effects report what happened by calling report_damage()/grace_reclaim()
# below, and battle_controller.gd decides what that becomes (a signal, a
# log call) - nothing under battle/rules/ knows signals exist.

var player: Combatant
var target: Combatant = null
# The enemies a card can reach: living and not buried (Combatant.buried).
# A buried enemy is left out, so an all-enemies effect never counts it.
var enemies: Array[Combatant] = []
var deck: Deck
# The cards the player chose from the hand for a SET_ASIDE (Bide), picked
# before the play committed (BattleController's choose mode). Empty for
# every other card, and for a Bide played with none chosen.
var set_aside_choice: Array[CardData] = []
# The hand card a CONSUME (Deny) takes: the most expensive other card,
# picked - or chosen among a tie - before the play committed (Battle
# Controller). Null when there was none to take.
var consume_choice: CardData = null
# Cards committed this turn BEFORE the one this context is for - what
# Condition.FIRST_CARD_THIS_TURN reads. The controller counts a card at
# commit, so for the card resolving this is its count minus one; for a
# preview of a card still in hand it is the count itself.
var cards_played_before_this: int = 0
# Called with the amount reclaimed, so battle_controller.gd can mirror it
# onto RunState and tell the readouts. Grace itself is spent here, in the
# rules, the same way damage is dealt here and only REPORTED outward.
var on_grace_reclaimed: Callable = Callable()

# Whether the card being resolved is an ATTACK - set by EffectResolver.
# resolve_card(), and what take_attack_bonus() pays out on.
var card_is_attack: bool = false
# Whether this card's attack bonus has been handed out already - see
# take_attack_bonus(). Cleared per card by resolve_card().
var attack_bonus_taken: bool = false
# Whether this card has actually spent Toll (spend_toll()) - what hurries
# a countdown, once per card. Cleared per card by resolve_card().
var toll_spent_this_card: bool = false
# The enemies whose mark this card has already been paid (take_mark_
# bonus()). Cleared per card by resolve_card().
var mark_bonus_paid: Array[Combatant] = []

# HP a card still in hand will have paid before its conditions are read -
# its own self-damage ahead of them, and the stance's per-Attack cost. Set
# only on a card face's preview copy (for_card_preview()); 0 when a card
# actually resolves, since by then those costs HAVE been paid. Read by
# Condition.CRITICAL alone.
var preview_hp_cost: int = 0

# HP this card costs in place of its Energy - a cost replacement's
# (Collateral, Combatant.replaced_cost_hp()), read by the controller when
# the play committed, since its charge is spent then. Paid by
# EffectResolver.resolve_card() before anything else on the card. 0 for
# every card nothing covered.
var replaced_cost_hp: int = 0
# What that HP is paid to, for the run log: "status:<id>" of the cost
# replacement. Set with replaced_cost_hp.
var replaced_cost_source: String = ""

# Did this card's damage finish something off? Set by damage_effect.gd,
# cleared per card by EffectResolver.resolve_card(), read by
# Condition.TARGET_KILLED - the one condition that depends on what an
# earlier effect on the same card did rather than on state that already
# existed.
var killed_this_card: bool = false

# HP this card's hits took from enemies, net of Grace: each hit adds the
# HP the enemy actually lost (no overkill) less what Grace reclaimed from
# that hit, never below 0 (record_hit()). What an Attack Drains for while
# StatusData.attacks_drain is up (EffectResolver.resolve_card()). Cleared
# per card by resolve_card().
var hp_dealt_this_card: int = 0

# HP put back by a card (HEAL, TOLL_HEAL). The rules mutate the
# Combatant; this is how battle_controller.gd learns to mirror it onto
# the run's own HP and tell the readouts - the same split report_damage()
# already uses, and the same one Grace's reclaim uses.
var on_heal: Callable = Callable()

var on_damage: Callable = Callable()
# Called as on_damage.call(target_combatant, amount, kind) whenever an
# effect actually lands damage.

var on_block: Callable = Callable()
# Called as on_repeat.call() when a hit is about to land again (Card
# Effect.repeat_toll_cost - Second Swing), before its Toll is spent: what
# the card reports from then on is the repeat's, which the view presents
# as its own follow-up blow. Nothing the rules decide reads it.
var on_repeat: Callable = Callable()
# Called as on_block.call(target_combatant, blocked, damage_to_hp) when a
# hit on an enemy meets its block - before that hit's on_damage, which
# only follows if some of it got through (damage_to_hp > 0).

# The attack bonus (AttackBonus) for the card being resolved, ONCE: the
# first damage effect to ask gets it, every later one 0 - the bonus is per
# Attack card, not per hit. Read when that effect resolves, so Critical
# is judged after whatever the card paid before it (Self-Eater's HP). 0 on
# anything but an ATTACK.
func take_attack_bonus() -> int:
	if not card_is_attack or attack_bonus_taken:
		return 0
	attack_bonus_taken = true
	var bonus: int = AttackBonus.for_player(player, player.hp)
	# A charged bonus ("+3 on your next Attack") is spent by the card that
	# took it - whether or not the blow lands on anyone.
	Status.spend_attack_bonus_charges(player.statuses, player.is_critical())
	return bonus

# The attack bonus for a REPEATED hit of the card being resolved (Card
# Effect.repeat_toll_cost - Second Swing): the ongoing part alone (Attack
# Bonus.ongoing_for_player()), every time it's asked - a one-shot charge
# went with the first hit, and spends nothing here. 0 on anything but an
# ATTACK. The mark bonus stays once per card: take_mark_bonus() pays it
# to the first hit only.
func take_repeat_attack_bonus() -> int:
	if not card_is_attack:
		return 0
	return AttackBonus.ongoing_for_player(player, player.hp)

# Every Toll a card spends goes through here: at most what is held, so
# Toll never goes below 0, and anything spent at all marks the card as
# having spent Toll (toll_spent_this_card - Sentence's hurry, once per
# card however much). Returns what was actually spent. Gaining Toll, or
# losing it any other way (the floor's reset), never comes here.
func spend_toll(amount: int) -> int:
	var spent: int = clampi(amount, 0, maxi(player.toll, 0))
	if spent <= 0:
		return 0
	player.toll -= spent
	toll_spent_this_card = true
	return spent

# The extra damage this Attack card deals to `enemy` for the marks it
# carries (StatusData.attack_bonus_against_holder - Come Due), ONCE per
# card per enemy, like the attack bonus: the first damage effect to land
# on it gets the bonus and spends a charge of each mark, every later one
# 0. Per enemy, so an all-enemies Attack pays it to the marked enemy
# alone. 0 on anything but an ATTACK, which spends nothing.
func take_mark_bonus(enemy: Combatant) -> int:
	if not card_is_attack or enemy == null or mark_bonus_paid.has(enemy):
		return 0
	mark_bonus_paid.append(enemy)
	return Status.spend_mark_bonus(enemy.statuses)

# What take_mark_bonus() would pay this card against `enemy`, spending
# nothing - the card face's reading of the same gate.
func mark_bonus_for(enemy: Combatant) -> int:
	if not card_is_attack or enemy == null or mark_bonus_paid.has(enemy):
		return 0
	return Status.mark_bonus(enemy.statuses)

# Every Block the player gains goes through here, so a stance that
# forbids it (Last Resort) is asked in one place. Returns what was gained.
func gain_block(amount: int) -> int:
	if amount <= 0 or Stance.prevents_block_gain(player.stance):
		return 0
	player.block += amount
	RunLogger.block_gained(amount)
	return amount

# This context for reading one card still in hand whose costs come to
# `hp_cost` - a copy, so the hand's shared context is never touched.
func for_card_preview(hp_cost: int) -> EffectContext:
	var copy := EffectContext.new()
	copy.player = player
	copy.target = target
	copy.enemies = enemies
	copy.deck = deck
	copy.cards_played_before_this = cards_played_before_this
	copy.preview_hp_cost = hp_cost
	return copy

func report_damage(target_combatant: Combatant, amount: int, kind: String) -> void:
	if on_damage.is_valid():
		on_damage.call(target_combatant, amount, kind)

# A hit on an enemy's DamagePipeline result: tells on_block if its block
# took any of it. Call before that hit's report_damage().
func report_block(target_combatant: Combatant, result: Dictionary) -> void:
	var blocked: int = result["blocked"]
	if blocked > 0 and on_block.is_valid():
		on_block.call(target_combatant, blocked, int(result["damage_to_hp"]))

# Damage this player just dealt takes Grace back 1:1, per hit as it
# lands, never past max HP and never more Grace than is left. Silent and
# free when the player has none open, which is every fight for a class
# without the passive.
# HP a card costs before its effects: the stance's per-Attack price, or
# what a cost replacement (Collateral) takes in place of Energy.
# Self-inflicted, so it takes the same route SELF_DAMAGE does: past block
# and absorb, accruing Toll, reported as "self" - and opening no Grace,
# because Grace only ever opens on an enemy's hit.
# `source` names what the price is paid to, for the run log ("stance:
# <id>", "status:<id>"); the Toll it accrues is put down to it too.
func pay_upfront_hp_cost(amount: int, source: String = "") -> void:
	if amount <= 0:
		return
	if not source.is_empty():
		RunLogger.push_source(source)
	var lost: int = DamagePipeline.apply_bypass(amount, player)
	if lost > 0:
		player.gain_self_loss_toll(lost)
		player.took_damage_this_turn = true
		# The price, split out of the "self" loss for the run log.
		RunLogger.hp_cost_paid(lost)
		report_damage(player, lost, "self")
	if not source.is_empty():
		RunLogger.pop_source()

# The Drain a self-loss counter has handed over (Combatant.pending_
# drain), resolved now, as one Drain from every enemy in reach - called
# right after anything that can lose the player HP to their own effect.
# Never on a dead player: a loss that killed them is not undone by the
# counter it completed. What it kills leaves `enemies`, and `target` when
# it was the target, so the rest of the card doesn't strike a body.
func resolve_pending_drain() -> void:
	var amount: int = player.pending_drain
	player.pending_drain = 0
	if amount <= 0 or player.hp <= 0:
		return
	if not DrainEffect.drain(amount, enemies, self):
		return
	var living: Array[Combatant] = []
	for enemy in enemies:
		if enemy.hp > 0:
			living.append(enemy)
	enemies = living
	if target != null and target.hp <= 0:
		target = null

# Heals the player and reports it. Callers mutate through this rather
# than touching hp directly, so the run's HP can't drift from the
# fight's - it silently did for HEAL before this existed.
func heal(amount: int) -> void:
	if amount <= 0:
		return
	var before: int = player.hp
	player.hp = mini(player.hp + amount, player.max_hp)
	var gained: int = player.hp - before
	if gained > 0 and on_heal.is_valid():
		on_heal.call(gained)

# Returns what it reclaimed, so a Drain on the same hit (record_hit())
# heals only the rest.
func grace_reclaim(damage_to_hp: int) -> int:
	if damage_to_hp <= 0 or player.grace <= 0:
		return 0
	var reclaimed: int = mini(damage_to_hp, player.grace)
	reclaimed = mini(reclaimed, player.max_hp - player.hp)
	if reclaimed <= 0:
		return 0
	player.grace -= reclaimed
	player.hp += reclaimed
	if on_grace_reclaimed.is_valid():
		on_grace_reclaimed.call(reclaimed)
	return reclaimed

# One hit of this card's has landed: `hp_lost` is the HP the enemy
# actually lost (its HP before less after - no overkill), `reclaimed`
# what Grace took back from that same hit. Adds the remainder to
# hp_dealt_this_card - so Grace and an Attack's Drain never both heal
# for the same point of damage.
func record_hit(hp_lost: int, reclaimed: int) -> void:
	hp_dealt_this_card += maxi(hp_lost - reclaimed, 0)
