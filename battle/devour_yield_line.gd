extends KeywordSlip
class_name DevourYieldLine

# One line over the card a Devour would eat while Take In's choice is
# open - what eating it yields (DevourYield.describe(): "+4 damage this
# combat", "+2 Block each turn", "Nothing"). HandContainer owns it, sets
# its text and places it over the hovered candidate (show_over()).
#
# The system voice, Alegreya Sans Regular in the battle ink, on a one-line
# strip of the card's bone (a KeywordSlip with no name), so it reads over
# any ground - never on the card face. Never wraps. Never takes the mouse.

var _text: String = ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	visible = false
	set_fade_time(0.0)
	set_font_size_px(13)
	# One line, however long: wider than any window it's drawn in.
	set_max_width(100000.0)
	set_revealed(true)

func get_text() -> String:
	return _text

# Shown with `text`, centred over `card_rect` (screen space - the card as it
# stands, lifted and grown), `gap_px` above its top edge, kept on screen.
func show_over(text: String, card_rect: Rect2, gap_px: float) -> void:
	if text != _text:
		_text = text
		set_lines(PackedStringArray([""]), PackedStringArray([_text]))
	var at := Vector2(card_rect.get_center().x - size.x / 2.0, card_rect.position.y - gap_px - size.y)
	var view: Rect2 = get_viewport_rect()
	at.x = clampf(at.x, view.position.x, maxf(view.end.x - size.x, view.position.x))
	at.y = clampf(at.y, view.position.y, maxf(view.end.y - size.y, view.position.y))
	global_position = at.round()
	visible = true

func hide_line() -> void:
	visible = false
