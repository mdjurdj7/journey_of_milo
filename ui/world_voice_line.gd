extends Label
class_name WorldVoiceLine

# The field's world-voice text: one line in Spectral, full-value ink, no
# box, no outline, no icon - a finding, not a prompt. Distinct from the
# system voice (DeckPanel/HPBar/EnemyStatus, theme-styled panels). One
# instance per field, created lazily under FieldHUD by on_hud() the first
# time something has a line to say; anything with a line (Hull, later
# props) calls show_line(). A new line while one is showing restarts the
# fade with the new text.
#
# Colour comes from the theme's own CardFace panel_color - "charcoal on a
# pale world, bone on a dark one" (see ui/battle_theme.gd's figure/ground
# rule), the same value FloatingNumber uses for text sitting directly over
# the 3D view - so it follows RegionField's ui_on_dark_world switch for
# free.

const FONT_PATH := "res://assets/fonts/Spectral-SemiBold.ttf"
const THEME_PATH := "res://ui/battle_theme.tres"
const NODE_NAME := "WorldVoiceLine"

@export var font_size_px: int = 26
# 0 = no outline (world voice sits bare on the world); raise if a line
# ever lands on the wet band and needs help.
@export var outline_size_px: int = 0
# Where on screen the line sits: fraction of the viewport height for its
# centre. 0.88 = y 950 at 1080p, a single line spanning ~934-966 - above
# the deck panel (bottom-left, y 1004-1048, and only 32-192 px wide) and
# well below the HP bar, which follows the Wanderer near mid-screen.
@export var screen_height_fraction: float = 0.88
@export var fade_in_seconds: float = 0.5
@export var fade_out_seconds: float = 0.5

var _tween: Tween = null

# The field's one WorldVoiceLine, under `hud` (the FieldHUD CanvasLayer -
# a Control needs a CanvasLayer ancestor to render, same reason
# EnemyStatus lives there). Finds an existing one by name, else creates
# it. Returns null if hud is null.
static func on_hud(hud: Node) -> WorldVoiceLine:
	if hud == null:
		return null
	var existing := hud.get_node_or_null(NODE_NAME) as WorldVoiceLine
	if existing != null:
		return existing
	var line := WorldVoiceLine.new()
	line.name = NODE_NAME
	hud.add_child(line)
	return line

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	theme = load(THEME_PATH) as Theme
	var font: Font = load(FONT_PATH)
	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", font_size_px)
	add_theme_color_override("font_color", get_theme_color("panel_color", "CardFace"))
	add_theme_color_override("font_outline_color", get_theme_color("text_color", "CardFace"))
	add_theme_constant_override("outline_size", outline_size_px)

	# Full width at screen_height_fraction, a generous side margin so a
	# long line wraps rather than touching the edges.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = screen_height_fraction
	anchor_bottom = screen_height_fraction
	offset_left = 120.0
	offset_right = -120.0
	offset_top = -40.0
	offset_bottom = 40.0
	grow_vertical = Control.GROW_DIRECTION_BOTH

	modulate.a = 0.0

# Fades the line in over fade_in_seconds, holds it hold_seconds, fades it
# out over fade_out_seconds. Restarts cleanly if called mid-show.
func show_line(line: String, hold_seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	text = line
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_in_seconds)
	_tween.tween_interval(maxf(hold_seconds, 0.0))
	_tween.tween_property(self, "modulate:a", 0.0, fade_out_seconds)
