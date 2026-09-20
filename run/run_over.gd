extends Control

const REGION_FIELD_SCENE_PATH := "res://field/region_field.tscn"
# Only for a RunOver reached with no run on RunState at all (the scene
# run directly); a real defeat restarts with the character the run used.
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"

@onready var restart_button: Button = $RestartButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_pressed)

# A fresh run, not a resumption: RunState.new_run() with the same
# character - floor 0, full HP, the starting Belongings, and the run_
# opening_pending it raises plays the zone intro on the field's first
# floor. Before this, the field simply reloaded with RunState as the
# defeat left it (HP 0, the floor index kept, no intro). The field's own
# guarded new_run() then sees the character set and stays out of it.
func _on_restart_pressed() -> void:
	var character: CharacterData = RunState.character
	if character == null:
		character = load(STARTING_CHARACTER_PATH) as CharacterData
	RunState.new_run(character)
	get_tree().change_scene_to_file(REGION_FIELD_SCENE_PATH)
