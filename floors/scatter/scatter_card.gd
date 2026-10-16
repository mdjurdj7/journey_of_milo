extends Resource
class_name ScatterCard

# One painted card a ScatterEntry can draw an item with - a dune-grass tuft:
# a transparent PNG, its base on the image's bottom edge, stood up as a
# flat card at its real height (its width follows the image's aspect) and
# drawn by tuft_card.gdshader (FieldScatter). An entry with cards picks
# one per item, at random by weight, so one cluster mixes them.

@export_file("*.png") var texture_path: String = "":
	set(value):
		texture_path = value
		emit_changed()
# The tallest blade, metres, at a scale of 1 - the image's full height.
@export var height_m: float = 0.3:
	set(value):
		height_m = value
		emit_changed()
# How often it is picked against the entry's other cards.
@export var weight: float = 1.0:
	set(value):
		weight = value
		emit_changed()
