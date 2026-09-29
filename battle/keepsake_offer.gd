extends CanvasLayer
class_name KeepsakeOffer

# A keepsake put in front of the Wanderer, as one choice over the field -
# the same scrim-and-freeze BelongingsScreen uses: RegionField freezes the
# field under it (see RegionField.open_keepsake_offer()), and this layer
# runs ALWAYS on layer 100.
#
# One column, centred: the header, the offered keepsake's name in
# Spectral and what it does (TrinketData.describe()) in Alegreya Sans,
# bone over the scrim with the reward screen's ink outline. With the slot
# already full, the held one follows under HELD, drawn down in the
# utility grey - the thing that would be left behind. No icon, no box,
# no rarity colour.
#
# Two choices under the column, the title menu's focus language (utility
# grey at rest; bone with the short hairline to the left when focused):
#   empty slot  TAKE / LEAVE  - take it, or leave it where it lies
#   full slot   TAKE / KEEP   - take it and leave the held one, or keep
#                               the held one and leave this
# There is never more than one keepsake. The mouse focuses by hovering
# and activates by clicking; ui_up/ui_down move (wrapping), ui_accept
# activates. ui_cancel and a right click anywhere are the second choice.
# Nothing is focused until the mouse or a key says so. Either choice is
# final: the offer is spent (RunState.note_keepsake_offered() ran when it
# was rolled).
#
# The scrim, the outlined text and the hairline are copies of
# RewardScreen's own - the fifth copy of the focus drawing; the shared
# extraction is deferred (see DESIGN.md).

# True when the offered keepsake was taken.
signal closed(taken: bool)

enum Choice { TAKE, DECLINE }

const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.40):
	set(value):
		scrim_color = value
		if _scrim != null:
			_scrim.color = scrim_color
# Bone - the on-dark ink of the theme's own pair.
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		bone = value
		_refresh()
# The 1 px outline under every run (RewardScreen's legibility treatment
# for text sitting over the dimmed world).
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_refresh()
@export var text_outline_px: int = 1:
	set(value):
		text_outline_px = value
		_refresh()
# The title menu's unfocused item: CardView's keyline_utility. Also the
# held keepsake's colour - it is what the other choice leaves.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_refresh()

@export_group("Column")
@export var column_width_px: float = 420.0:
	set(value):
		column_width_px = value
		_refresh()
@export var header_text: String = "KEEPSAKE":
	set(value):
		header_text = value
		_refresh()
@export var held_text: String = "HELD":
	set(value):
		held_text = value
		_refresh()
# The header's baseline, as a fraction of the viewport height - the
# column hangs from it, above the frozen Wanderer (head near y 0.57).
@export_range(0.0, 1.0) var header_baseline_fraction: float = 0.16:
	set(value):
		header_baseline_fraction = value
		_refresh()
@export var caps_size_px: int = 22:
	set(value):
		caps_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var caps_tracking_em: float = 0.16:
	set(value):
		caps_tracking_em = value
		_rebuild_fonts()
@export var name_size_px: int = 34:
	set(value):
		name_size_px = value
		_refresh()
@export var description_size_px: int = 20:
	set(value):
		description_size_px = value
		_refresh()
# Baseline to baseline, in ems of each run's own size.
@export var line_pitch_em: float = 1.3:
	set(value):
		line_pitch_em = value
		_refresh()
# Header to name, name to description, description to the HELD block.
@export var header_gap_px: float = 22.0:
	set(value):
		header_gap_px = value
		_refresh()
@export var block_gap_px: float = 36.0:
	set(value):
		block_gap_px = value
		_refresh()
@export_group("")

@export_group("Choices")
@export var take_text: String = "TAKE":
	set(value):
		take_text = value
		_refresh()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_refresh()
@export var keep_text: String = "KEEP":
	set(value):
		keep_text = value
		_refresh()
# The first choice's baseline, as a fraction of the viewport height -
# under the frozen Wanderer's feet (near y 0.72).
@export_range(0.0, 1.0) var choices_baseline_fraction: float = 0.80:
	set(value):
		choices_baseline_fraction = value
		_refresh()
@export var choice_gap_px: float = 14.0:
	set(value):
		choice_gap_px = value
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
@export var take_volume_db: float = -18.0
@export_group("")

var _offered: TrinketData = null
var _held: TrinketData = null

var _scrim: ColorRect = null
var _draw_layer: Control = null
var _caps_font: Font = null
var _name_font: Font = null
var _text_font: Font = null

# A Choice, or -1 for nothing. _mouse_on is what the mouse is over, so
# leaving it clears only a mouse focus.
var _focus: int = -1
var _mouse_on: int = -1
var _done: bool = false

# Called by RegionField before the offer enters the tree. `held` is the
# keepsake already in the slot, or null.
func setup(offered: TrinketData, held: TrinketData) -> void:
	_offered = offered
	_held = held

func _ready() -> void:
	# The field is frozen under this; this layer has to opt out of the
	# freeze or stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_rebuild_fonts()

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field and order the Wanderer off.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Column"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_column)
	_draw_layer.resized.connect(_refresh)
	add_child(_draw_layer)

	if _offered == null:
		push_warning("KeepsakeOffer: nothing to offer; closing.")
		_finish(false)
		return
	_refresh()

func _rebuild_fonts() -> void:
	_caps_font = InkType.tracked(InkType.text_bold_font(), caps_size_px, caps_tracking_em)
	_name_font = InkType.numeral_font()
	_text_font = InkType.text_font()
	_refresh()

func _refresh() -> void:
	if _draw_layer != null:
		_draw_layer.queue_redraw()

func _choice_label(index: int) -> String:
	if index == Choice.TAKE:
		return take_text
	return keep_text if _held != null else leave_text

# --- Layout ---

func _column_left() -> float:
	return roundf((_draw_layer.size.x - column_width_px) / 2.0)

func _choice_baseline(index: int) -> float:
	return roundf(_draw_layer.size.y * choices_baseline_fraction + float(index) * (float(caps_size_px) + choice_gap_px))

func _choice_label_left(index: int) -> float:
	return roundf((_draw_layer.size.x - InkType.width(_caps_font, _choice_label(index), caps_size_px)) / 2.0)

# The label and the hairline's room to its left.
func _choice_rect(index: int) -> Rect2:
	var label_left: float = _choice_label_left(index)
	var left: float = label_left - hairline_gap_px - hairline_length_px
	var right: float = label_left + InkType.width(_caps_font, _choice_label(index), caps_size_px)
	return Rect2(left, _choice_baseline(index) - float(caps_size_px), right - left, float(caps_size_px) * 1.3)

# --- Draw ---

# One run over its ink outline, the outline carrying the run's alpha.
func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

# A run centred in the column.
func _centred(font: Font, text: String, baseline: float, size_px: int, color: Color) -> void:
	var left: float = _column_left() + roundf((column_width_px - InkType.width(font, text, size_px)) / 2.0)
	_text(font, text, Vector2(left, baseline), size_px, color)

# Wrapped at the column's width, each line centred, the first baseline at
# `baseline`. Returns the last line's baseline.
func _wrapped(font: Font, text: String, baseline: float, size_px: int, color: Color) -> float:
	var paragraph := TextParagraph.new()
	paragraph.width = column_width_px
	paragraph.add_string(text, font, size_px)
	var pitch: float = roundf(float(size_px) * line_pitch_em)
	var y: float = baseline
	for line_index in paragraph.get_line_count():
		var line_range: Vector2i = paragraph.get_line_range(line_index)
		_centred(font, text.substr(line_range.x, line_range.y - line_range.x).strip_edges(), y, size_px, color)
		y += pitch
	return y - pitch

# One keepsake: its name, then what it does under it. Returns the last
# line's baseline.
func _draw_trinket(trinket: TrinketData, baseline: float, color: Color) -> float:
	_centred(_name_font, trinket.display_name, baseline, name_size_px, color)
	var description_top: float = baseline + roundf(float(description_size_px) * line_pitch_em) + 4.0
	return _wrapped(_text_font, trinket.describe(), description_top, description_size_px, color)

# The header, the offered keepsake, the held one if any, then the choices.
func _draw_column() -> void:
	if _done or _offered == null:
		return
	var y: float = roundf(_draw_layer.size.y * header_baseline_fraction)
	_centred(_caps_font, header_text, y, caps_size_px, bone)
	y += header_gap_px + float(name_size_px)
	y = _draw_trinket(_offered, y, bone)
	if _held != null:
		y += block_gap_px + float(caps_size_px)
		_centred(_caps_font, held_text, y, caps_size_px, unfocused_color)
		y += header_gap_px + float(name_size_px)
		_draw_trinket(_held, y, unfocused_color)

	for index in 2:
		var focused: bool = _focus == index
		var label_left: float = _choice_label_left(index)
		var baseline: float = _choice_baseline(index)
		_text(_caps_font, _choice_label(index), Vector2(label_left, baseline), caps_size_px, bone if focused else unfocused_color)
		if focused:
			var mid: float = baseline - float(caps_size_px) * 0.35
			var left: float = label_left - hairline_gap_px - hairline_length_px
			_draw_layer.draw_rect(Rect2(left, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

# --- Input ---

func _hit(position: Vector2) -> int:
	for index in 2:
		if _choice_rect(index).has_point(position):
			return index
	return -1

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	_focus = index
	_draw_layer.queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if _done:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _hit(motion.position)
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
		_activate(Choice.DECLINE)
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _hit(button.position)
		if index >= 0:
			_activate(index)
		_draw_layer.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_down"):
		_set_focus(posmod(_focus + 1, 2) if _focus >= 0 else Choice.TAKE)
	elif event.is_action_pressed("ui_up"):
		_set_focus(posmod(_focus - 1, 2) if _focus >= 0 else Choice.DECLINE)
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_focus)
	elif event.is_action_pressed("ui_cancel"):
		_activate(Choice.DECLINE)
	else:
		return
	get_viewport().set_input_as_handled()

# The one gate: the first activation wins. TAKE puts the offered keepsake
# in the slot - whatever was there is left behind; the other choice
# changes nothing.
func _activate(index: int) -> void:
	if _done:
		return
	_done = true
	_draw_layer.queue_redraw()
	if index == Choice.TAKE:
		RunState.equip_keepsake(_offered)
		TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "KeepsakeTakeAudio", "KeepsakeOffer")
		print("KeepsakeOffer: took '%s'%s." % [_offered.display_name, " (left '%s')" % _held.display_name if _held != null else ""])
		_finish(true)
		return
	print("KeepsakeOffer: left '%s'%s." % [_offered.display_name, " (kept '%s')" % _held.display_name if _held != null else ""])
	_finish(false)

func _finish(taken: bool) -> void:
	closed.emit(taken)
	queue_free()
