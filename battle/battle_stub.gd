extends Control
class_name BattleStub

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

@onready var enemy_label: Label = $EnemyLabel
@onready var win_button: Button = $Buttons/WinButton
@onready var lose_button: Button = $Buttons/LoseButton
@onready var escape_button: Button = $Buttons/EscapeButton

func _ready() -> void:
	win_button.pressed.connect(func(): battle_finished.emit(Outcome.WIN))
	lose_button.pressed.connect(func(): battle_finished.emit(Outcome.LOSE))
	escape_button.pressed.connect(func(): battle_finished.emit(Outcome.ESCAPE))

func set_enemy_id(enemy_id: StringName) -> void:
	enemy_label.text = "Enemy: %s" % enemy_id
