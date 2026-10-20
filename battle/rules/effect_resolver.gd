extends RefCounted
class_name EffectResolver

# Registry, not a switch: each CardEffect.EffectType maps to a small
# script under battle/rules/effects/ implementing resolve(effect, ctx).
# Three old type names collapse onto DAMAGE's own script (see damage_
# effect.gd) - they're kept as distinct enum values so old-style
# authoring still reads correctly, but every one of them resolves
# identically to a plain DAMAGE effect with the right condition/
# target_scope set.
const EFFECT_SCRIPT_PATHS: Dictionary = {
	CardEffect.EffectType.DAMAGE: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.FIRST_CARD_DAMAGE: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.DAMAGE_ALL: "res://battle/rules/effects/damage_effect.gd",
	CardEffect.EffectType.BLOCK: "res://battle/rules/effects/block_effect.gd",
	CardEffect.EffectType.SELF_DAMAGE: "res://battle/rules/effects/self_damage_effect.gd",
	CardEffect.EffectType.DRAW: "res://battle/rules/effects/draw_effect.gd",
	CardEffect.EffectType.HEAL: "res://battle/rules/effects/heal_effect.gd",
	CardEffect.EffectType.STUN: "res://battle/rules/effects/stun_effect.gd",
	CardEffect.EffectType.TOLL_BLOCK: "res://battle/rules/effects/toll_block_effect.gd",
	CardEffect.EffectType.TOLL_RETALIATE: "res://battle/rules/effects/toll_retaliate_effect.gd",
	CardEffect.EffectType.SELF_DAMAGE_TOLL: "res://battle/rules/effects/self_damage_toll_effect.gd",
	CardEffect.EffectType.APPLY_STATUS: "res://battle/rules/effects/apply_status_effect.gd",
	CardEffect.EffectType.TOLL_FRACTION_DAMAGE_ALL: "res://battle/rules/effects/toll_fraction_damage_all_effect.gd",
	CardEffect.EffectType.UNDAMAGED_BLOCK: "res://battle/rules/effects/undamaged_block_effect.gd",
	CardEffect.EffectType.GAIN_ENERGY: "res://battle/rules/effects/gain_energy_effect.gd",
	CardEffect.EffectType.ABSORB: "res://battle/rules/effects/absorb_effect.gd",
	CardEffect.EffectType.APPLY_STATUS_TO_TARGET: "res://battle/rules/effects/apply_status_to_target_effect.gd",
	CardEffect.EffectType.APPLY_STANCE: "res://battle/rules/effects/apply_stance_effect.gd",
	CardEffect.EffectType.TOLL_HEAL: "res://battle/rules/effects/toll_heal_effect.gd",
	CardEffect.EffectType.SPEND_TOLL: "res://battle/rules/effects/spend_toll_effect.gd",
	CardEffect.EffectType.DRAIN: "res://battle/rules/effects/drain_effect.gd",
	CardEffect.EffectType.REPLAY_LAST_ATTACK: "res://battle/rules/effects/replay_last_attack_effect.gd",
	CardEffect.EffectType.GRANT_KEEP: "res://battle/rules/effects/grant_keep_effect.gd",
	CardEffect.EffectType.COPY_HAND_CARD: "res://battle/rules/effects/copy_hand_card_effect.gd",
	CardEffect.EffectType.UNDO_LAST_ATTACK: "res://battle/rules/effects/undo_last_attack_effect.gd",
	CardEffect.EffectType.TOLL_SPENT_DAMAGE: "res://battle/rules/effects/toll_spent_damage_effect.gd",
}

var _cache: Dictionary = {}

# The stance's price is paid BEFORE the card's own effects: an Attack pays
# it as part of being played. The bonus is NOT fixed here - the card's
# first damage effect takes it as it lands (EffectContext.take_attack_
# bonus()), so Critical is judged after everything the card paid first.
# A card that isn't an ATTACK pays and gets nothing, which is how a stance
# card can be played while a stance is already up without charging for
# itself. Nor does an Attack with nothing it can hit - every enemy buried
# (ctx.enemies is only the hittable ones): the stance's HP isn't paid
# into immunity.
func resolve_card(card: CardData, ctx: EffectContext) -> void:
	# Per card, not per effect: "if this kills" means this CARD's own
	# damage, so a kill from the card before must not still be standing.
	ctx.killed_this_card = false
	ctx.card_is_attack = card.card_type == CardData.CardType.ATTACK
	ctx.attack_bonus_taken = false
	ctx.toll_spent_this_card = false
	ctx.hp_dealt_this_card = 0
	ctx.attack_card_extra_this_card = 0
	# A cost replacement's HP (Collateral), first of all - it is this
	# card's price. A price that kills ends the card: none of its effects
	# resolve, and the fight ends as a defeat.
	if ctx.replaced_cost_hp > 0:
		ctx.pay_upfront_hp_cost(ctx.replaced_cost_hp, ctx.replaced_cost_source)
		ctx.resolve_pending_drain()
		if ctx.player.hp <= 0:
			return
	if ctx.card_is_attack and ctx.player.stance != null and not ctx.enemies.is_empty():
		var stance_id: String = ctx.player.stance.data.id if ctx.player.stance.data != null else ""
		ctx.pay_upfront_hp_cost(Stance.attack_hp_loss(ctx.player.stance), "stance:" + stance_id)
		# The price can be the loss that sets off a counter (The Return):
		# its Drain lands now, before the Attack it was paid for.
		ctx.resolve_pending_drain()
	for effect in card.effects:
		# The gate lives HERE, not in each resolver - it used to be checked
		# only inside damage_effect.gd, so a condition on any other effect
		# type was silently ignored (With Regards' energy paid out whether
		# or not the blow killed). A REPLACE or an ADD still goes through:
		# its condition chooses a number rather than whether to resolve at
		# all - CardBonus tells the three apart and hands each resolver
		# the number (CardBonus.resolved_value()).
		if not CardBonus.should_resolve(effect, ctx):
			continue
		var resolver: Object = _get_resolver(effect.effect_type)
		if resolver != null:
			resolver.resolve(effect, ctx)
		# Straight after the loss that set a counter off, before the next
		# effect - Blood Arc's Drain lands before its own sweep.
		ctx.resolve_pending_drain()
	# An Attack's last effect done: what waits for an Attack card to finish
	# (Bent Nail's doubling) spends now - after every hit it gave. Not on a
	# replay (Second Swing): that card was played before, and isn't now.
	if ctx.card_is_attack and not ctx.is_replay:
		for spent_id in Status.spend_on_attack_card(ctx.player.statuses):
			RunLogger.mechanic("keepsake_double", {"card": card.card_name, "status": spent_id, "extra": ctx.attack_card_extra_this_card})
	# After the whole card, once however much it spent: Toll spent hurries
	# every countdown that listens for it (Sentence), and one that reaches
	# 0 goes off now, in the player's turn - reported as damage, never as
	# the card's own blow.
	# The run log puts each step down to what spent the Toll - the card, or
	# a replay ("replay:<attack>").
	if ctx.toll_spent_this_card:
		for enemy in ctx.status_holders():
			for left in Status.advance_on_toll_spend(enemy):
				RunLogger.mechanic("sentence_advance", {"enemy": RunLogger.combatant_id(enemy), "turns_left": left, "source": RunLogger.current_source()})
			var taken: int = Status.resolve_countdowns(enemy)
			if taken > 0:
				RunLogger.mechanic("sentence_resolved", {"enemy": RunLogger.combatant_id(enemy), "damage": taken, "by": "spend"})
				ctx.report_damage(enemy, taken, "status")
	# After the card's last effect, once: an Attack played while its
	# Attacks Drain (Ransom) heals its share (StatusData.ransom_heal_
	# fraction, rounded down) of what its own hits took, net of Grace
	# (EffectContext.record_hit()) - all of them summed for an all-enemies
	# Attack. Never a countdown going off or a counter's Drain: neither is
	# the Attack's blow. Before the Critical triggers below, so a heal that
	# lifts the player out of Critical is seen there. The run log puts the
	# heal down to the card that granted the Drain, with this Attack as its
	# trigger (RunLogger.player_healed()).
	if ctx.card_is_attack and Status.attacks_drain(ctx.player.statuses):
		RunLogger.push_source(Status.attacks_drain_source(ctx.player.statuses))
		ctx.heal(floori(float(ctx.hp_dealt_this_card) * Status.attacks_drain_fraction(ctx.player.statuses)))
		RunLogger.pop_source()
	# The skillchain the play's chain link fired (Skillchain), after the
	# card's own effects and what waits on an Attack's blows: a Lunge is
	# no Attack's blow, so it takes no attack bonus and nothing an Attack
	# spends or Drains.
	if ctx.skillchain != &"" and not ctx.is_replay:
		_fire_skillchain(card, ctx)
	# After the whole card: its own HP cost (self-damage, the stance's
	# price) may have made the player Critical, and a status waiting for
	# that (No Further) gives way now - as does one this card just applied
	# while they were already there.
	Status.resolve_critical_triggers(ctx.player)

# Whether the rules forbid playing this card right now, whatever its
# energy: it spends a fixed Toll the player doesn't hold (SPEND_TOLL - Come
# Due). Read by BattleController.
# request_play() and by the hand, which fades the card - so a copy that
# can't be paid for shows it rather than being taken and doing nothing.
# Whether `card` may land on `combatant`: living and not buried, and - for
# a card that skips its target's turn (Deny) - not one already holding
# that status, since it doesn't stack. And taunt (StatusData.taunts - the
# Glower's Inflated): while any of `enemies` - the fight's, living and
# unburied - is taunting, an Attack card aimed at one enemy may land only
# on a taunting one. An area Attack has no target to ask about, and an
# enemy-target Skill (Brace, Sentence) goes where it likes. Killing the
# taunter lifts it at once. BattleController's targeting and the hand's
# fade both ask here.
static func can_target(card: CardData, combatant: Combatant, enemies: Array[Combatant] = []) -> bool:
	if combatant == null or combatant.hp <= 0 or combatant.buried:
		return false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS_TO_TARGET and effect.status_data != null and effect.status_data.skips_next_turn:
			if Status.skip_turn_status(combatant.statuses) != null:
				return false
		# Deny: not on one whose next action is held already.
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS_TO_TARGET and effect.status_data != null and effect.status_data.delays_next_action:
			if Status.delay_status(combatant.statuses) != null:
				return false
		# A card that marks an intent (Brace, Garnish) targets the enemy's
		# queued intent: only an attack that will land, carrying none of
		# the same mark yet (EnemyTurn.mark_refusal()).
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS_TO_TARGET and effect.status_data != null and effect.status_data.intent_mark != &"":
			if EnemyTurn.mark_refusal(combatant, combatant.enemy_data, effect.status_data) != EnemyTurn.MarkRefusal.NONE:
				return false
	if card.card_type == CardData.CardType.ATTACK and card.target_type == CardData.TargetType.ENEMY and not is_taunting(combatant):
		for other in enemies:
			if other != null and other != combatant and other.hp > 0 and not other.buried and is_taunting(other):
				return false
	return true

# Whether any of `enemies` is one `card` may land on.
static func has_target(card: CardData, enemies: Array[Combatant]) -> bool:
	for combatant in enemies:
		if can_target(card, combatant, enemies):
			return true
	return false

# Whether `combatant` holds a status that taunts (StatusData.taunts).
static func is_taunting(combatant: Combatant) -> bool:
	for active: Status in combatant.statuses:
		if active.data != null and active.data.taunts:
			return true
	return false

# The hand cards `card` may copy (COPY_HAND_CARD - Countersign): every
# other card in `hand` but one that copies itself - Countersign never
# copies a Countersign. Empty for a card that copies nothing, too. With
# none, the controller and the hand's fade both refuse the card.
static func copy_targets(card: CardData, hand: Array[CardData]) -> Array[CardData]:
	var targets: Array[CardData] = []
	if card == null or not copies_hand_card(card):
		return targets
	for other in hand:
		if other != card and other != null and not copies_hand_card(other):
			targets.append(other)
	return targets

static func copies_hand_card(card: CardData) -> bool:
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.COPY_HAND_CARD:
			return true
	return false

# Also a card applying a status the player already holds that allows one
# at a time (StatusData.blocks_reapply_while_held - Dying Light).
static func card_blocked(card: CardData, player: Combatant) -> bool:
	if card == null or player == null:
		return false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.SPEND_TOLL and player.toll < effect.toll_cost:
			return true
		# Nothing to undo: no enemy attack on the record not yet undone (Not So).
		if effect != null and effect.effect_type == CardEffect.EffectType.UNDO_LAST_ATTACK and player.last_undoable_hit().is_empty():
			return true
		# Nothing to play again: no Attack played this turn (Second Swing).
		if effect != null and effect.effect_type == CardEffect.EffectType.REPLAY_LAST_ATTACK and player.last_attack == null:
			return true
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS and effect.status_data != null and effect.status_data.blocks_reapply_while_held and Status.find_in(player.statuses, effect.status_data) != null:
			return true
	return false

# ctx.skillchain at ctx.skillchain_level, through the effect script its
# payoff names - so its Block, draw and damage report as a card's do. A
# Lunge whose target is down (the card's own blow killed it) fizzles.
func _fire_skillchain(card: CardData, ctx: EffectContext) -> void:
	var effect: CardEffect = Skillchain.payoff(ctx.skillchain, ctx.skillchain_level, ctx.player)
	var fizzled: bool = effect == null or (ctx.skillchain == Skillchain.LUNGE and not Skillchain.target_standing(ctx.target))
	RunLogger.mechanic("skillchain", {"link": String(ctx.skillchain), "level": ctx.skillchain_level, "card": card.card_name, "fizzled": fizzled})
	if fizzled:
		return
	var was_attack: bool = ctx.card_is_attack
	ctx.card_is_attack = false
	var resolver: Object = _get_resolver(effect.effect_type)
	if resolver != null:
		resolver.resolve(effect, ctx)
	ctx.card_is_attack = was_attack
	ctx.resolve_pending_drain()

func _get_resolver(effect_type: CardEffect.EffectType) -> Object:
	if _cache.has(effect_type):
		return _cache[effect_type]
	var path: String = EFFECT_SCRIPT_PATHS.get(effect_type, "")
	if path == "":
		push_error("EffectResolver: no resolver registered for effect type %d" % effect_type)
		return null
	var instance: Object = load(path).new()
	_cache[effect_type] = instance
	return instance

static func condition_met(effect: CardEffect, ctx: EffectContext) -> bool:
	match effect.condition:
		CardEffect.Condition.NONE:
			return true
		CardEffect.Condition.TOLL_AT_LEAST:
			return ctx.player.toll >= int(effect.condition_value)
		CardEffect.Condition.HP_BELOW_PERCENT:
			return ctx.player.hp < ctx.player.max_hp * (effect.condition_value / 100.0)
		CardEffect.Condition.FIRST_CARD_THIS_TURN:
			return ctx.cards_played_before_this == 0
		CardEffect.Condition.TARGET_KILLED:
			return ctx.killed_this_card
		CardEffect.Condition.HAS_GRACE:
			return ctx.player.grace > 0
		CardEffect.Condition.UNDAMAGED_LAST_TURN:
			return not ctx.player.took_damage_last_turn
		CardEffect.Condition.CRITICAL:
			return ctx.player.is_critical_at(ctx.player.hp - ctx.preview_hp_cost)
		CardEffect.Condition.TOLL_SPENT_THIS_TURN:
			return ctx.player.toll_spent_this_turn
	return true
