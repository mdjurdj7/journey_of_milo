extends Control
class_name KeywordSlip

# A small slip of the card's own bone under a keyword's definition, so it
# reads over any ground: ink text on bone, at most a hairline edge, no
# shadow, no glow, no dark panel. The name in Bold, then the definition
# with each rules keyword in Bold ("Keep: Stays in your hand..."); an
# entry with no name is one plain line (the Take In yield line,
# DevourYieldLine).
#
# The host sets the widest the slip may be (set_max_width()) and places
# it; the text wraps inside that less the padding, and the slip shrinks
# to its widest line, so a short definition is a short slip. Shown and
# hidden by set_revealed(), faded over the host's fade time. Never takes
# the mouse.
#
# Drawn, one TextParagraph per entry, rebuilt only when the lines, the
# width or the type change. The bone, ink, edge, size and padding are
# the host's exports (CardView's Keyword Reveal group), pushed in through
# the setters below.

var _fade_time: float = 0.12
var _font_size_px: int = 17
# Line pitch in ems.
var _line_height: float = 1.28
# Bone between the slip's edge and its text: x each side, y top and bottom.
var _padding: Vector2 = Vector2(8.0, 6.0)
var _bone: Color = Color(0.94, 0.91, 0.86)
var _ink: Color = Color(0.165, 0.165, 0.18)
# The edge's width in screen pixels; 0 draws none.
var _edge_px: float = 0.0
var _edge_color: Color = Color(0.165, 0.165, 0.18, 0.88)

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
var _max_width: float = 200.0
var _paragraphs: Array[TextParagraph] = []
# 0 hidden, 1 shown - tweened by set_revealed().
var _reveal: float = 0.0
var _shown: bool = false
var _tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()

# One entry per name/line pair. An empty name is a plain line. Empty
# arrays clear it.
func set_lines(names: PackedStringArray, lines: PackedStringArray) -> void:
	if names == _names and lines == _lines:
		return
	_names = names
	_lines = lines
	_rebuild()

# The widest the slip may be, padding and all.
func set_max_width(width: float) -> void:
	if is_equal_approx(width, _max_width):
		return
	_max_width = width
	_rebuild()

func set_bone(bone: Color) -> void:
	_bone = bone
	queue_redraw()

func set_ink(ink: Color) -> void:
	_ink = ink
	queue_redraw()

func set_edge(edge_px: float, edge_color: Color) -> void:
	_edge_px = maxf(edge_px, 0.0)
	_edge_color = edge_color
	queue_redraw()

func set_padding(padding: Vector2) -> void:
	_padding = padding.max(Vector2.ZERO)
	_rebuild()

func set_fade_time(fade_time: float) -> void:
	_fade_time = fade_time

func set_font_size_px(font_size_px: int) -> void:
	_font_size_px = maxi(font_size_px, 1)
	_rebuild()

func set_line_height(line_height: float) -> void:
	_line_height = line_height
	_rebuild()

func get_font_size_px() -> int:
	return _font_size_px

func get_line_count() -> int:
	var count: int = 0
	for paragraph in _paragraphs:
		count += paragraph.get_line_count()
	return count

func set_revealed(revealed: bool) -> void:
	if revealed == _shown:
		return
	_shown = revealed
	if _tween != null:
		_tween.kill()
	var target: float = 1.0 if revealed else 0.0
	if _fade_time <= 0.0 or not is_inside_tree():
		_set_reveal(target)
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_reveal, _reveal, target, _fade_time)

func _set_reveal(value: float) -> void:
	_reveal = value
	queue_redraw()

func _line_pitch() -> float:
	return roundf(float(_font_size_px) * _line_height)

func _rebuild() -> void:
	_paragraphs.clear()
	var text_width: float = maxf(_max_width - _padding.x * 2.0, 1.0)
	var widest: float = 0.0
	if text_font != null and text_bold_font != null:
		for i in mini(_names.size(), _lines.size()):
			var paragraph: TextParagraph = _build_paragraph(_names[i], _lines[i], text_width)
			for line_index in paragraph.get_line_count():
				widest = maxf(widest, paragraph.get_line_width(line_index))
			_paragraphs.append(paragraph)
	var line_count: int = get_line_count()
	if line_count == 0:
		size = Vector2.ZERO
	else:
		size = Vector2(minf(ceilf(widest) + _padding.x * 2.0, maxf(_max_width, 1.0)), _line_pitch() * float(line_count) + _padding.y * 2.0)
	queue_redraw()

func _build_paragraph(entry_name: String, line: String, width: float) -> TextParagraph:
	var paragraph := TextParagraph.new()
	paragraph.width = width
	if not entry_name.is_empty():
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
	var bone: Color = _bone
	bone.a *= _reveal
	draw_rect(Rect2(Vector2.ZERO, size), bone)
	if _edge_px > 0.0:
		var edge: Color = _edge_color
		edge.a *= _reveal
		draw_rect(Rect2(Vector2.ZERO, size).grow(-_edge_px / 2.0), edge, false, _edge_px)
	var ink: Color = _ink
	ink.a *= _reveal
	var y: float = _padding.y
	for paragraph in _paragraphs:
		for line_index in paragraph.get_line_count():
			# Each line centred in its pitch.
			var lead: float = roundf((_line_pitch() - paragraph.get_line_size(line_index).y) / 2.0)
			paragraph.draw_line(get_canvas_item(), Vector2(_padding.x, y + lead), line_index, ink)
			y += _line_pitch()
