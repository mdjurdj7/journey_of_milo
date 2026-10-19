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
# DRAIN, value otherwise. Before any stance or status modifier: those are
# the resolver's and the face's to apply alike, on top of this.
static func resolved_value(effect: CardEffect, ctx: EffectContext) -> int:
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

# The card's reading: LIVE if any previewable condition on it holds now,
# DORMANT if it has one and none holds, NONE if it has none - in which
# case the face shows nothing either way.
# Whether the hit of a DAMAGE effect drains in this context: always with
# `drains`, and with drain_on_condition while its condition holds.
static func drains(effect: CardEffect, ctx: EffectContext) -> bool:
	if effect.drains:
		return true
	return mode(effect) == Mode.DRAIN and EffectResolver.condition_met(effect, ctx)

static func state(card: CardData, ctx: EffectContext) -> State:
	if card == null or ctx == null:
		return State.NONE
	var has_condition: bool = false
	for effect in card.effects:
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
# EFFECT_TYPES) and Reckoning's TOLL_DAMAGE.
const HP_COST_STOPS: Array = [CardEffect.EffectType.DAMAGE, CardEffect.EffectType.FIRST_CARD_DAMAGE,
	CardEffect.EffectType.DAMAGE_ALL, CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE, CardEffect.EffectType.TOLL_DAMAGE]

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
