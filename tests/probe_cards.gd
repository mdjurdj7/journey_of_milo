class_name ProbeCards
extends RefCounted

# Card numbers for probes, read from the .tres the game reads - so a probe
# that needs what Slash deals, what Self-Eater adds or where Critical
# starts asks here instead of writing the number down, and a retune moves
# the probe with the card. Each reads the data or calls the rule itself;
# none restates a rule. `tempered` reads the + card (CardData.tempered).

const SLASH_PATH := "res://cards/data/slash.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const LAST_RESORT_PATH := "res://cards/data/last_resort.tres"
const SENTENCE_PATH := "res://cards/data/sentence.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"

static func card(path: String, tempered: bool = false) -> CardData:
	var data: CardData = load(path) as CardData
	return data.tempered if tempered else data

# What Slash's hit is printed for.
static func slash_damage(tempered: bool = false) -> int:
	for effect in card(SLASH_PATH, tempered).effects:
		if effect.effect_type == CardEffect.EffectType.DAMAGE:
			return effect.value
	return -1

# What Self-Eater's stance adds to each Attack, and what it charges for one.
static func self_eater_bonus(tempered: bool = false) -> int:
	return _stance(SELF_EATER_PATH, tempered).attack_damage_bonus

static func self_eater_hp_loss(tempered: bool = false) -> int:
	return _stance(SELF_EATER_PATH, tempered).attack_hp_loss

# What Last Resort's stance adds to each Attack while Critical.
static func last_resort_bonus(tempered: bool = false) -> int:
	return _stance(LAST_RESORT_PATH, tempered).attack_damage_bonus

# The turns Sentence's countdown starts at, and what it deals at 0.
static func sentence_turns(tempered: bool = false) -> int:
	return _status(SENTENCE_PATH, tempered).default_duration_turns

static func sentence_damage(tempered: bool = false) -> int:
	return _status(SENTENCE_PATH, tempered).countdown_damage

# The highest HP that's Critical at `max_hp` and `fraction` - asked of
# Combatant.critical_at(), the rule itself. -1 when none is.
static func critical_line(max_hp: int, fraction: float) -> int:
	for hp in range(max_hp, -1, -1):
		if Combatant.critical_at(hp, max_hp, fraction):
			return hp
	return -1

# `amount` as it lands on a Braced target - through Status.apply_modifiers(),
# the rule itself, with one fresh Braced.
static func braced(amount: int) -> int:
	var data: StatusData = load(BRACED_PATH) as StatusData
	var statuses: Array[Status] = [Status.new(data)]
	return Status.apply_modifiers(amount, statuses, data.modifier_target)

static func _stance(path: String, tempered: bool) -> StanceData:
	for effect in card(path, tempered).effects:
		if effect.stance_data != null:
			return effect.stance_data
	return null

static func _status(path: String, tempered: bool) -> StatusData:
	for effect in card(path, tempered).effects:
		if effect.status_data != null:
			return effect.status_data
	return null
