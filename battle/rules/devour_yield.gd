extends RefCounted
class_name DevourYield

# What a card Devoured by the keyword gives (Take In - DEVOUR_FROM_HAND):
# the one place it is worked out, so the line the hand shows over a
# candidate while choosing (describe()) and what the Devour puts on the
# player (apply()) both read of() and can't disagree. A card's own "When
# Devoured" text, when one exists, is answered here too.
#
# For each Energy of the eaten card's PRINTED cost (CardData.cost - never
# a discount, a free card or a replacement), `per_energy` of:
#   an Attack  Teeth: your Attacks deal that much more this fight - every
#              hit, a Lash's repeats too (StatusData.attack_damage_bonus,
#              no charges: AttackBonus pays it to each)
#   a Skill    Marrow: that much Block at the start of each of your turns
#              (StatusData.turn_start_block)
# One stack per point, so the status row reads the total ("Teeth ×4").
# A 0-cost card, a Power and a Stance yield nothing. Never the Devour
# button's: that heals and yields nothing (BattleController.devour()).

enum Kind { NOTHING, ATTACK, BLOCK }

const TEETH_PATH := "res://battle/rules/statuses/teeth.tres"
const MARROW_PATH := "res://battle/rules/statuses/marrow.tres"

# The yield of eating `card`: {"kind": Kind, "amount": int} - amount 0
# with NOTHING.
static func of(card: CardData, per_energy: int) -> Dictionary:
	var result: Dictionary = {"kind": Kind.NOTHING, "amount": 0}
	if card == null:
		return result
	var amount: int = maxi(card.cost, 0) * maxi(per_energy, 0)
	if amount <= 0:
		return result
	match card.card_type:
		CardData.CardType.ATTACK:
			result = {"kind": Kind.ATTACK, "amount": amount}
		CardData.CardType.SKILL:
			result = {"kind": Kind.BLOCK, "amount": amount}
	return result

# The yield in a line, as the hand shows it over a candidate: "+N damage
# this combat", "+N Block each turn" or "Nothing".
static func describe(card: CardData, per_energy: int) -> String:
	var yielded: Dictionary = of(card, per_energy)
	match int(yielded["kind"]):
		Kind.ATTACK:
			return "+%d damage this combat" % int(yielded["amount"])
		Kind.BLOCK:
			return "+%d Block each turn" % int(yielded["amount"])
	return "Nothing"

# The yield put on `player`: Teeth or Marrow, a stack per point. Returns
# what of() said - what was applied.
static func apply(card: CardData, per_energy: int, player: Combatant) -> Dictionary:
	var yielded: Dictionary = of(card, per_energy)
	var path: String = ""
	match int(yielded["kind"]):
		Kind.ATTACK:
			path = TEETH_PATH
		Kind.BLOCK:
			path = MARROW_PATH
	if path.is_empty() or player == null:
		return yielded
	var status_data := load(path) as StatusData
	if status_data == null:
		push_error("DevourYield: %s failed to load - nothing yielded." % path)
		return {"kind": Kind.NOTHING, "amount": 0}
	for point in int(yielded["amount"]):
		Status.apply_to(player.statuses, status_data)
	return yielded

# The kind's name for the run log: "attack", "block" or "nothing".
static func kind_name(kind: int) -> String:
	match kind:
		Kind.ATTACK:
			return "attack"
		Kind.BLOCK:
			return "block"
	return "nothing"
