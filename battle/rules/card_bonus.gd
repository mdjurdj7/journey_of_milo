extends RefCounted
class_name CardBonus

# The one reading of a conditional effect, shared by resolution and the
# card face. A CardEffect with a condition is one of three things, told
# apart HERE and nowhere else from its fields:
#   REPLACE - alt_value set: the condition picks alt_value over value,
#             something always resolves (Left Hand, Reprisal).
#   ADD     - bonus_value set: the condition adds bonus_value on top of
#             value, something always resolves (Untouched).
#   GATE    - neither: the condition decides whether the effect resolves
#             at all (With Regards' energy on a kill).
# resolved_value() is the number an effect lands for, given a context -
# damage_effect.gd and undamaged_block_effect.gd deal exactly this, and
# CardView prints exactly this - so the face can never promise a number
# the rules won't pay. state() is the face's LIVE/DORMANT reading of a
# whole card: over every effect whose condition can be judged before the
# card is played (TARGET_KILLED can't - it reads the card's own damage).

enum Mode { NONE, GATE, REPLACE, ADD }
enum State { NONE, DORMANT, LIVE }

static func mode(effect: CardEffect) -> Mode:
	if effect == null or effect.condition == CardEffect.Condition.NONE:
		return Mode.NONE
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
# REPLACE, value + bonus_value on a met ADD, value otherwise. Before any
# stance or status modifier: those are the resolver's and the face's to
# apply alike, on top of this.
static func resolved_value(effect: CardEffect, ctx: EffectContext) -> int:
	match mode(effect):
		Mode.REPLACE:
			return effect.alt_value if EffectResolver.condition_met(effect, ctx) else effect.value
		Mode.ADD:
			return effect.value + effect.bonus_value if EffectResolver.condition_met(effect, ctx) else effect.value
		_:
			return effect.value

# The number the condition is FOR - what the clause prints: alt_value on
# a REPLACE, bonus_value on an ADD, the effect's own value on a GATE.
static func bonus_value(effect: CardEffect) -> int:
	match mode(effect):
		Mode.REPLACE:
			return effect.alt_value
		Mode.ADD:
			return effect.bonus_value
		_:
			return effect.value

# The card's reading: LIVE if any previewable condition on it holds now,
# DORMANT if it has one and none holds, NONE if it has none - in which
# case the face shows nothing either way.
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
