extends Resource
class_name FightRarityStep

# One line of a FightRarityTable: from this floor of the region on
# (1 = its first), a normal fight's card offer rolls with these rates.

@export var from_floor: int = 1:
	set(value):
		from_floor = value
		emit_changed()
@export var rates: RarityRates = null:
	set(value):
		rates = value
		emit_changed()
