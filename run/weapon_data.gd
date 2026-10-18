extends Resource
class_name WeaponData

# The weapon the run carries - one, always (RunState.weapon), set from the
# character's starting_weapon by new_run(). Shown in the HUD's WEAPON slot
# (KeepsakeLine) and on its plate (ArmorPlate.set_weapon()). Never a
# trinket: held_pieces() and the fight hooks don't read it.
#
# What a weapon is for (DESIGN.md, Weapons): it modifies the class's basic
# attack - Slash for the Wanderer - through modify_basic_attack(). Nothing
# calls that yet; the Rusted Blade, the baseline, leaves the attack as it
# is.

@export var id: StringName = &""
@export var display_name: String = ""
# One sentence in rules voice for what it does to the basic attack, shown
# on its plate. Empty = no effect, and no effect line.
@export_multiline var description: String = ""
# One quiet line about the object itself, under its name on the plate.
# Empty = no line.
@export_multiline var lore: String = ""
# The object, square - cropped to a square in the HUD slot, drawn in the
# plate's art window. Null = the plate's placeholder; nothing breaks.
@export var art: Texture2D = null

# The effect hook: the class's basic attack as this weapon makes it. The
# baseline returns `card` unchanged; a weapon with an effect returns a
# modified copy, never edits the shared resource.
func modify_basic_attack(card: CardData) -> CardData:
	return card

func describe() -> String:
	return description
