extends Control
class_name KeepsakeRow

# The keepsakes the Wanderer carries into this fight that have no
# in-combat counter, as one line of grey tracked caps directly under the
# battle DECK line ("SIGNAL GLASS") - names apart by name_gap_px, no
# bullets, no dividers. A keepsake whose status counts (a combat_start_
# status with a self_loss_trigger_count) is a counter line under the HP
# bar instead, and not here. Drawn, not boxed, sized to its own text.
#
# Hovering a name shows what that keepsake does (TrinketData.describe()) in
# the readouts' rules type - a StatusReveal, left-aligned with the row and
# sitting reveal_gap_px over set_reveal_floor_y(): the top of the bottom-
# left stack, so it never lands on DECK or the energy pips. Polled, never
# a mouse event; a card or button under the cursor wins.
#
# BattleOverlay creates it with the other corner readouts, places it
# (_layout_corners()) and hands it the keepsakes (set_keepsakes()). Reads
# the theme's Battle/ink token - re-read via refresh_style().

@export var font_size_px: int = 12:
	set(value):
		font_size_px = value
		_refresh_if_ready()
# One tracking value for every caps label in the battle UI - see InkType.
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_refresh_if_ready()
# The grey: the battle ink at this alpha, as DECK's label.
@export_range(0.0, 1.0) var label_alpha: float = 0.62:
	set(value):
		label_alpha = value
		queue_redraw()
@export var name_gap_px: float = 14.0:
	set(value):
		name_gap_px = value
		_relayout()

@export_group("Reveal")
# Between the reveal's last line and the top of the bottom-left stack.
@export var reveal_gap_px: float = 10.0:
	set(value):
		reveal_gap_px = value
		_place_reveal()
@export var reveal_wrap_width_px: float = 190.0:
	set(value):
		reveal_wrap_width_px = value
		if _reveal != null:
			_reveal.set_wrap_width(value)
		_place_reveal()
@export var reveal_fade_time: float = 0.12:
	set(value):
		reveal_fade_time = value
		if _reveal != null:
			_reveal.set_fade_time(value)
@export_range(0.0, 1.0) var reveal_line_alpha: float = 0.92:
	set(value):
		reveal_line_alpha = value
		if _reveal != null:
			_reveal.set_line_alpha(value)
@export var reveal_font_size_px: int = 13:
	set(value):
		reveal_font_size_px = value
		if _reveal != null:
			_reveal.set_font_size_px(value)
		_place_reveal()
# Line pitch in ems, as CardView.rules_line_height.
@export var reveal_line_height: float = 1.28:
	set(value):
		reveal_line_height = value
		if _reveal != null:
			_reveal.set_line_height(value)
		_place_reveal()
@export_group("")

var _keepsakes: Array[TrinketData] = []
var _ink: Color = Color.BLACK
var _font_tracked: Font = null
var _reveal: StatusReveal = null
# The name under the cursor, or -1.
var _hovered: int = -1
# Canvas y the reveal sits over - see set_reveal_floor_y().
var _reveal_floor_y: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal = StatusReveal.new()
	_reveal.name = "StatusReveal"
	_reveal.set_fade_time(reveal_fade_time)
	_reveal.set_line_alpha(reveal_line_alpha)
	_reveal.set_font_size_px(reveal_font_size_px)
	_reveal.set_line_height(reveal_line_height)
	_reveal.set_wrap_width(reveal_wrap_width_px)
	add_child(_reveal)
	refresh_style()

func set_keepsakes(keepsakes: Array[TrinketData]) -> void:
	_keepsakes = keepsakes.duplicate()
	_hovered = -1
	_relayout()

# The canvas y the reveal's bottom keeps reveal_gap_px above - the top of
# whatever sits over this row (BattleOverlay's bottom-left stack).
func set_reveal_floor_y(y: float) -> void:
	_reveal_floor_y = y
	_place_reveal()

# Re-reads the theme's ink and rebuilds the tracked face - called at
# _ready() and by BattleOverlay's F2 flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_font_tracked = InkType.tracked(InkType.text_bold_font(), font_size_px, tracking_em)
	if _reveal != null:
		_reveal.set_ink(_ink)
	_relayout()

func _refresh_if_ready() -> void:
	if is_inside_tree():
		refresh_style()

func _names() -> PackedStringArray:
	var names := PackedStringArray()
	for keepsake in _keepsakes:
		names.append(keepsake.display_name.to_upper())
	return names

func _relayout() -> void:
	if not is_inside_tree() or _font_tracked == null:
		return
	var width: float = 0.0
	var names: PackedStringArray = _names()
	for i in names.size():
		if i > 0:
			width += name_gap_px
		width += InkType.width(_font_tracked, names[i], font_size_px)
	size = Vector2(width, _font_tracked.get_height(font_size_px))
	queue_redraw()

# Each name's own span, the row's full height.
func _name_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x: float = 0.0
	for name_text in _names():
		var width: float = InkType.width(_font_tracked, name_text, font_size_px)
		rects.append(Rect2(x, 0.0, width, size.y))
		x += width + name_gap_px
	return rects

func _process(_delta: float) -> void:
	var hovered: int = -1
	if visible and _font_tracked != null and get_viewport().gui_get_hovered_control() == null:
		var mouse: Vector2 = get_local_mouse_position()
		var rects: Array[Rect2] = _name_rects()
		for i in rects.size():
			if rects[i].has_point(mouse):
				hovered = i
				break
	if hovered != _hovered:
		_hovered = hovered
		if hovered >= 0:
			var keepsake: TrinketData = _keepsakes[hovered]
			_reveal.set_lines(PackedStringArray([keepsake.display_name]), PackedStringArray([keepsake.describe()]))
			_place_reveal()
		_reveal.set_revealed(hovered >= 0)

func _place_reveal() -> void:
	if _reveal == null or not is_inside_tree():
		return
	var floor_local: float = _reveal_floor_y - global_position.y
	_reveal.position = Vector2(0.0, floor_local - reveal_gap_px - _reveal.size.y)

func _draw() -> void:
	if _font_tracked == null:
		return
	var color: Color = _ink
	color.a = label_alpha
	var baseline: float = _font_tracked.get_ascent(font_size_px)
	var x: float = 0.0
	for name_text in _names():
		x += InkType.draw_run(self, _font_tracked, name_text, Vector2(x, baseline), font_size_px, color)
		x += name_gap_px
