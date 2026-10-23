extends RefCounted
class_name NumberBreakdown

# One number and every source outside the card that moved it, in the
# order they did: the card's own number (`base` - its value, with its own
# Chain and Energy scaling already in), then each item, stance and status
# with exactly what it changed the running total by. The rules' scalar
# sums are these parts added up (Stance.attack_bonus(), Status.attack_
# bonus(), Status.apply_modifiers(), DamageEffect.landed()), so the number
# a card lands for, the number its face prints and the breakdown its face
# explains can't disagree.
#
# A MULTIPLY part keeps the amount it actually added once rounded, so the
# parts always sum to `total`; FLOOR is the clamp at 0 that ends a run of
# modifiers, and NO_BLOCK a stance taking Block to 0 (Last Resort).

enum Op { ADD, MULTIPLY, FLOOR, NO_BLOCK }

class Part:
	var source: String = ""
	var op: Op = Op.ADD
	# What this part changed the running total by.
	var amount: int = 0
	# MULTIPLY: the percentage it added (-50 halves).
	var percent: int = 0

var base: int = 0
# What the base is, when it isn't a number printed on the card - "Toll
# spent" on Reckoning's. Empty for a printed number.
var base_label: String = ""
var parts: Array[Part] = []
var total: int = 0

func _init(start: int = 0, label: String = "") -> void:
	base = start
	base_label = label
	total = start

# `amount` more from `source`. Recorded even at 0, so two breakdowns run
# over the same sources stay part for part (difference()).
func add(source: String, amount: int) -> NumberBreakdown:
	_append(source, Op.ADD, amount, 0)
	return self

# `percent`% of the running total more from `source`, rounded as the
# modifiers always have been.
func multiply(source: String, percent: int) -> NumberBreakdown:
	_append(source, Op.MULTIPLY, roundi(total * percent / 100.0), percent)
	return self

# The clamp at 0 a run of modifiers ends on.
func floor_at_zero() -> NumberBreakdown:
	_append("", Op.FLOOR, maxi(-total, 0), 0)
	return self

# `source` takes the whole number to 0.
func zero(source: String) -> NumberBreakdown:
	_append(source, Op.NO_BLOCK, -total, 0)
	return self

# What the sources added up to.
func change() -> int:
	return total - base

# Whether anything outside the card moved the number it shows.
func differs() -> bool:
	return total != base

# `with_it` less `without_it`, part by part, on `start`: what a clause adding
# to a hit puts on it once both are through the same sources. The two must
# have been run over the same sources in the same order.
static func difference(with_it: NumberBreakdown, without_it: NumberBreakdown, start: int) -> NumberBreakdown:
	var out := NumberBreakdown.new(start)
	for i in mini(with_it.parts.size(), without_it.parts.size()):
		var a: Part = with_it.parts[i]
		out._append(a.source, a.op, a.amount - without_it.parts[i].amount, a.percent)
	# Whatever the parts don't account for (none, when the two ran alike).
	var rest: int = (with_it.total - without_it.total) - out.total
	if rest != 0:
		out._append("", Op.FLOOR, rest, 0)
	return out

# The slip's line: "6 · Gaff Hook +3 · = 9", "Toll spent 13 · Whetstone
# +2 · = 15". A part that moved nothing, and the bare clamp, say nothing.
func describe() -> String:
	var terms := PackedStringArray()
	terms.append(str(base) if base_label.is_empty() else "%s %d" % [base_label, base])
	for part in parts:
		if part.amount == 0 or part.source.is_empty():
			continue
		terms.append("%s %s" % [part.source, _operation_text(part)])
	terms.append("= %d" % total)
	return " · ".join(terms)

func _append(source: String, op: Op, amount: int, percent: int) -> void:
	var part := Part.new()
	part.source = source
	part.op = op
	part.amount = amount
	part.percent = percent
	parts.append(part)
	total += amount

static func _operation_text(part: Part) -> String:
	match part.op:
		Op.MULTIPLY:
			return "×" + _factor_text(100 + part.percent)
		Op.NO_BLOCK:
			return "×0"
		_:
			return ("+%d" % part.amount) if part.amount >= 0 else ("−%d" % -part.amount)

# A factor in hundredths as the face writes it: 2, ½, 1½, ¾, 0 - a
# decimal where no vulgar fraction fits.
static func _factor_text(hundredths: int) -> String:
	@warning_ignore("integer_division")
	var whole: int = hundredths / 100
	var rest: int = hundredths % 100
	var fraction: String = ""
	match rest:
		0:
			return str(whole)
		25:
			fraction = "¼"
		50:
			fraction = "½"
		75:
			fraction = "¾"
		_:
			return String.num(hundredths / 100.0, 2)
	return fraction if whole == 0 else str(whole) + fraction
