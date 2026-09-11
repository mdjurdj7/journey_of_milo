extends Node2D
# Shown after beating the boss - the run's actual end state, distinct from
# a normal battle's reward screen (see battle.gd's
# _on_post_battle_button_pressed()). There's no next battle to carry a
# reward into once the boss is dead, just a summary of the run that just
# ended before heading back to the title screen. Doesn't touch RunState -
# same as Defeat, the title screen's Begin Run button is the only place a
# fresh run starts (see title_screen.gd).

@onready var rooms_cleared_label: Label = $UI/RoomsClearedLabel
@onready var gold_earned_label: Label = $UI/GoldEarnedLabel
@onready var return_button: Button = $UI/ReturnButton

func _ready() -> void:
	return_button.pressed.connect(_on_return_pressed)
	rooms_cleared_label.text = "Rooms Cleared: %d" % RunState.room_number
	gold_earned_label.text = "Gold Earned: %d" % RunState.gold

func _on_return_pressed() -> void:
	SceneTransition.go_to("res://title_screen.tscn")
