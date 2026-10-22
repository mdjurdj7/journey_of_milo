extends RefCounted
class_name CardBonus

# The one reading of a conditional effect, shared by resolution and the
# card face. A CardEffect with a condition is one of three things, told
# apart HERE and nowhere else from its fields:
#   REPLACE - alt_value set: the condition picks alt_value over value,
#             something always resolves (Left Hand).
#   ADD     - bonus_value set: the condition adds bonus_value on top of
#             value, something always resolves (Untouched).
#   GATE    - neither: the condition decides whether the effect resolves
#             at all (With Regards' heal on a kill).
#   DRAIN   - drain_on_condition set (over alt_value): something always
#             resolves; the condition decides whether its hit drains, and
#             a met one lands alt_value when that's set, else value (Gnaw).
# resolved_value() is the number an effect lands for, given a context -
# damage_effect.gd and undamaged_block_effect.gd deal exactly this, and
# CardView prints exactly this - so the face can never promise a number
# the rules won't pay. state() is the face's LIVE/DORMANT reading of a
# whole card: over every effect whose condition can be judged before the
# card is played (TARGET_KILLED can't - it reads the card's own damage).

enum Mode { NONE, GATE, REPLACE, ADD, DRAIN }
enum State { NONE, DORMANT, LIVE }

static func mode(effect: CardEffect) -> Mode:
	if effect == null or effect.condition == CardEffect.Condition.NONE:
		return Mode.NONE
	if effect.drain_on_condition:
		return Mode.DRAIN
	if effect.alt_value != 0:
		return Mode.REPLACE
	if effect.bonus_value != 0:
		return Mode.ADD
	return Mode.GATE

# Whether the condition can be read off the battle state as it stands,
# before the card resolves.
static func previewable(effect: CardEffect) -> bool:
	if effect == null or effect.condition == CardEffect.Condition.NONE:
		return false
	return effect.condition != CardEffect.Condition.TARGET_KILLED

# Whether the effect resolves at all in this context: a GATE only when
# its condition holds; everything else always (the condition then picks
# the number instead - see resolved_value()).
static func should_resolve(effect: CardEffect, ctx: EffectContext) -> bool:
	if mode(effect) != Mode.GATE:
		return true
	return EffectResolver.condition_met(effect, ctx)

# The number the effect lands for in this context - alt_value on a met
# REPLACE, value + bonus_value on a met ADD, alt_value (when set) on a met
# DRAIN, value otherwise. Then bonus_per_chain_level for each chain level
# before the card (Severance), and bonus_per_unspent_energy for each
# Energy left once it was paid for (Patient Cut). Before any stance or
# status modifier: those are the resolver's and the face's to apply alike,
# on top of this.
static func resolved_value(effect: CardEffect, ctx: EffectContext) -> int:
	return _condition_value(effect, ctx) + chain_bonus(effect, ctx) + energy_bonus(effect, ctx.unspent_energy if ctx != null else 0)

# What the chain adds to the effect's number in this context.
static func chain_bonus(effect: CardEffect, ctx: EffectContext) -> int:
	if effect == null or ctx == null or effect.bonus_per_chain_level == 0:
		return 0
	return effect.bonus_per_chain_level * maxi(ctx.chain_level_before_this, 0)

# What `unspent` Energy, left after the card's own cost, adds to the
# effect's number.
static func energy_bonus(effect: CardEffect, unspent: int) -> int:
	if effect == null or effect.bonus_per_unspent_energy == 0:
		return 0
	return effect.bonus_per_unspent_energy * maxi(unspent, 0)

# The Energy `player` would hold once `card`, still in hand, was paid for
# now (Combatant.energy_cost() - the free card, a reduction, Critical's
# cost): what a face reads in place of EffectContext.unspent_energy.
static func unspent_energy_after(card: CardData, player: Combatant) -> int:
	if card == null or player == null:
		return 0
	return maxi(player.energy - player.energy_cost(card), 0)

static func _condition_value(effect: CardEffect, ctx: EffectContext) -> int:
	match mode(effect):
		Mode.REPLACE:
			return effect.alt_value if EffectResolver.condition_met(effect, ctx) else effect.value
		Mode.ADD:
			return effect.value + effect.bonus_value if EffectResolver.condition_met(effect, ctx) else effect.value
		Mode.DRAIN:
			return effect.alt_value if effect.alt_value != 0 and EffectResolver.condition_met(effect, ctx) else effect.value
		_:
			return effect.value

# The number the condition is FOR - what the clause prints: alt_value on
# a REPLACE, bonus_value on an ADD, alt_value (when set, else value) on a
# DRAIN, the effect's own value on a GATE.
static func bonus_value(effect: CardEffect) -> int:
	match mode(effect):
		Mode.REPLACE:
			return effect.alt_value
		Mode.ADD:
			return effect.bonus_value
		Mode.DRAIN:
			return effect.alt_value if effect.alt_value != 0 else effect.value
		_:
			return effect.value

# Whether the hit of a DAMAGE effect drains in this context: always with
# `drains`, and with drain_on_condition while its condition holds.
static func drains(effect: CardEffect, ctx: EffectContext) -> bool:
	if effect.drains:
		return true
	return mode(effect) == Mode.DRAIN and EffectResolver.condition_met(effect, ctx)

# The card's reading: LIVE if any previewable condition on it holds now,
# DORMANT if it has one and none holds, NONE if it has none - in which
# case the face shows nothing either way. A TOLL_BLOCK's all-or-nothing
# spend reads as one too (Settled Account): live while it will pay
# (TollBlockEffect.pays()).
static func state(card: CardData, ctx: EffectContext) -> State:
	if card == null or ctx == null:
		return State.NONE
	var has_condition: bool = false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.TOLL_BLOCK and ctx.player != null:
			has_condition = true
			if TollBlockEffect.pays(effect, ctx.player.toll, ctx.player.stance, ctx.player.is_critical_at(ctx.player.hp - ctx.preview_hp_cost)):
				return State.LIVE
			continue
		if not previewable(effect):
			continue
		has_condition = true
		if EffectResolver.condition_met(effect, ctx):
			return State.LIVE
	return State.DORMANT if has_condition else State.NONE

# The HP `card` will have paid before its first conditional or damage
# effect reads anything - what state() is judged against, through
# EffectContext.for_card_preview(): `replaced_hp` (a cost replacement's,
# Collateral - paid before any effect, see EffectResolver.resolve_card()),
# the stance's per-Attack price, and the card's own self-loss authored
# ahead of its conditions (In the Red's 8). Self-loss authored after
# (Bite Down's, Last Wager's - the Wanderer's attack-then-pay convention)
# is paid too late to count. The card face and the play sound both ask
# here, so the sound is lifted exactly when the face shows the clause live.
#
# The effects that end the count: every damage type (CardView.DAMAGE_
# EFFECT_TYPES) and Reckoning's TOLL_SPENT_DAMAGE.
const HP_COST_STOPS: Array = [CardEffect.EffectType.DAMAGE, CardEffect.EffectType.FIRST_CARD_DAMAGE,
	CardEffect.EffectType.DAMAGE_ALL, CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE, CardEffect.EffectType.TOLL_SPENT_DAMAGE]

static func upfront_hp_cost(card: CardData, stance: Stance, replaced_hp: int) -> int:
	if card == null:
		return 0
	var total: int = replaced_hp
	if card.card_type == CardData.CardType.ATTACK:
		total += Stance.attack_hp_loss(stance)
	for effect in card.effects:
		if effect == null:
			continue
		if effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL:
			total += effect.value
			continue
		if effect.condition != CardEffect.Condition.NONE or HP_COST_STOPS.has(effect.effect_type):
			break
	return total

# All the HP playing `card` now will cost the player - every self-inflicted
# loss, predicted from the card's data and the fight as `ctx` holds it
# (BattleController.preview_context()), nothing resolved. In the order
# EffectResolver.resolve_card() pays it: a cost replacement's HP
# (Collateral - Combatant.replaced_cost_hp(); a price that kills ends the
# card), the stance's price on an Attack with something to hit, then each
# SELF_DAMAGE (can kill) and SELF_DAMAGE_TOLL (never below 1 HP) in the
# card's order, gated as the resolver gates them, judged at the HP already
# paid. A REPLAY_LAST_ATTACK (Second Swing) adds the replayed Attack's own
# stance price and self-loss - never its Collateral. Each payment is
# clamped to the HP left, so the total never passes the HP held. Not
# counted: heals mid-card (Drain, The Return) and enemy blows (Coiled).
# With no player (outside a fight) it is the card's printed self-loss.
# The card's HP badge and the HP bar's preview both read this.
static func predicted_self_loss(card: CardData, ctx: EffectContext) -> int:
	if card == null:
		return 0
	if ctx == null or ctx.player == null:
		return printed_self_loss(card)
	var start: int = maxi(ctx.player.hp, 0)
	var hp: int = start - mini(maxi(ctx.player.replaced_cost_hp(card), 0), start)
	if hp > 0:
		hp = _hp_after_self_loss(card, ctx, hp, start, true)
	return start - hp

# The sum of the card's own SELF_DAMAGE / SELF_DAMAGE_TOLL values, as
# printed - no stance, no clamp.
static func printed_self_loss(card: CardData) -> int:
	var total: int = 0
	if card == null:
		return total
	for effect in card.effects:
		if effect != null and (effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL):
			total += maxi(effect.value, 0)
	return total

# The HP left after `card`'s stance price and own self-loss, from `hp`
# (`start` the HP before the play). `may_replay`: a replay's own replay
# effect doesn't replay again.
static func _hp_after_self_loss(card: CardData, ctx: EffectContext, hp: int, start: int, may_replay: bool) -> int:
	if card.card_type == CardData.CardType.ATTACK and not ctx.enemies.is_empty():
		hp -= mini(maxi(Stance.attack_hp_loss(ctx.player.stance), 0), hp)
	for effect in card.effects:
		if effect == null or not should_resolve(effect, ctx.for_card_preview(start - hp)):
			continue
		match effect.effect_type:
			CardEffect.EffectType.SELF_DAMAGE:
				hp -= mini(maxi(effect.value, 0), hp)
			CardEffect.EffectType.SELF_DAMAGE_TOLL:
				hp -= clampi(effect.value, 0, maxi(hp - 1, 0))
			CardEffect.EffectType.REPLAY_LAST_ATTACK:
				# Replayed at what it was played at (BattleController.
				# _replay_attack()): an all-enemies Attack while anything
				# can be hit, else only while its target still stands.
				var replayed: CardData = ctx.player.last_attack
				var before: Combatant = ctx.player.last_attack_target
				var lands: bool = not ctx.enemies.is_empty() if ctx.player.last_attack_all else (before != null and before.hp > 0 and ctx.enemies.has(before))
				if may_replay and replayed != null and lands:
					hp = _hp_after_self_loss(replayed, ctx, hp, start, false)
	return hp
