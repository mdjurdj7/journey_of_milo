extends RefCounted
class_name WeightedRandom
# A small reusable helper for "pick one option out of several, unevenly
# likely" - the technique reward_screen.gd's rarity roll and
# room_state.gd's room-type roll both need, extracted here now that a
# third use (combat room blob count) needs the exact same thing.
#
# The idea: line up every option's weight end-to-end on a number line
# from 0 up to the total of all weights, then drop a random point
# somewhere on that line. Whichever option's stretch the point lands in
# is the result - an option with double the weight of another covers
# double the distance, so it's twice as likely to be hit. Walking the
# dictionary and subtracting each weight from the roll in turn is just a
# way to find "which stretch did the point land in" without actually
# building the number line as data.

static func pick(weights: Dictionary) -> Variant:
	var total := 0.0
	for weight in weights.values():
		total += weight
	var roll := randf() * total
	for option in weights:
		roll -= weights[option]
		if roll < 0.0:
			return option
	return weights.keys()[0] # Unreachable outside float rounding at the very top edge.
