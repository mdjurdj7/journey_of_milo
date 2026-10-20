extends Control
class_name DevourYieldLine

# One line of ink over the card a Devour would eat while Take In's choice
# is open - what eating it yields (DevourYield.describe(): "+4 damage this
# combat", "+2 Block each turn", "Nothing"). HandContainer owns it, sets
# its text and places it over the hovered candidate (show_over()).
#
# The system voice: Alegreya Sans Regular, the battle ink, no box, no
# backing, no glow - on the world, never on the card face. Drawn, one
# TextLine, rebuilt only when the text, size or ink change. Never takes
# the mouse.

# Held, as every drawn face here is: a font loaded and dropped in the draw
# callback is freed with its glyphs as the callback returns.
var _font: Font = null
var _line: TextLine = null
var _text: String = ""
var _font_size_px: int = 13
var _ink: Color = Color(0.165, 0.165, 0.18, 1.0)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	visible = false
	_font = InkType.text_font()

func set_font_size_px(size_px: int) -> void:
	if size_px == _font_size_px:
		return
	_font_size_px = maxi(size_px, 1)
	_rebuild()

func set_ink(ink: Color) -> void:
	_ink = ink
	queue_redraw()

func get_text() -> String:
	return _text

# Shown with `text`, centred over `card_rect` (screen space - the card as it
# stands, lifted and grown), `gap_px` above its top edge, kept on screen.
func show_over(text: String, card_rect: Rect2, gap_px: float) -> void:
	if text != _text:
		_text = text
		_rebuild()
	var at := Vector2(card_rect.get_center().x - size.x / 2.0, card_rect.position.y - gap_px - size.y)
	var view: Rect2 = get_viewport_rect()
	at.x = clampf(at.x, view.position.x, maxf(view.end.x - size.x, view.position.x))
	at.y = clampf(at.y, view.position.y, maxf(view.end.y - size.y, view.position.y))
	global_position = at.round()
	visible = true

func hide_line() -> void:
	visible = false

func _rebuild() -> void:
	_line = TextLine.new()
	if not _text.is_empty() and _font != null:
		_line.add_string(_text, _font, _font_size_px)
	size = Vector2(ceilf(_line.get_line_width()), ceilf(_line.get_size().y))
	queue_redraw()

func _draw() -> void:
	if _line == null or _text.is_empty():
		return
	_line.draw(get_canvas_item(), Vector2.ZERO, _ink)
