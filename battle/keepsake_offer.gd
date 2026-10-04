extends CanvasLayer
class_name KeepsakeOffer

# Keepsake Found: a dropped keepsake shown as the object it is, on its
# own panel, after the normal reward has closed (see RegionField.open_
# keepsake_offer()). A different class of reward from the card choice -
# never in its grid. The field is frozen under it and a scrim dims it;
# this layer runs ALWAYS on layer 100.
#
# The panel is card stock - the card's bone paper (card_paper_material),
# a charcoal frame, a soft shadow - and reads top to bottom:
#   KEEPSAKE FOUND   small tracked caps, a printed rule under it
#   the object       TrinketData.art, large and centred - the first thing
#                    the eye lands on - over a soft contact shadow
#   its name         Spectral, directly under the object
#   Dropped by ...   quiet, only when the drop has a named source
#   what it does     one line, TrinketData.describe()
#   CURRENTLY HELD   a much smaller strip under a rule: the held keepsake's
#                    small art, name and short line (describe_short()) -
#                    or "Keepsake slot empty"
#   the actions      TAKE, the primary (an ink-filled plate), and KEEP
#                    CURRENT - or LEAVE on an empty slot - as quieter text
# No glow, no rarity colour, no ornament: the object, the hierarchy and
# what it would replace are the whole of the excitement.
#
# TAKE puts it in the slot at once - whatever was held is gone for the
# run - and closes; the other choice leaves it behind and closes. No
# confirmation, and no inventory of unheld keepsakes. The mouse focuses by
# hovering and activates by clicking; ui_left/ui_right and ui_up/ui_down
# move between the two, ui_accept activates; ui_cancel and a right click
# anywhere are the second choice. Nothing is focused until the mouse or a
# key says so.
#
# Opening is a quiet reveal: the panel fades in and the object settles
# from a hair smaller. Nothing else moves.

# True when the offered keepsake was taken.
signal closed(taken: bool)

enum Choice { TAKE, DECLINE }

const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const PAPER_MATERIAL_PATH := "res://battle/card_paper_material.tres"

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.40):
	set(value):
		scrim_color = value
		if _scrim != null:
			_scrim.color = scrim_color
# The card's field colour and its ink (CardView.field_color, the frame).
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		bone = value
		_refresh()
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_refresh()
# The title menu's unfocused item: CardView's keyline_utility.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_refresh()

@export_group("Panel")
@export var panel_size_px: Vector2 = Vector2(560.0, 800.0):
	set(value):
		panel_size_px = value
		_layout()
@export var corner_radius_px: int = 6:
	set(value):
		corner_radius_px = value
		_refresh()
@export_range(0.0, 1.0) var frame_alpha: float = 0.88:
	set(value):
		frame_alpha = value
		_refresh()
# The thin rules between the panel's sections.
@export_range(0.0, 1.0) var rule_alpha: float = 0.25:
	set(value):
		rule_alpha = value
		_refresh()
@export var side_padding_px: float = 44.0:
	set(value):
		side_padding_px = value
		_refresh()
@export var shadow_size_px: int = 18:
	set(value):
		shadow_size_px = value
		_refresh_shadow()
@export_range(0.0, 1.0) var shadow_alpha: float = 0.22:
	set(value):
		shadow_alpha = value
		_refresh_shadow()
@export var shadow_offset_px: float = 6.0:
	set(value):
		shadow_offset_px = value
		_refresh_shadow()
@export_group("")

@export_group("Header")
@export var header_text: String = "KEEPSAKE FOUND":
	set(value):
		header_text = value
		_refresh()
@export var header_size_px: int = 14:
	set(value):
		header_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var caps_tracking_em: float = 0.16:
	set(value):
		caps_tracking_em = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var label_alpha: float = 0.62:
	set(value):
		label_alpha = value
		_refresh()
@export var header_baseline_px: float = 46.0:
	set(value):
		header_baseline_px = value
		_layout()
@export var header_rule_gap_px: float = 16.0:
	set(value):
		header_rule_gap_px = value
		_layout()
@export_group("")

@export_group("Object")
# The object's square. The object, its name, source and description are
# one block, centred between the header rule and the held strip - never
# closer to the header rule than art_top_gap_px.
@export var art_size_px: float = 300.0:
	set(value):
		art_size_px = value
		_layout()
@export var art_top_gap_px: float = 22.0:
	set(value):
		art_top_gap_px = value
		_layout()
# The contact shadow under the object: an ellipse this wide (of the
# object's own width) and tall, at this alpha, its centre this far below
# the object's lowest opaque pixel.
@export_range(0.0, 1.0) var art_shadow_width: float = 0.8:
	set(value):
		art_shadow_width = value
		_refresh()
@export var art_shadow_height_px: float = 26.0:
	set(value):
		art_shadow_height_px = value
		_refresh()
@export_range(0.0, 1.0) var art_shadow_alpha: float = 0.16:
	set(value):
		art_shadow_alpha = value
		_refresh()
@export var art_shadow_lift_px: float = 10.0:
	set(value):
		art_shadow_lift_px = value
		_refresh()
@export var name_size_px: int = 38:
	set(value):
		name_size_px = value
		_layout()
@export var name_gap_px: float = 48.0:
	set(value):
		name_gap_px = value
		_layout()
@export var source_format: String = "Dropped by %s":
	set(value):
		source_format = value
		_layout()
@export var source_size_px: int = 15:
	set(value):
		source_size_px = value
		_layout()
@export_range(0.0, 1.0) var source_alpha: float = 0.55:
	set(value):
		source_alpha = value
		_refresh()
@export var description_size_px: int = 19:
	set(value):
		description_size_px = value
		_layout()
@export var description_width_px: float = 430.0:
	set(value):
		description_width_px = value
		_layout()
@export var line_pitch_em: float = 1.3:
	set(value):
		line_pitch_em = value
		_layout()
@export_group("")

@export_group("Currently Held")
@export var held_text: String = "CURRENTLY HELD":
	set(value):
		held_text = value
		_refresh()
@export var empty_text: String = "Keepsake slot empty":
	set(value):
		empty_text = value
		_refresh()
@export var held_label_size_px: int = 12:
	set(value):
		held_label_size_px = value
		_rebuild_fonts()
@export var held_icon_px: float = 56.0:
	set(value):
		held_icon_px = value
		_refresh()
@export var held_name_size_px: int = 20:
	set(value):
		held_name_size_px = value
		_refresh()
@export var held_line_size_px: int = 15:
	set(value):
		held_line_size_px = value
		_refresh()
@export_range(0.0, 1.0) var held_line_alpha: float = 0.72:
	set(value):
		held_line_alpha = value
		_refresh()
# The strip and the actions hang from the panel's foot: the actions'
# rule this far above the actions' centre line, the strip this tall
# above that rule.
@export var actions_rule_gap_px: float = 68.0:
	set(value):
		actions_rule_gap_px = value
		_layout()
@export var held_strip_height_px: float = 118.0:
	set(value):
		held_strip_height_px = value
		_layout()
@export_group("")

@export_group("Actions")
@export var take_text: String = "TAKE":
	set(value):
		take_text = value
		_refresh()
@export var keep_text: String = "KEEP CURRENT":
	set(value):
		keep_text = value
		_refresh()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_refresh()
@export var action_size_px: int = 17:
	set(value):
		action_size_px = value
		_rebuild_fonts()
@export var take_plate_size_px: Vector2 = Vector2(176.0, 48.0):
	set(value):
		take_plate_size_px = value
		_refresh()
@export var action_gap_px: float = 44.0:
	set(value):
		action_gap_px = value
		_refresh()
# The actions' centre line, this far up from the panel's foot.
@export var actions_lift_px: float = 64.0:
	set(value):
		actions_lift_px = value
		_refresh()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_refresh()
@export var take_volume_db: float = -18.0
@export_group("")

@export_group("Reveal")
@export var reveal_fade_sec: float = 0.22
@export var reveal_art_sec: float = 0.4
@export_range(0.5, 1.0) var reveal_art_start_scale: float = 0.94
@export_group("")

var _offered: TrinketData = null
var _held: TrinketData = null
var _source: String = ""

var _scrim: ColorRect = null
var _panel: Control = null
var _shadow: Panel = null
var _paper: Control = null
var _face: Control = null
var _art: Control = null
var _header_font: Font = null
var _held_label_font: Font = null
var _action_font: Font = null
var _name_font: Font = null
var _text_font: Font = null
var _shadow_ellipse: GradientTexture2D = null
var _paper_seed: float = 0.0

# Section positions in panel space, from _layout().
var _header_rule_y: float = 0.0
var _art_rect: Rect2 = Rect2()
# The object's opaque bounds inside _art_rect - what the contact shadow
# sits under, so a wide, low object isn't left floating over it.
var _object_rect: Rect2 = Rect2()
var _name_baseline: float = 0.0
var _source_baseline: float = 0.0
var _description: TextParagraph = null
var _description_top: float = 0.0
var _held_rule_y: float = 0.0
var _actions_rule_y: float = 0.0

# A Choice, or -1 for nothing. _mouse_on is what the mouse is over, so
# leaving it clears only a mouse focus.
var _focus: int = -1
var _mouse_on: int = -1
var _done: bool = false

# Called by RegionField before the offer enters the tree. `held` is the
# keepsake already in the slot, or null; `source` names where it came
# from ("Wardling") - empty for a drop with no named source, which shows
# no source line.
func setup(offered: TrinketData, held: TrinketData, source: String = "") -> void:
	_offered = offered
	_held = held
	_source = source

func _ready() -> void:
	# The field is frozen under this; this layer has to opt out of the
	# freeze or stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_paper_seed = randf()

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field and order the Wanderer off.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_gui_input)
	_scrim.resized.connect(_layout)
	add_child(_scrim)

	_panel = Control.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_shadow = Panel.new()
	_shadow.name = "Shadow"
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_shadow)

	_paper = Control.new()
	_paper.name = "Paper"
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.material = load(PAPER_MATERIAL_PATH) as Material
	_paper.draw.connect(_draw_paper)
	_panel.add_child(_paper)

	_art = Control.new()
	_art.name = "Object"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The art is drawn well under its size, like a card's (CardView).
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.draw.connect(_draw_art)
	_panel.add_child(_art)

	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_STOP
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.gui_input.connect(_on_face_gui_input)
	_face.draw.connect(_draw_face)
	_panel.add_child(_face)

	_shadow_ellipse = GradientTexture2D.new()
	_shadow_ellipse.fill = GradientTexture2D.FILL_RADIAL
	_shadow_ellipse.fill_from = Vector2(0.5, 0.5)
	_shadow_ellipse.fill_to = Vector2(1.0, 0.5)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	_shadow_ellipse.gradient = gradient

	_rebuild_fonts()
	_refresh_shadow()
	if _offered == null:
		push_warning("KeepsakeOffer: nothing to offer; closing.")
		_finish(false)
		return
	_layout()
	_reveal()

func _rebuild_fonts() -> void:
	_header_font = InkType.tracked(InkType.text_bold_font(), header_size_px, caps_tracking_em)
	_held_label_font = InkType.tracked(InkType.text_bold_font(), held_label_size_px, caps_tracking_em)
	_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, caps_tracking_em)
	_name_font = InkType.numeral_font()
	_text_font = InkType.text_font()
	_layout()

func _refresh() -> void:
	for canvas: Control in [_paper, _art, _face]:
		if canvas != null:
			canvas.queue_redraw()

func _refresh_shadow() -> void:
	if _shadow == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(bone, 0.0)
	style.set_corner_radius_all(corner_radius_px)
	style.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	style.shadow_size = shadow_size_px
	style.shadow_offset = Vector2(0.0, shadow_offset_px)
	_shadow.add_theme_stylebox_override("panel", style)

func _choice_label(index: int) -> String:
	if index == Choice.TAKE:
		return take_text
	return keep_text if _held != null else leave_text

# --- Layout (panel space) ---

func _layout() -> void:
	if _panel == null or _scrim == null or _offered == null:
		return
	var viewport_size: Vector2 = _scrim.size
	_panel.size = panel_size_px
	_panel.position = ((viewport_size - panel_size_px) / 2.0).round()
	for child: Control in [_shadow, _paper, _art, _face]:
		child.position = Vector2.ZERO
		child.size = panel_size_px

	_header_rule_y = header_baseline_px + header_rule_gap_px
	_actions_rule_y = roundf(_actions_centre_y() - actions_rule_gap_px)
	_held_rule_y = _actions_rule_y - held_strip_height_px

	_description = TextParagraph.new()
	_description.width = description_width_px
	_description.add_string(_offered.describe(), _text_font, description_size_px)
	var source_height: float = 0.0
	if not _source.is_empty():
		source_height = roundf(float(source_size_px) * line_pitch_em) + 4.0
	var block_height: float = art_size_px + name_gap_px + source_height + 14.0 + _pitch(description_size_px) * _description.get_line_count()
	var room: float = _held_rule_y - _header_rule_y
	var art_top: float = _header_rule_y + maxf(art_top_gap_px, roundf((room - block_height) / 2.0))
	_art_rect = Rect2(roundf((panel_size_px.x - art_size_px) / 2.0), art_top, art_size_px, art_size_px)
	_art.pivot_offset = _art_rect.get_center()
	_object_rect = _art_rect
	if _offered.art != null:
		var image: Image = _offered.art.get_image()
		if image != null and not image.is_empty():
			var used: Rect2i = image.get_used_rect()
			var to_panel: Vector2 = _art_rect.size / Vector2(image.get_size())
			_object_rect = Rect2(_art_rect.position + Vector2(used.position) * to_panel, Vector2(used.size) * to_panel)
	_name_baseline = _art_rect.end.y + name_gap_px
	_source_baseline = _name_baseline + source_height
	_description_top = _source_baseline + 14.0
	_refresh()

func _pitch(size_px: int) -> float:
	return roundf(float(size_px) * line_pitch_em)

func _actions_centre_y() -> float:
	return panel_size_px.y - actions_lift_px

func _take_rect() -> Rect2:
	var total: float = take_plate_size_px.x + action_gap_px + InkType.width(_action_font, _choice_label(Choice.DECLINE), action_size_px)
	var left: float = roundf((panel_size_px.x - total) / 2.0)
	return Rect2(left, roundf(_actions_centre_y() - take_plate_size_px.y / 2.0), take_plate_size_px.x, take_plate_size_px.y)

func _decline_rect() -> Rect2:
	var take: Rect2 = _take_rect()
	var width: float = InkType.width(_action_font, _choice_label(Choice.DECLINE), action_size_px)
	return Rect2(take.end.x + action_gap_px, take.position.y, width, take.size.y)

# --- Draw ---

func _draw_paper() -> void:
	# The card's own trick: the paper shader reads its seed from red.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_paper_seed, 0.0, 0.0, 1.0)
	style.set_corner_radius_all(corner_radius_px)
	_paper.draw_style_box(style, Rect2(Vector2.ZERO, panel_size_px))

func _draw_art() -> void:
	if _offered == null:
		return
	var shadow_width: float = _object_rect.size.x * art_shadow_width
	var shadow_centre := Vector2(_object_rect.get_center().x, _object_rect.end.y + art_shadow_lift_px)
	_art.draw_texture_rect(_shadow_ellipse, Rect2(shadow_centre.x - shadow_width / 2.0, shadow_centre.y - art_shadow_height_px / 2.0, shadow_width, art_shadow_height_px), false, Color(1.0, 1.0, 1.0, art_shadow_alpha))
	if _offered.art != null:
		_art.draw_texture_rect(_offered.art, _art_rect, false)

func _text_centred(canvas: CanvasItem, font: Font, text: String, baseline: float, size_px: int, color: Color) -> void:
	var left: float = roundf((panel_size_px.x - InkType.width(font, text, size_px)) / 2.0)
	InkType.draw_run(canvas, font, text, Vector2(left, baseline), size_px, color)

func _rule(y: float) -> void:
	var color: Color = ink
	color.a = rule_alpha
	_face.draw_rect(Rect2(side_padding_px, y, panel_size_px.x - side_padding_px * 2.0, hairline_thickness_px), color)

func _draw_face() -> void:
	if _offered == null:
		return
	var face_rect := Rect2(Vector2.ZERO, panel_size_px)
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(1)
	frame.border_color = Color(ink, frame_alpha)
	frame.set_corner_radius_all(corner_radius_px)
	_face.draw_style_box(frame, face_rect)

	var label: Color = Color(ink, label_alpha)
	_text_centred(_face, _header_font, header_text, header_baseline_px, header_size_px, label)
	_rule(_header_rule_y)

	_text_centred(_face, _name_font, _offered.display_name, _name_baseline, name_size_px, ink)
	if not _source.is_empty():
		_text_centred(_face, _text_font, source_format % _source, _source_baseline, source_size_px, Color(ink, source_alpha))
	# Each line centred by its own width - draw_line() doesn't apply the
	# paragraph's alignment.
	var y: float = _description_top
	for line_index in _description.get_line_count():
		y += _pitch(description_size_px)
		var line_left: float = roundf((panel_size_px.x - _description.get_line_width(line_index)) / 2.0)
		_description.draw_line(_face.get_canvas_item(), Vector2(line_left, y - _description.get_line_ascent(line_index)), line_index, ink)

	_rule(_held_rule_y)
	_draw_held_strip(label)
	_rule(_actions_rule_y)
	_draw_actions()

# The small comparison strip: what the slot holds now, secondary to the
# drop above it - or that it's empty.
func _draw_held_strip(label: Color) -> void:
	var top: float = _held_rule_y + 30.0
	_text_centred(_face, _held_label_font, held_text, top, held_label_size_px, label)
	if _held == null:
		_text_centred(_face, _text_font, empty_text, top + 40.0, held_line_size_px + 1, Color(ink, 0.55))
		return
	var name_width: float = InkType.width(_name_font, _held.display_name, held_name_size_px)
	var line_text: String = _held.describe_short()
	var line_width: float = InkType.width(_text_font, line_text, held_line_size_px)
	var text_width: float = maxf(name_width, line_width)
	var gap: float = 16.0
	var left: float = roundf((panel_size_px.x - (held_icon_px + gap + text_width)) / 2.0)
	var icon_top: float = top + 14.0
	if _held.art != null:
		_face.draw_texture_rect(_held.art, Rect2(left, icon_top, held_icon_px, held_icon_px), false)
	var text_left: float = left + held_icon_px + gap
	InkType.draw_run(_face, _name_font, _held.display_name, Vector2(text_left, icon_top + held_icon_px * 0.45), held_name_size_px, ink)
	InkType.draw_run(_face, _text_font, line_text, Vector2(text_left, icon_top + held_icon_px * 0.45 + float(held_line_size_px) + 8.0), held_line_size_px, Color(ink, held_line_alpha))

# TAKE on an ink plate - the primary; the other choice as quieter caps.
# Focus: a bone keyline inside the plate, or full ink and a hairline under
# the text.
func _draw_actions() -> void:
	var take: Rect2 = _take_rect()
	var plate := StyleBoxFlat.new()
	plate.bg_color = ink
	plate.set_corner_radius_all(3)
	_face.draw_style_box(plate, take)
	if _focus == Choice.TAKE:
		var inset := StyleBoxFlat.new()
		inset.draw_center = false
		inset.set_border_width_all(1)
		inset.border_color = Color(bone, 0.7)
		inset.set_corner_radius_all(2)
		_face.draw_style_box(inset, take.grow(-4.0))
	var take_width: float = InkType.width(_action_font, take_text, action_size_px)
	var baseline: float = roundf(_actions_centre_y() + float(action_size_px) * 0.35)
	InkType.draw_run(_face, _action_font, take_text, Vector2(roundf(take.get_center().x - take_width / 2.0), baseline), action_size_px, bone)

	var decline: Rect2 = _decline_rect()
	var focused: bool = _focus == Choice.DECLINE
	InkType.draw_run(_face, _action_font, _choice_label(Choice.DECLINE), Vector2(decline.position.x, baseline), action_size_px, ink if focused else unfocused_color)
	if focused:
		_face.draw_rect(Rect2(decline.position.x, baseline + 7.0, decline.size.x, hairline_thickness_px), ink)

# --- Reveal ---

func _reveal() -> void:
	_panel.modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(_panel, "modulate:a", 1.0, maxf(reveal_fade_sec, 0.01))
	_art.scale = Vector2.ONE * reveal_art_start_scale
	var settle: Tween = create_tween()
	settle.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	settle.tween_property(_art, "scale", Vector2.ONE, maxf(reveal_art_sec, 0.01))

# --- Input ---

func _hit(position: Vector2) -> int:
	if _take_rect().has_point(position):
		return Choice.TAKE
	if _decline_rect().grow(8.0).has_point(position):
		return Choice.DECLINE
	return -1

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	_focus = index
	_face.queue_redraw()

func _on_face_gui_input(event: InputEvent) -> void:
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
		_face.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _hit(button.position)
		if index >= 0:
			_activate(index)
		_face.accept_event()

# Off the panel only a right click means anything: the second choice.
func _on_scrim_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if _done or button == null or not button.pressed or button.button_index != MOUSE_BUTTON_RIGHT:
		return
	_activate(Choice.DECLINE)
	_scrim.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_set_focus(posmod(_focus + 1, 2) if _focus >= 0 else Choice.TAKE)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_set_focus(posmod(_focus - 1, 2) if _focus >= 0 else Choice.TAKE)
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_focus)
	elif event.is_action_pressed("ui_cancel"):
		_activate(Choice.DECLINE)
	else:
		return
	get_viewport().set_input_as_handled()

# The one gate: the first activation wins. TAKE puts the offered keepsake
# in the slot - whatever was held is gone; the other choice changes
# nothing.
func _activate(index: int) -> void:
	if _done:
		return
	_done = true
	RunLogger.event("keepsake_offer", {
		"source": RunLogger.or_null(_source),
		"offered": RunLogger.keepsake_id(_offered),
		"held": RunLogger.keepsake_id(_held),
		"taken": index == Choice.TAKE,
	})
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
