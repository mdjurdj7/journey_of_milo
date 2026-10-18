extends Resource
class_name BedrollData

# The Bedroll: a single-use rest, class-neutral. The run carries at most
# one (RunState.has_bedroll); the field HUD shows it while it's carried
# (BedrollLine), and using it on the field - never in a fight, never at
# full HP - rests the Wanderer (BedrollRest): heal_fraction of his max
# HP, rounded down, capped at the max, and it's gone. One of these,
# run/data/bedroll.tres, read by everything that shows or uses it.

# The share of max HP a rest restores, rounded down.
@export_range(0.0, 1.0, 0.01) var heal_fraction: float = 0.3
# The HUD row's item, in the row's tracked caps.
@export var hud_label: String = "BEDROLL"
# The HUD item's hover: "<hover_name>: <hover_text>", {percent} the
# heal_fraction as a whole percent.
@export var hover_name: String = "Rest"
@export var hover_text: String = "restore {percent}% of your max HP. One use."
# Beside an offer of one while one is carried - it can't be taken then.
@export var carrying_text: String = "(carrying one)"
# Its item plate (ItemPlate.set_bedroll() - the belongings offer's hover):
# the plate's name, and its effect line, {percent} as above - saying it is
# a rest item, used in the field.
@export var plate_name: String = "Bedroll"
@export var plate_text: String = "Use anywhere in the field, outside battle: restore {percent}% of your max HP. One use."

# hover_text with its number in.
func describe() -> String:
	return hover_text.replace("{percent}", str(roundi(heal_fraction * 100.0)))

# plate_text with its number in.
func describe_plate() -> String:
	return plate_text.replace("{percent}", str(roundi(heal_fraction * 100.0)))

# What a rest restores at `max_hp`: heal_fraction of it, rounded down -
# the hair over the product keeps 0.3 of 80 at 24 whatever the float.
func heal_amount(max_hp: int) -> int:
	return maxi(floori(float(maxi(max_hp, 0)) * heal_fraction + 0.000001), 0)
