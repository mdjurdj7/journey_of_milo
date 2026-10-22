extends WorldArmor
class_name WorldShell

# The Warped Shell lying on the sand where the crab fell (WarpedShellData,
# RegionField._roll_warped_shell()) - WorldArmor's body, seat and reach,
# a placeholder block (no glow), in a group of its own so nothing that
# looks for worn pieces finds it. Within reach, a click opens its plate
# (RegionField.open_shell_examine()); out of reach he walks up first.
# TAKE changes the card and it goes (take()); LEAVE leaves it lying for
# the rest of the floor.

const SHELL_GROUP := &"shell_drops"

@export var shell: WarpedShellData = null
# The roll that dropped it, for the run log's shell_drop - and whether
# the F1 row's Drop shell put it there (RegionField._on_debug_shell_
# pressed()), so a test drop can be left out of playtest data.
var roll: float = 0.0
var debug: bool = false

func _init() -> void:
	placeholder_size = Vector3(0.3, 0.1, 0.24)
	placeholder_color = Color(0.62, 0.57, 0.48)

# Gone from the sand untaken - the floor left, the run ended: its roll's
# shell_drop line, not taken.
func _exit_tree() -> void:
	if shell == null or is_taken():
		return
	RunLogger.event("shell_drop", {"roll": roll, "dropped": true, "taken": false, "card_before": null, "card_after": null, "debug": debug})

func _group() -> StringName:
	return SHELL_GROUP

func _holds_something() -> bool:
	return shell != null

func _model_path() -> String:
	return ""
