extends Control
class_name ReplayGhost

# A preview of the Attack a Second Swing will replay (CardView.replay_
# attack()): that card's real face, faded, with REPLAY above it, beside the
# Second Swing hovered or armed in the hand and clear above the resting
# hand. HandContainer owns it, pushes its looks (the setters) and places it
# each frame it shows (show_beside()).
#
# A preview only: never takes the mouse, no glow and no box of its own -
# the face is the card's, the label is the battle's ink with a bone outline,
# as the intent readouts are, so it reads over any ground.

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const LABEL_TEXT := "REPLAY"

var _holder: Control = null
var _card_view: CardView = null
var _label: Label = null
var _shown: CardData = null
var _scale: float = 0.9
var _label_gap_px: float = 6.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	visible = false

func _ready() -> void:
	# The faded part: the face alone, so the label keeps its own ink.
	_holder = Control.new()
	_holder.name = "Face"
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	_card_view = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	_card_view.hover_enabled = false
	_holder.add_child(_card_view)
	_card_view.pivot_offset = Vector2.ZERO
	_card_view.position = Vector2.ZERO
	_ignore_mouse(_card_view)
	_label = Label.new()
	_label.name = "ReplayLabel"
	_label.text = LABEL_TEXT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)

# Every Control under `node` - the face's own included, which CardView
# sets to STOP in its _ready() - lets the mouse through.
func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func set_face_alpha(alpha: float) -> void:
	if _holder != null:
		_holder.modulate.a = clampf(alpha, 0.0, 1.0)

# The face's size, as a share of a hand card's full card_size.
func set_face_scale(value: float) -> void:
	_scale = maxf(value, 0.01)
	if _card_view != null:
		_card_view.scale = Vector2(_scale, _scale)

# REPLAY's type: Alegreya Sans Bold caps at `size_px`, `spacing_em`
# tracking (FontVariation.spacing_glyph is whole pixels).
func set_label_font(font: Font, size_px: int, spacing_em: float, outline_px: int) -> void:
	if _label == null:
		return
	var variation := FontVariation.new()
	variation.base_font = font
	variation.spacing_glyph = roundi(float(size_px) * spacing_em)
	_label.add_theme_font_override("font", variation)
	_label.add_theme_font_size_override("font_size", size_px)
	_label.add_theme_constant_override("outline_size", outline_px)

func set_label_colors(ink: Color, outline: Color) -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color", ink)
	_label.add_theme_color_override("font_outline_color", outline)

func set_label_gap(gap_px: float) -> void:
	_label_gap_px = gap_px

# The face's on-screen size now.
func face_size() -> Vector2:
	if _card_view == null:
		return Vector2.ZERO
	return _card_view.card_size * _scale

func shown_card() -> CardData:
	return _shown if visible else null

# Shown with `card`'s face read against `ctx` (its live numbers, as a hand
# card's), its top-left at `at` (screen space) and REPLAY centred
# label_gap_px above it.
func show_card(card: CardData, ctx: EffectContext, at: Vector2) -> void:
	if _card_view == null:
		return
	if card != _shown:
		_shown = card
		_card_view.set_card_data(card)
		_ignore_mouse(_card_view)
	_card_view.set_bonus_context(ctx)
	var face: Vector2 = face_size()
	var label_size: Vector2 = _label.get_combined_minimum_size()
	global_position = at.round()
	size = face
	_holder.position = Vector2.ZERO
	_label.size = Vector2(face.x, label_size.y)
	_label.position = Vector2(0.0, -_label_gap_px - label_size.y).round()
	visible = true

func hide_ghost() -> void:
	visible = false
