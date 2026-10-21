extends Resource
class_name CollectorGood

# One piece of equipment the collector stocks beside its cards (Collector.
# goods): an existing item resource - a worn piece or a keepsake (Trinket-
# Data, by its slot) or a weapon (WeaponData) - and what it asks for it.
# Nothing is rolled: a floor lists its goods through the FloorProp's
# overrides, each taken at most once while the floor lasts.

@export var item: Resource = null
@export var price: int = 0

# The item as a trinket, or null when it is a weapon (or nothing).
func get_trinket() -> TrinketData:
	return item as TrinketData

# The item as a weapon, or null when it is a trinket (or nothing).
func get_weapon() -> WeaponData:
	return item as WeaponData

# Whether the item is something the screen can sell.
func is_valid() -> bool:
	return get_trinket() != null or get_weapon() != null
