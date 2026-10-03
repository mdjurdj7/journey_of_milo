extends Control
class_name StatusReveal

# What each status - and the Wanderer's stance - on one combatant does,
# one entry each, directly under its battle readout's status row: the
# name, then its rules sentence with live numbers ("Come Due: +4 damage
# on your next 2 Attacks against it."). Shown while the readout is
# hovered - the host (EnemyStatus or HPBar) decides when and calls
# set_revealed() - faded in and out over reveal_fade_time.
#
# Ink on the world in the card's rules type: Alegreya Sans Regular, the
# name and the rules keywords (CardView.KEYWORDS) in Bold, at the card's
# rules line height - no box, no backing, no glyph. Each entry wraps at
# the host's readout width (set_wrap_width()), so in a cluster every
# reveal stays in its own column. The host hands over ready strings
# (Status.describe()/Stance.describe()); nothing here reads rules state.
#
# Drawn, one TextParagraph per entry, rebuilt only when the lines, the
# width or the type change. Never takes the mouse.
#
# The fade, the ink alpha, the size and the spacing are the host's
# exports (the readout's Status Reveal group, editable on its scene node),
# pushed in through the setters below.

var _fade_time: float = 0.12
var _line_alpha: float = 0.92
var _font_size_px: int = 13
# Line pitch in ems, as CardView.keyword_reveal_line_height.
var _line_height: float = 1.28
# Extra space between two entries, on top of the line pitch, so a wrapped
# sentence reads apart from the next status's.
var _entry_gap_px: float = 4.0
var _align_right: bool = false

@export var text_font: Font = load("res://assets/fonts/AlegreyaSans-Regular.ttf"):
	set(value):
		text_font = value
		_rebuild()
@export var text_bold_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf"):
	set(value):
		text_bold_font = value
		_rebuild()

var _names: PackedStringArray = PackedStringArray()
var _lines: PackedStringArray = PackedStringArray()
var _wrap_width: float = 160.0
var _ink: Color = Color.BLACK
var _paragraphs: Array[TextParagraph] = []
# 0 hidden, 1 shown - tweened by set_revealed().
var _reveal: float = 0.0
var _shown: bool = false
var _tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()

# One entry per name/line pair, in the order the row shows them. Empty
# arrays clear it.
func set_lines(names: PackedStringArray, lines: PackedStringArray) -> void:
	if names == _names and lines == _lines:
		return
	_names = names
	_lines = lines
	_rebuild()

func set_wrap_width(width: float) -> void:
	if is_equal_approx(width, _wrap_width):
		return
	_wrap_width = width
	_rebuild()

func set_ink(ink: Color) -> void:
	_ink = ink
	queue_redraw()

func set_fade_time(fade_time: float) -> void:
	_fade_time = fade_time

func set_line_alpha(line_alpha: float) -> void:
	_line_alpha = line_alpha
	queue_redraw()

func set_font_size_px(font_size_px: int) -> void:
	_font_size_px = font_size_px
	_rebuild()

func set_line_height(line_height: float) -> void:
	_line_height = line_height
	_rebuild()

func set_entry_gap_px(entry_gap_px: float) -> void:
	_entry_gap_px = entry_gap_px
	_rebuild()

# Every line flush right in the wrap width instead of left - for a host
# that sets this beside its readout's left edge (HPBar's flip).
func set_align_right(align_right: bool) -> void:
	if align_right == _align_right:
		return
	_align_right = align_right
	queue_redraw()

func set_revealed(revealed: bool) -> void:
	if revealed == _shown:
		return
	_shown = revealed
	if _tween != null:
		_tween.kill()
	var target: float = 1.0 if revealed else 0.0
	if _fade_time <= 0.0:
		_set_reveal(target)
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_reveal, _reveal, target, _fade_time)

# Gone at once, lines and all - the fight is over.
func clear() -> void:
	if _tween != null:
		_tween.kill()
	_shown = false
	_set_reveal(0.0)
	set_lines(PackedStringArray(), PackedStringArray())

func _set_reveal(value: float) -> void:
	_reveal = value
	queue_redraw()

func _line_pitch() -> float:
	return roundf(float(_font_size_px) * _line_height)

func _rebuild() -> void:
	_paragraphs.clear()
	if text_font != null and text_bold_font != null:
		for i in mini(_names.size(), _lines.size()):
			_paragraphs.append(_build_paragraph(_names[i], _lines[i]))
	var height: float = 0.0
	for paragraph in _paragraphs:
		height += _line_pitch() * paragraph.get_line_count() + _entry_gap_px
	size = Vector2(_wrap_width, maxf(height - _entry_gap_px, 0.0))
	queue_redraw()

# "Name: " in Bold, then the sentence with each keyword in Bold - the
# card's _format_rules() emphasis, as spans rather than BBCode.
func _build_paragraph(entry_name: String, line: String) -> TextParagraph:
	var paragraph := TextParagraph.new()
	paragraph.width = _wrap_width
	paragraph.add_string(entry_name + ": ", text_bold_font, _font_size_px)
	var cursor: int = 0
	for keyword: RegExMatch in KeywordTable.shared().pattern().search_all(line):
		if keyword.get_start() > cursor:
			paragraph.add_string(line.substr(cursor, keyword.get_start() - cursor), text_font, _font_size_px)
		paragraph.add_string(keyword.get_string(), text_bold_font, _font_size_px)
		cursor = keyword.get_end()
	if cursor < line.length():
		paragraph.add_string(line.substr(cursor), text_font, _font_size_px)
	return paragraph

func _draw() -> void:
	if _reveal <= 0.0 or _paragraphs.is_empty():
		return
	var color: Color = _ink
	color.a = _line_alpha * _reveal
	var y: float = 0.0
	for paragraph in _paragraphs:
		for line_index in paragraph.get_line_count():
			# draw_line() ignores the paragraph's own alignment - flush
			# right is placed by hand.
			var x: float = _wrap_width - paragraph.get_line_width(line_index) if _align_right else 0.0
			paragraph.draw_line(get_canvas_item(), Vector2(x, y), line_index, color)
			y += _line_pitch()
		y += _entry_gap_px
