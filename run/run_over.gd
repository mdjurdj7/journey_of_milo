extends Control

const REGION_FIELD_SCENE_PATH := "res://field/region_field.tscn"

@onready var restart_button: Button = $RestartButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_pressed)

func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file(REGION_FIELD_SCENE_PATH)
