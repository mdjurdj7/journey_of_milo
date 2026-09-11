extends PanelContainer
class_name EnemyStatus

# One per enemy in the fight - a small dark panel (same PanelContainer
# style as StatsPanel, since neither sets a theme_type_variation of its
# own) showing "HP current/max" and a thin bar, repositioned every frame
# at the enemy's head via unproject. Created by BattleOverlay.enter_battle
# per enemy, updated from BattleController's own enemy_hp_changed signal,
# freed along with the rest of the overlay when the battle ends.
#
# IntentSlot is deliberately empty - reserved room beside the HP block for
# a future intent icon, not built this pass.

# Just above the Sputter's own shell, not a human head-height - retune per
# enemy live (Remote tab) once a taller creature needs a bigger offset.
@export var head_offset: Vector3 = Vector3(0.0, 0.9, 0.0)

@onready var hp_label: Label = $Content/VBox/HPLabel
@onready var bar_background: ColorRect = $Content/VBox/BarBackground
@onready var bar_fill: ColorRect = $Content/VBox/BarBackground/BarFill

var target: FieldEnemy
var _bar_width: float = 0.0

func _ready() -> void:
	_bar_width = bar_background.custom_minimum_size.x
	bar_background.color = get_theme_color("panel_light_color", "CardFace")
	bar_fill.color = get_theme_color("text_color", "CardFace")

func set_target(field_enemy: FieldEnemy) -> void:
	target = field_enemy

func update_hp(current: int, max_hp: int) -> void:
	hp_label.text = "HP %d/%d" % [current, max_hp]
	var fraction: float = float(current) / float(max_hp) if max_hp > 0 else 0.0
	bar_fill.size.x = _bar_width * clampf(fraction, 0.0, 1.0)

func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(target.global_position + head_offset)
	position = screen_pos - size / 2.0
