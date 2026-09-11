extends Label
class_name FloatingNumber

# A placeholder rising number - reacts to BattleController's own
# damage_dealt signal (see battle_overlay.gd), nothing else. Rises and
# fades over its own exported time, then frees itself.
#
# Color is read from the theme's own CardFace tokens, not hardcoded or
# left at Label's default white: panel_color is exactly "charcoal on a
# pale world, bone on a dark one" already (see ui/battle_theme.gd's own
# figure/ground rule) - the same value that makes a card panel read as
# the dark figure against pale ground, or the pale figure against dark
# ground, is what a number floating directly over the 3D world (not a UI
# panel) needs too. The outline uses the opposite value (text_color) so
# it survives either ground tone.

const FONT_PATH := "res://assets/fonts/Spectral-SemiBold.ttf"

@export var rise_px: float = 60.0
@export var duration_sec: float = 0.6
@export var font_size_px: int = 40
@export var outline_size_px: int = 2

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var font: Font = load(FONT_PATH)
	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", font_size_px)

	add_theme_color_override("font_color", get_theme_color("panel_color", "CardFace"))
	add_theme_color_override("font_outline_color", get_theme_color("text_color", "CardFace"))
	add_theme_constant_override("outline_size", outline_size_px)

func show_value(value: int, screen_pos: Vector2) -> void:
	text = str(value)
	position = screen_pos

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", screen_pos.y - rise_px, duration_sec)
	tween.tween_property(self, "modulate:a", 0.0, duration_sec)
	tween.chain().tween_callback(queue_free)
