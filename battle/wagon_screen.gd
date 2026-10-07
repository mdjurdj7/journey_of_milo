extends CanvasLayer
class_name WagonScreen

# The wagon's tools, over the field. Opened by RegionField.open_wagon_
# screen() on the wagon's open_requested, over the scrim-and-freeze the
# collector's screen uses: the field goes DISABLED under it, the camera
# holds, and this layer runs ALWAYS on layer 100. No title, no panel, no
# box - the system voice and the cards alone.
#
# At the top, GLASSBONE xN in tracked caps; under it the wagon's world-
# voice line in Spectral - Wagon.working_line while the run's Glassbone
# covers Wagon.temper_cost, Wagon.empty_line while it doesn't. Then:
#
# - Glassbone short (EMPTY): nothing more - no grid. LEAVE.
# - Glassbone enough (GRID): the deck as a grid of cards, by name, sized
#   to fit. A card with no tempered version (CardData.tempered null -
#   which every tempered card is) is dimmed (CardView.set_playable(false))
#   and its click does nothing. Clicking one that has one opens:
# - PREVIEW: that card on the left and its tempered version on the
#   right, both at preview_card_scale, a single hairline arrow between
#   them. On the tempered face, a short ink hairline under every number
#   that differs from the original, under the whole of a line the
#   original doesn't have, and under the cost when it differs. TEMPER
#   and BACK under them; BACK returns to the grid with nothing spent.
# - TEMPER spends the cost and swaps the card (RunState.temper_card()),
#   then HELD: the tempered card alone, centred, under Wagon.held_line in
#   the world line's place, for Wagon.held_seconds - and back to the grid
#   with the count moved, or to EMPTY if the Glassbone is now short.
#
# LEAVE - and ui_cancel, and a right click outside a preview - closes the
# screen at any point except HELD, and RegionField unlocks the field. A
# right click in a preview is BACK.
#
# The focus language of the other screens over the scrim: a card focused
# grows in place (CardView.set_hovered()); a text line focused is full
# bone with the short hairline to its left, grey at rest. ui_left/
# ui_right move along the grid (or between TEMPER and BACK), ui_down
# drops to LEAVE, ui_up climbs back, ui_accept acts.
#
# The scrim, the outlined text and the hairline are copies of
# CollectorScreen's - the shared focus-drawing extraction is its own
# task (DESIGN.md).

signal closed()

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"

enum Mode { GRID, EMPTY, PREVIEW, HELD }

# Text-line focus indices, past any card's.
const TEMPER_INDEX := 100000
const BACK_INDEX := 100001
const LEAVE_INDEX := 100002

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.55):
	set(value):
		scrim_color = value
		if _scrim != null:
			_scrim.color = value
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		bone = value
		_refresh()
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_refresh()
@export var text_outline_px: int = 1:
	set(value):
		text_outline_px = value
		_refresh()
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_refresh()

@export_group("Top")
# Every size is authored for this window height and scaled by the
# window's own.
@export var reference_height: float = 1080.0:
	set(value):
		reference_height = value
		_relayout()
@export var count_format: String = "GLASSBONE ×%d":
	set(value):
		count_format = value
		_refresh()
@export var count_size_px: int = 24:
	set(value):
		count_size_px = value
		_relayout()
@export_range(0.0, 1.0) var count_baseline_fraction: float = 0.07:
	set(value):
		count_baseline_fraction = value
		_refresh()
@export var line_size_px: int = 28:
	set(value):
		line_size_px = value
		_relayout()
@export_range(0.0, 1.0) var line_baseline_fraction: float = 0.135:
	set(value):
		line_baseline_fraction = value
		_refresh()
@export_group("")

@export_group("Grid")
# A grid card's scale at its largest; held lower when the deck won't fit
# the area between grid_top_fraction and grid_bottom_fraction.
@export var grid_card_scale: float = 0.62:
	set(value):
		grid_card_scale = value
		_relayout()
# Between two cards, as a fraction of a card's width.
@export var grid_gap_fraction: float = 0.12:
	set(value):
		grid_gap_fraction = value
		_relayout()
@export_range(0.0, 1.0) var grid_top_fraction: float = 0.19:
	set(value):
		grid_top_fraction = value
		_relayout()
@export_range(0.0, 1.0) var grid_bottom_fraction: float = 0.86:
	set(value):
		grid_bottom_fraction = value
		_relayout()
@export_range(0.1, 1.0) var max_width_fraction: float = 0.9:
	set(value):
		max_width_fraction = value
		_relayout()
@export_group("")

@export_group("Preview")
@export var preview_card_scale: float = 1.4:
	set(value):
		preview_card_scale = value
		_relayout()
@export_range(0.0, 1.0) var preview_centre_fraction: float = 0.47:
	set(value):
		preview_centre_fraction = value
		_relayout()
# The room between the two cards, as a fraction of a (scaled) card's
# width; the arrow runs across its middle arrow_length_fraction of it.
@export var preview_gap_fraction: float = 0.42:
	set(value):
		preview_gap_fraction = value
		_relayout()
@export_range(0.1, 1.0) var arrow_length_fraction: float = 0.6:
	set(value):
		arrow_length_fraction = value
		_refresh()
# The head's two strokes, reference px, and their angle off the shaft.
@export var arrow_head_px: float = 9.0:
	set(value):
		arrow_head_px = value
		_refresh()
@export var arrow_head_degrees: float = 30.0:
	set(value):
		arrow_head_degrees = value
		_refresh()
@export var arrow_color: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		arrow_color = value
		_refresh()
@export var arrow_width_px: float = 1.0:
	set(value):
		arrow_width_px = value
		_refresh()
# The tempered card's cost hairline: card px under the cost's baseline.
@export var cost_mark_gap_px: float = 3.0:
	set(value):
		cost_mark_gap_px = value
		if _cost_mark != null:
			_cost_mark.queue_redraw()
@export_range(0.0, 1.0) var actions_baseline_fraction: float = 0.8:
	set(value):
		actions_baseline_fraction = value
		_refresh()
# Between TEMPER's right edge and BACK's hairline, reference px.
@export var actions_gap_px: float = 96.0:
	set(value):
		actions_gap_px = value
		_refresh()
# The tempered card's slide to the centre when it holds.
@export var held_slide_sec: float = 0.25
@export_group("")

@export_group("Lines")
@export var temper_text: String = "TEMPER":
	set(value):
		temper_text = value
		_refresh()
@export var back_text: String = "BACK":
	set(value):
		back_text = value
		_refresh()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_refresh()
@export var label_size_px: int = 22:
	set(value):
		label_size_px = value
		_relayout()
@export_range(0.0, 1.0) var label_tracking_em: float = 0.16:
	set(value):
		label_tracking_em = value
		_relayout()
@export_range(0.0, 1.0) var leave_baseline_fraction: float = 0.93:
	set(value):
		leave_baseline_fraction = value
		_refresh()
@export var hairline_length_px: float = 28.0:
	set(value):
		hairline_length_px = value
		_refresh()
@export var hairline_gap_px: float = 14.0:
	set(value):
		hairline_gap_px = value
		_refresh()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_refresh()
@export_group("")

var _wagon: Wagon = null
var _mode: Mode = Mode.EMPTY
var _scrim: ColorRect = null
var _draw_layer: Control = null
# Above the cards: the preview's arrow.
var _overlay: Control = null
var _line_font: Font = null
var _label_font: Font = null
var _count_font: Font = null
var _fit: float = 1.0
var _label_px: int = 22
var _count_px: int = 24
var _line_px: int = 28
# The grid: the deck's cards by name, one view each.
var _cards: Array[CardData] = []
var _views: Array[CardView] = []
# The preview: the deck's card picked and the two faces shown.
var _picked: CardData = null
var _before_view: CardView = null
var _after_view: CardView = null
var _cost_mark: Control = null
var _held_tween: Tween = null
# Focus: a grid index, or TEMPER/BACK/LEAVE_INDEX; -1 = nothing.
var _focus: int = -1
var _mouse_on: int = -1
var _closing: bool = false

# Called by RegionField before the screen enters the tree.
func setup(wagon: Wagon) -> void:
	_wagon = wagon

func _ready() -> void:
	# The field is frozen under this (RegionField.open_wagon_screen()); this
	# layer opts out of the freeze or would stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field and order the Wanderer off.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Screen"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_screen)
	_draw_layer.resized.connect(_relayout)
	add_child(_draw_layer)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	if _wagon != null:
		_wagon.temper_changed.connect(_on_temper_changed)
	_enter_rest_mode()

func _exit_tree() -> void:
	if _wagon != null and is_instance_valid(_wagon) and _wagon.temper_changed.is_connected(_on_temper_changed):
		_wagon.temper_changed.disconnect(_on_temper_changed)

# --- Modes ---

func _cost() -> int:
	return _wagon.temper_cost if _wagon != null else 1

func _can_temper() -> bool:
	return RunState.glassbone >= _cost()

# GRID or EMPTY, by the Glassbone held - what the screen rests in.
func _enter_rest_mode() -> void:
	_clear_preview()
	_clear_grid()
	_focus = -1
	_mouse_on = -1
	if _can_temper():
		_mode = Mode.GRID
		_build_grid()
	else:
		_mode = Mode.EMPTY
	_relayout()

func _clear_grid() -> void:
	for view in _views:
		if view != null and is_instance_valid(view):
			view.queue_free()
	_views.clear()
	_cards.clear()

func _clear_preview() -> void:
	if _held_tween != null and _held_tween.is_valid():
		_held_tween.kill()
	_held_tween = null
	for view: CardView in [_before_view, _after_view]:
		if view != null and is_instance_valid(view):
			view.queue_free()
	_before_view = null
	_after_view = null
	_cost_mark = null
	_picked = null

# A card the wagon can work: it has a tempered version. A tempered card's
# own is null, so this is also "not tempered yet".
static func can_pick(card: CardData) -> bool:
	return card != null and card.tempered != null

func _build_grid() -> void:
	_cards = RunState.deck.duplicate()
	_cards.sort_custom(func(a: CardData, b: CardData) -> bool: return a.card_name.naturalnocasecmp_to(b.card_name) < 0)
	for index in _cards.size():
		var view: CardView = _new_view(_cards[index])
		if view == null:
			return
		view.set_playable(can_pick(_cards[index]))
		view.clicked.connect(_on_card_clicked.bind(index))
		view.mouse_entered.connect(_on_card_mouse_entered.bind(index))
		view.mouse_exited.connect(_on_card_mouse_exited.bind(index))
		_views.append(view)

# The reward screen's choice card: grows in place about its centre (pivot
# set after add_child()), no lift; keywords define themselves on hover.
func _new_view(card: CardData) -> CardView:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("WagonScreen: could not load %s; no cards shown." % CARD_VIEW_SCENE_PATH)
		return null
	var view := scene.instantiate() as CardView
	view.hover_lift = 0.0
	_draw_layer.add_child(view)
	view.pivot_offset = view.card_size / 2.0
	view.set_card_data(card)
	view.set_keyword_inspect(true)
	return view

func _open_preview(index: int) -> void:
	var card: CardData = _cards[index]
	if not can_pick(card):
		return
	_set_focus(-1)
	for view in _views:
		if view != null and is_instance_valid(view):
			view.visible = false
	_picked = card
	_before_view = _new_view(card)
	_after_view = _new_view(card.tempered)
	if _before_view == null or _after_view == null:
		return
	for view: CardView in [_before_view, _after_view]:
		view.hover_enabled = false
	mark_changes(_before_view, _after_view)
	_mode = Mode.PREVIEW
	_mouse_on = -1
	_relayout()

func _back_to_grid() -> void:
	_clear_preview()
	_mode = Mode.GRID
	for view in _views:
		if view != null and is_instance_valid(view):
			view.visible = true
	_mouse_on = -1
	_relayout()

# TEMPER: the Glassbone spent and the card swapped, then the tempered card
# alone, centred, under the held line - and back.
func _temper() -> void:
	if _picked == null or _wagon == null:
		return
	var tempered: CardData = RunState.temper_card(_picked, _cost())
	if tempered == null:
		return
	print("WagonScreen: tempered '%s' into '%s' (Glassbone %d)." % [_picked.card_name, tempered.card_name, RunState.glassbone])
	_mode = Mode.HELD
	_set_focus(-1)
	if _before_view != null and is_instance_valid(_before_view):
		_before_view.visible = false
	_refresh()
	_held_tween = create_tween()
	if _after_view != null and is_instance_valid(_after_view):
		_held_tween.tween_property(_after_view, "position", _preview_position(0.0), held_slide_sec).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_held_tween.tween_interval(maxf(_wagon.held_seconds - held_slide_sec, 0.0))
	_held_tween.tween_callback(_enter_rest_mode)

func _on_temper_changed() -> void:
	if _mode == Mode.GRID or _mode == Mode.EMPTY:
		_enter_rest_mode()
	else:
		_refresh()

# --- Changes on the tempered face ---

# On `after`'s face, a hairline under what differs from `before`'s: each
# number that changed in a line otherwise the same, the whole of a line
# that changed in its words or that `before` doesn't have ([u] in the
# rules text - the face's own ink, at its own size), and the cost (a 1 px
# line under its numeral, cost_mark_gap_px below the baseline).
func mark_changes(before: CardView, after: CardView) -> void:
	var old_lines: PackedStringArray = before.rules_text.get_parsed_text().split("
")
	var new_lines: PackedStringArray = after.rules_text.get_parsed_text().split("
")
	var bbcode: PackedStringArray = after.rules_text.text.split("
")
	if bbcode.size() == new_lines.size():
		for i in new_lines.size():
			if i < old_lines.size() and old_lines[i] == new_lines[i]:
				continue
			var changed: Array[int] = []
			if i < old_lines.size():
				changed = _changed_numbers(old_lines[i], new_lines[i])
			if changed.is_empty():
				bbcode[i] = "[u]%s[/u]" % bbcode[i]
			else:
				bbcode[i] = _underline_numbers(bbcode[i], changed)
		after.rules_text.text = "
".join(bbcode)
	else:
		push_warning("WagonScreen: '%s' rules text doesn't split into its lines; no hairlines under it." % after.card_data.card_name)
	if before.card_data.cost != after.card_data.cost:
		_cost_mark = Control.new()
		_cost_mark.name = "CostMark"
		_cost_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cost_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		_cost_mark.draw.connect(_draw_cost_mark.bind(after))
		after.add_child(_cost_mark)

# Width -1: one screen pixel at any scale the card is drawn at.
func _draw_cost_mark(after: CardView) -> void:
	if _cost_mark == null:
		return
	var label: Label = after.cost_label
	var y: float = after.header_baseline_px + cost_mark_gap_px
	_cost_mark.draw_line(Vector2(label.position.x, y), Vector2(label.position.x + label.size.x, y), after.ink_color, -1.0)

# Which numbers (by order in the line) differ, when the two lines are the
# same words round them; empty when the words differ too, or nothing does.
static func _changed_numbers(old_line: String, new_line: String) -> Array[int]:
	var changed: Array[int] = []
	var digits := RegEx.create_from_string("\\d+")
	if digits.sub(old_line, "#", true) != digits.sub(new_line, "#", true):
		return changed
	var old_numbers: Array[RegExMatch] = digits.search_all(old_line)
	var new_numbers: Array[RegExMatch] = digits.search_all(new_line)
	for k in new_numbers.size():
		if old_numbers[k].get_string() != new_numbers[k].get_string():
			changed.append(k)
	return changed

# The BBCode line with the given numbers (by order, counting only digits
# outside [tags]) wrapped in [u].
static func _underline_numbers(line: String, which: Array[int]) -> String:
	var out: String = ""
	var index: int = 0
	var number: int = 0
	while index < line.length():
		var c: String = line[index]
		if c == "[":
			var close: int = line.find("]", index)
			if close < 0:
				out += line.substr(index)
				break
			out += line.substr(index, close - index + 1)
			index = close + 1
			continue
		if c >= "0" and c <= "9":
			var end: int = index
			while end < line.length() and line[end] >= "0" and line[end] <= "9":
				end += 1
			var run: String = line.substr(index, end - index)
			out += ("[u]%s[/u]" % run) if which.has(number) else run
			number += 1
			index = end
			continue
		out += c
		index += 1
	return out

# --- Layout ---

func _card_size() -> Vector2:
	for view: CardView in [_before_view, _after_view]:
		if view != null and is_instance_valid(view):
			return view.card_size
	for view in _views:
		if view != null and is_instance_valid(view):
			return view.card_size
	return Vector2(200.0, 280.0)

func _relayout() -> void:
	if _draw_layer == null or not is_node_ready():
		return
	var window: Vector2 = _draw_layer.size
	_fit = maxf(window.y / maxf(reference_height, 1.0), 0.01)
	_label_px = maxi(roundi(float(label_size_px) * _fit), 1)
	_count_px = maxi(roundi(float(count_size_px) * _fit), 1)
	_line_px = maxi(roundi(float(line_size_px) * _fit), 1)
	_line_font = InkType.numeral_font()
	_label_font = InkType.tracked(InkType.text_bold_font(), _label_px, label_tracking_em)
	_count_font = InkType.tracked(InkType.text_bold_font(), _count_px, label_tracking_em)
	match _mode:
		Mode.GRID:
			_layout_grid()
		Mode.PREVIEW, Mode.HELD:
			_layout_preview()
	_refresh()

# The largest scale up to grid_card_scale at which every card fits the
# grid's area, the rows centred.
func _layout_grid() -> void:
	if _views.is_empty():
		return
	var window: Vector2 = _draw_layer.size
	var card_size: Vector2 = _card_size()
	var area := Vector2(window.x * max_width_fraction, window.y * (grid_bottom_fraction - grid_top_fraction))
	var count: int = _views.size()
	var face_scale: float = grid_card_scale * _fit
	var columns: int = 1
	var rows: int = 1
	for _attempt in 60:
		var card: Vector2 = card_size * face_scale
		var gap: float = card.x * grid_gap_fraction
		columns = clampi(int((area.x + gap) / (card.x + gap)), 1, count)
		rows = ceili(float(count) / float(columns))
		if float(rows) * card.y + float(rows - 1) * gap <= area.y or face_scale < 0.05:
			break
		face_scale *= 0.95
	var card_px: Vector2 = card_size * face_scale
	var gap_px: float = card_px.x * grid_gap_fraction
	var block_height: float = float(rows) * card_px.y + float(rows - 1) * gap_px
	var top: float = roundf(window.y * grid_top_fraction + (area.y - block_height) / 2.0)
	var pivot_shift: Vector2 = (card_size * 0.5) * (face_scale - 1.0)
	for index in count:
		@warning_ignore("integer_division")
		var row: int = index / columns
		var column: int = index % columns
		var in_row: int = mini(columns, count - row * columns)
		var row_width: float = float(in_row) * card_px.x + float(in_row - 1) * gap_px
		var left: float = roundf((window.x - row_width) / 2.0 + float(column) * (card_px.x + gap_px))
		var view: CardView = _views[index]
		view.position = Vector2(left, roundf(top + float(row) * (card_px.y + gap_px))) + pivot_shift
		view.set_rest_offset(view.position.y)
		view.set_base_scale(face_scale)

# `slot` -1 the left card, 1 the right, 0 the centre.
func _preview_position(slot: float) -> Vector2:
	var window: Vector2 = _draw_layer.size
	var card_size: Vector2 = _card_size()
	var face_scale: float = preview_card_scale * _fit
	var card: Vector2 = card_size * face_scale
	var gap: float = card.x * preview_gap_fraction
	var centre := Vector2(window.x * 0.5 + slot * (card.x + gap) * 0.5, window.y * preview_centre_fraction)
	var pivot_shift: Vector2 = (card_size * 0.5) * (face_scale - 1.0)
	return (centre - card * 0.5).round() + pivot_shift

func _layout_preview() -> void:
	var face_scale: float = preview_card_scale * _fit
	if _before_view != null and is_instance_valid(_before_view):
		_before_view.position = _preview_position(-1.0)
		_before_view.set_rest_offset(_before_view.position.y)
		_before_view.set_base_scale(face_scale)
	if _after_view != null and is_instance_valid(_after_view):
		_after_view.position = _preview_position(0.0 if _mode == Mode.HELD else 1.0)
		_after_view.set_rest_offset(_after_view.position.y)
		_after_view.set_base_scale(face_scale)

func _line_baseline(index: int) -> float:
	var fraction: float = leave_baseline_fraction if index == LEAVE_INDEX else actions_baseline_fraction
	return roundf(_draw_layer.size.y * fraction)

func _line_label(index: int) -> String:
	match index:
		TEMPER_INDEX:
			return temper_text
		BACK_INDEX:
			return back_text
	return leave_text

# Centred alone (LEAVE); TEMPER and BACK as a pair centred on the screen,
# actions_gap_px apart.
func _line_left(index: int) -> float:
	var window_x: float = _draw_layer.size.x
	if index == LEAVE_INDEX:
		return roundf((window_x - _line_width(index)) / 2.0)
	var gap: float = actions_gap_px * _fit
	var pair: float = _line_width(TEMPER_INDEX) + gap + _line_width(BACK_INDEX)
	var left: float = roundf((window_x - pair) / 2.0)
	return left if index == TEMPER_INDEX else roundf(left + _line_width(TEMPER_INDEX) + gap)

func _line_width(index: int) -> float:
	return InkType.width(_label_font, _line_label(index), _label_px)

# The line and the hairline's room to its left.
func _line_rect(index: int) -> Rect2:
	var left: float = _line_left(index) - (hairline_gap_px + hairline_length_px) * _fit
	var right: float = _line_left(index) + _line_width(index)
	return Rect2(left, _line_baseline(index) - float(_label_px), right - left, float(_label_px) * 1.3)

func _lines() -> Array[int]:
	match _mode:
		Mode.PREVIEW:
			return [TEMPER_INDEX, BACK_INDEX, LEAVE_INDEX]
		Mode.HELD:
			return []
	return [LEAVE_INDEX]

# --- Draw ---

func _refresh() -> void:
	if _draw_layer != null:
		_draw_layer.queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()

# One bone run over its ink outline, the outline carrying the run's alpha.
func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

func _text_centred(font: Font, text: String, baseline: float, size_px: int, color: Color) -> void:
	var width: float = InkType.width(font, text, size_px)
	_text(font, text, Vector2(roundf((_draw_layer.size.x - width) / 2.0), baseline), size_px, color)

func _draw_screen() -> void:
	if _closing or _label_font == null:
		return
	_text_centred(_count_font, count_format % RunState.glassbone, roundf(_draw_layer.size.y * count_baseline_fraction), _count_px, bone)
	_text_centred(_line_font, get_world_line(), roundf(_draw_layer.size.y * line_baseline_fraction), _line_px, bone)
	for index in _lines():
		_draw_line(index)

func _draw_line(index: int) -> void:
	var focused: bool = _focus == index
	var left: float = _line_left(index)
	var baseline: float = _line_baseline(index)
	_text(_label_font, _line_label(index), Vector2(left, baseline), _label_px, bone if focused else unfocused_color)
	if focused:
		var mid: float = baseline - float(_label_px) * 0.35
		var length: float = hairline_length_px * _fit
		_draw_layer.draw_rect(Rect2(left - hairline_gap_px * _fit - length, mid - hairline_thickness_px * 0.5, length, hairline_thickness_px), bone)

# The preview's arrow, over the scrim between the two faces.
func _draw_overlay() -> void:
	if _closing or _mode != Mode.PREVIEW:
		return
	var card: Vector2 = _card_size() * preview_card_scale * _fit
	var gap: float = card.x * preview_gap_fraction
	var centre := Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y * preview_centre_fraction)
	var half: float = gap * arrow_length_fraction * 0.5
	var tail := Vector2(roundf(centre.x - half), roundf(centre.y))
	var tip := Vector2(roundf(centre.x + half), roundf(centre.y))
	_overlay.draw_line(tail, tip, arrow_color, arrow_width_px, true)
	var head: float = arrow_head_px * _fit
	var angle: float = deg_to_rad(arrow_head_degrees)
	for side: float in [-1.0, 1.0]:
		_overlay.draw_line(tip, tip + Vector2(-cos(angle), side * sin(angle)) * head, arrow_color, arrow_width_px, true)

# The world-voice line this state says.
func get_world_line() -> String:
	if _wagon == null:
		return ""
	if _mode == Mode.HELD:
		return _wagon.held_line
	return _wagon.working_line if _can_temper() or _mode == Mode.PREVIEW else _wagon.empty_line

# --- Focus ---

func _focusable(index: int) -> bool:
	if index >= 0 and index < _cards.size():
		return _mode == Mode.GRID and can_pick(_cards[index])
	return _lines().has(index)

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	if _focus >= 0 and _focus < _views.size() and is_instance_valid(_views[_focus]):
		_views[_focus].set_hovered(false)
	_focus = index
	if _focus >= 0 and _focus < _views.size() and is_instance_valid(_views[_focus]):
		_views[_focus].set_hovered(true)
	_refresh()

# The next pickable grid card from `from` stepping `step`, wrapping; -1
# when none is.
func _grid_step(from: int, step: int) -> int:
	var count: int = _cards.size()
	var start: int = from if from >= 0 else (-1 if step > 0 else count)
	for i in count:
		var index: int = posmod(start + step * (i + 1), count)
		if _focusable(index):
			return index
	return -1

func _on_card_mouse_entered(index: int) -> void:
	if _input_open() and _focusable(index):
		_set_focus(index)

func _on_card_mouse_exited(index: int) -> void:
	if _input_open() and _focus == index:
		_set_focus(-1)

func _input_open() -> bool:
	return not _closing and _mode != Mode.HELD

func _line_hit(position: Vector2) -> int:
	for index in _lines():
		if _line_rect(index).has_point(position):
			return index
	return -1

func _on_gui_input(event: InputEvent) -> void:
	if not _input_open():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _line_hit(motion.position)
		if under != _mouse_on:
			if under >= 0:
				_set_focus(under)
			elif _focus == _mouse_on:
				_set_focus(-1)
			_mouse_on = under
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_activate(BACK_INDEX if _mode == Mode.PREVIEW else LEAVE_INDEX)
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _line_hit(button.position)
		if index >= 0:
			_activate(index)
		_draw_layer.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	# HELD swallows the keys, Escape included: no leaving mid-temper.
	if _mode == Mode.HELD:
		if event is InputEventKey or event is InputEventAction:
			get_viewport().set_input_as_handled()
		return
	var on_grid: bool = _focus >= 0 and _focus < _cards.size()
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var step: int = 1 if event.is_action_pressed("ui_right") else -1
		if _mode == Mode.PREVIEW:
			_set_focus(BACK_INDEX if _focus == TEMPER_INDEX else TEMPER_INDEX)
		elif _mode == Mode.GRID:
			_set_focus(_grid_step(_focus if on_grid else -1, step))
	elif event.is_action_pressed("ui_down"):
		_set_focus(LEAVE_INDEX)
	elif event.is_action_pressed("ui_up"):
		if _focus == LEAVE_INDEX:
			if _mode == Mode.PREVIEW:
				_set_focus(TEMPER_INDEX)
			elif _mode == Mode.GRID:
				_set_focus(_grid_step(-1, 1))
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_focus)
	elif event.is_action_pressed("ui_cancel"):
		_activate(LEAVE_INDEX)
	else:
		return
	get_viewport().set_input_as_handled()

# --- Acting ---

func _on_card_clicked(_card_data: CardData, index: int) -> void:
	if _input_open() and _mode == Mode.GRID:
		_activate(index)

func _activate(index: int) -> void:
	if not _input_open():
		return
	match index:
		LEAVE_INDEX:
			close()
		BACK_INDEX:
			if _mode == Mode.PREVIEW:
				_back_to_grid()
		TEMPER_INDEX:
			if _mode == Mode.PREVIEW:
				_temper()
		_:
			if _mode == Mode.GRID and index >= 0 and index < _cards.size():
				_open_preview(index)

# LEAVE, ui_cancel or a right click: the screen goes and the field comes
# back (RegionField._on_wagon_screen_closed()). Never while HELD.
func close() -> void:
	if _closing or _mode == Mode.HELD:
		return
	_closing = true
	closed.emit()
	queue_free()

# For probes: the state as a name, the grid's cards in order (empty
# outside GRID), and the card a preview holds.
func get_mode() -> String:
	return String(Mode.find_key(_mode))

func get_grid_cards() -> Array[CardData]:
	if _mode != Mode.GRID:
		return []
	return _cards.duplicate()

func get_picked() -> CardData:
	return _picked
