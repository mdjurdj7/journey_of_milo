extends Label
class_name WorldVoiceLine

# The field's world-voice text: one line in Spectral, full-value ink, no
# box, no outline, no icon - a finding, not a prompt. Distinct from the
# system voice (DeckPanel/HPBar/EnemyStatus, theme-styled panels). One
# instance per field, created lazily under FieldHUD by on_hud() the first
# time something has a line to say; anything with a line (Hull, later
# props) calls show_line(), or show_line_near() to say it over whoever
# says it rather than in the band. A new line while one is showing
# restarts the fade with the new text.
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
# show_line_near() only: the line sits over a point in the world instead
# of in the band - its box this wide, centred on the point's screen
# position, its text's baseline anchored_gap_px above it. Read every
# frame while anchored.
@export var anchored_width_px: float = 900.0
@export var anchored_gap_px: float = 8.0

var _tween: Tween = null
# show_line_near()'s node and the world offset from it the line sits
# over - null while the line is in the band.
var _anchor: Node3D = null
var _anchor_offset: Vector3 = Vector3.ZERO

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
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	theme = load(THEME_PATH) as Theme
	var font: Font = load(FONT_PATH)
	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", font_size_px)
	add_theme_color_override("font_color", get_theme_color("panel_color", "CardFace"))
	add_theme_color_override("font_outline_color", get_theme_color("text_color", "CardFace"))
	add_theme_constant_override("outline_size", outline_size_px)

	_apply_band_layout()
	modulate.a = 0.0

# The band: full width at screen_height_fraction, a generous side margin
# so a long line wraps rather than touching the edges. A click on the
# band is UI, not a point-to-move click (see RegionField._unhandled_
# input()) - STOP swallows it. The band is the full 120..-120 px width at
# screen_height_fraction, whether or not a line is currently showing (it
# hides by modulate, not visibility).
func _apply_band_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = screen_height_fraction
	anchor_bottom = screen_height_fraction
	offset_left = 120.0
	offset_right = -120.0
	offset_top = -40.0
	offset_bottom = 40.0
	grow_vertical = Control.GROW_DIRECTION_BOTH

# Over a point in the world (show_line_near()): a free box placed by
# _process(), the text on its bottom edge. It lets clicks through - it
# sits over the field he is walking on, not in a band kept for UI.
func _apply_anchored_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	size = Vector2(anchored_width_px, 80.0)

func _process(_delta: float) -> void:
	if _anchor == null:
		return
	if not is_instance_valid(_anchor):
		_anchor = null
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var point: Vector3 = _anchor.global_position + _anchor_offset
	if camera.is_position_behind(point):
		return
	var screen_pos: Vector2 = camera.unproject_position(point)
	size = Vector2(anchored_width_px, size.y)
	position = (screen_pos - Vector2(anchored_width_px * 0.5, size.y + anchored_gap_px)).round()

# Fades the line in over fade_in_seconds, holds it hold_seconds, fades it
# out over fade_out_seconds. Restarts cleanly if called mid-show.
func show_line(line: String, hold_seconds: float) -> void:
	_anchor = null
	_apply_band_layout()
	_play(line, hold_seconds)

# The same line, over `anchor` (plus `offset`, world) rather than in the
# band - world voice near the one saying it. Back to the band once it has
# faded out, so the next show_line() finds the band as it was.
func show_line_near(line: String, hold_seconds: float, anchor: Node3D, offset: Vector3) -> void:
	_anchor = anchor
	_anchor_offset = offset
	_apply_anchored_layout()
	_process(0.0)
	_play(line, hold_seconds)
	_tween.tween_callback(func() -> void:
		_anchor = null
		_apply_band_layout())

func _play(line: String, hold_seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	text = line
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, fade_in_seconds)
	_tween.tween_interval(maxf(hold_seconds, 0.0))
	_tween.tween_property(self, "modulate:a", 0.0, fade_out_seconds)
