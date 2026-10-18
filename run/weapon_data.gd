extends Resource
class_name WeaponData

# The weapon the run carries - one, always (RunState.weapon), set from the
# character's starting_weapon by new_run(). Shown in the HUD's WEAPON slot
# (KeepsakeLine) and on its plate (ItemPlate.set_weapon()). Never a
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

@export_group("Field Model")
# What the Wanderer carries in the field and the battle frame (Wanderer.
# _build_sword()), drawn through the painted shader with field_albedo.
# Empty path = his own sword.glb (Wanderer.SWORD_SCENE_PATH). Null albedo
# = sword_painted.png for his own sword, else the model's own imported
# base colour.
@export_file("*.glb", "*.gltf", "*.tscn", "*.fbx") var field_model_path: String = ""
@export var field_albedo: Texture2D = null

# Its fit (field_fit()), copied onto the Wanderer's exports of the same
# names when the sword is built - those stay the live-tunable ones (the
# Remote tab). An unset value keeps the Wanderer's own from the scene: a
# length of 0, a grip fraction below 0, FitFlag.UNSET, or a vector with
# any non-finite component (the INF defaults). Positions in world metres,
# rotations in degrees, as his exports read them.
enum FitFlag { UNSET, OFF, ON }
const UNSET_VECTOR := Vector3(INF, INF, INF)
# His sword_length: the model's longest side, in metres.
@export var field_length: float = 0.0
# His grip_fraction: the grip along the long side, from the tip.
@export_range(-1.0, 1.0) var field_grip_fraction: float = -1.0
# His grip_axis_flip: ON = the tip is the long side's lower end.
@export var field_grip_axis_flip: FitFlag = FitFlag.UNSET
@export var field_hand_mount_position: Vector3 = UNSET_VECTOR
@export var field_hand_mount_rotation_degrees: Vector3 = UNSET_VECTOR
@export var field_back_mount_position: Vector3 = UNSET_VECTOR
@export var field_back_mount_rotation_degrees: Vector3 = UNSET_VECTOR

# The fit values this weapon sets, keyed by the Wanderer export each one
# stands for; the unset ones are left out.
func field_fit() -> Dictionary:
	var fit: Dictionary = {}
	if field_length > 0.0:
		fit[&"sword_length"] = field_length
	if field_grip_fraction >= 0.0:
		fit[&"grip_fraction"] = field_grip_fraction
	if field_grip_axis_flip != FitFlag.UNSET:
		fit[&"grip_axis_flip"] = field_grip_axis_flip == FitFlag.ON
	var vectors: Dictionary = {
		&"hand_mount_position": field_hand_mount_position,
		&"hand_mount_rotation_degrees": field_hand_mount_rotation_degrees,
		&"back_mount_position": field_back_mount_position,
		&"back_mount_rotation_degrees": field_back_mount_rotation_degrees,
	}
	for property: StringName in vectors:
		var value: Vector3 = vectors[property]
		if value.is_finite():
			fit[property] = value
	return fit

# The effect hook: the class's basic attack as this weapon makes it. The
# baseline returns `card` unchanged; a weapon with an effect returns a
# modified copy, never edits the shared resource.
func modify_basic_attack(card: CardData) -> CardData:
	return card

func describe() -> String:
	return description
