extends Control
class_name KeepsakeRow

# The keepsakes the Wanderer carries into this fight that have no
# in-combat counter, as one line of grey tracked caps directly under the
# battle DECK line ("SIGNAL GLASS") - names apart by name_gap_px, no
# bullets, no dividers. A keepsake whose status counts (a combat_start_
# status with a self_loss_trigger_count) is a counter line under the HP
# bar instead, and not here. Drawn, not boxed, sized to its own text.
#
# Hovering a name shows that keepsake's KeepsakeTile at reveal_tile_scale
# (the field HUD's hover, the same tile at the same size), left-aligned
# with the row and sitting reveal_gap_px over set_reveal_floor_y(): the
# top of the bottom-left stack, so it never lands on DECK or the energy
# pips. It fades in and out over reveal_fade_time. Polled, never a mouse
# event; a card or button under the cursor wins.
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
# Between the tile's bottom and the top of the bottom-left stack.
@export var reveal_gap_px: float = 10.0:
	set(value):
		reveal_gap_px = value
		_place_reveal()
@export var reveal_tile_scale: float = 1.0:
	set(value):
		reveal_tile_scale = value
		_place_reveal()
@export var reveal_fade_time: float = 0.12
@export_group("")

var _keepsakes: Array[TrinketData] = []
var _ink: Color = Color.BLACK
var _font_tracked: Font = null
var _reveal: KeepsakeTile = null
# The name under the cursor, or -1.
var _hovered: int = -1
# The tile's share of full opacity, 0..1, eased toward the hover.
var _reveal_alpha: float = 0.0
# Canvas y the reveal sits over - see set_reveal_floor_y().
var _reveal_floor_y: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal = KeepsakeTile.new()
	_reveal.name = "Tile"
	_reveal.visible = false
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

func _process(delta: float) -> void:
	var hovered: int = -1
	if visible and _font_tracked != null and get_viewport().gui_get_hovered_control() == null:
		var mouse: Vector2 = get_local_mouse_position()
		var rects: Array[Rect2] = _name_rects()
		for i in rects.size():
			if rects[i].has_point(mouse):
				hovered = i
				break
	_set_hovered(hovered)
	_advance_reveal(delta)

# The name under the cursor (-1 none) - the tile takes its keepsake; the
# last one shown stays on it while it fades out.
func _set_hovered(index: int) -> void:
	if index == _hovered:
		return
	_hovered = index
	if index >= 0 and index < _keepsakes.size():
		_reveal.set_keepsake(_keepsakes[index])

# The tile's opacity eased toward the hover over reveal_fade_time.
func _advance_reveal(delta: float) -> void:
	var target: float = 1.0 if _hovered >= 0 else 0.0
	if is_equal_approx(_reveal_alpha, target):
		return
	_reveal_alpha = target if reveal_fade_time <= 0.0 else move_toward(_reveal_alpha, target, delta / reveal_fade_time)
	_place_reveal()

# For probes: the hover's tile.
func get_tile() -> KeepsakeTile:
	return _reveal

func _place_reveal() -> void:
	if _reveal == null or not is_inside_tree():
		return
	_reveal.visible = _reveal_alpha > 0.0
	_reveal.modulate.a = _reveal_alpha
	if not is_equal_approx(_reveal.tile_scale, reveal_tile_scale):
		_reveal.tile_scale = reveal_tile_scale
	var floor_local: float = _reveal_floor_y - global_position.y
	_reveal.position = Vector2(0.0, roundf(floor_local - reveal_gap_px - _reveal.get_tile_size().y))

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
