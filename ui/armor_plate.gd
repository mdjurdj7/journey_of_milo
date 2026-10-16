extends Control
class_name ArmorPlate

# One worn piece (TrinketData.slot WORN), shown the one way armor is
# shown: a landscape plate in the card family - the card's paper (card_
# paper_material), a thin charcoal frame, a soft shadow - never card-
# shaped. Top to bottom:
#   the object    TrinketData.art in a square window - or, with no art, a
#                 flat tone panel with the name's initial: a placeholder
#   its name      Spectral SemiBold, centred, in its rarity's finish - the
#                 cards' own (CardRarityFinish, card_name_finish.gdshader):
#                 flat ink for COMMON, the RARE base with its faint
#                 gradient, a sheen once when the plate opens (play_name_
#                 sheen()). Nothing else says rarity.
#   what it does  TrinketData.describe(), Alegreya Sans, centred
#   its lore      TrinketData.flavor_text in a slanted Spectral, grey,
#                 under a hairline - left out when it has none
#   what it costs with a piece already worn (set_replaced()), a grey
#                 "Replaces <name>: <effect>" line
#   the choice    with show_actions, TAKE and LEAVE side by side - the
#                 title menu's treatment (TitleMenu, WorldKeepsake): plain
#                 tracked caps, the focused one in ink with a short
#                 hairline to its left, the other in the utility grey. No
#                 buttons, no boxes, no glow.
#
# Drawn at plate_scale, not scaled, like KeepsakeTile: every size and gap
# multiplied out, so a large plate is as crisp as a small one; size
# follows the laid-out content. A second copy of KeepsakeTile's paper,
# frame and paragraph drawing rather than a shared helper - two consumers
# (CLAUDE.md on extracting at the third). Hosts - ArmorExamine, the HUD's
# WORN line, the battle row's hover - place it; with show_actions it takes
# the mouse and says `chosen`, otherwise it ignores it.

signal chosen(take: bool)

enum Choice { TAKE, LEAVE }

const PAPER_MATERIAL_PATH := "res://battle/card_paper_material.tres"
const LORE_FONT_PATH := "res://assets/fonts/Spectral-Light.ttf"

@export var plate_width: float = 460.0:
	set(value):
		plate_width = value
		_relayout()
@export var plate_scale: float = 1.0:
	set(value):
		plate_scale = maxf(value, 0.1)
		_relayout()
@export_file("*.tres") var rarity_finish_path: String = "res://battle/card_rarity_finish.tres"
@export_file("*.gdshader") var name_finish_shader_path: String = "res://battle/card_name_finish.gdshader"

@export_group("Look")
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_redraw()
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_redraw()
@export var corner_radius_px: int = 6:
	set(value):
		corner_radius_px = value
		_relayout()
@export_range(0.0, 1.0) var frame_alpha: float = 0.85:
	set(value):
		frame_alpha = value
		_redraw()
@export var shadow_size_px: int = 12:
	set(value):
		shadow_size_px = value
		_relayout()
@export_range(0.0, 1.0) var shadow_alpha: float = 0.2:
	set(value):
		shadow_alpha = value
		_relayout()
@export var shadow_offset_px: float = 4.0:
	set(value):
		shadow_offset_px = value
		_relayout()
@export var padding_px: float = 18.0:
	set(value):
		padding_px = value
		_relayout()
@export_range(0.0, 1.0) var hairline_alpha: float = 0.35:
	set(value):
		hairline_alpha = value
		_redraw()
@export_group("")

@export_group("Art")
@export var art_size_px: float = 96.0:
	set(value):
		art_size_px = value
		_relayout()
@export var placeholder_color: Color = Color(0.80, 0.77, 0.71, 1.0):
	set(value):
		placeholder_color = value
		_redraw()
@export var placeholder_initial_size_px: int = 44:
	set(value):
		placeholder_initial_size_px = value
		_redraw()
@export_range(0.0, 1.0) var placeholder_initial_alpha: float = 0.45:
	set(value):
		placeholder_initial_alpha = value
		_redraw()
@export_group("")

@export_group("Text")
@export var name_size_px: int = 21:
	set(value):
		name_size_px = value
		_relayout()
@export var name_gap_px: float = 12.0:
	set(value):
		name_gap_px = value
		_relayout()
@export var rules_size_px: int = 15:
	set(value):
		rules_size_px = value
		_relayout()
@export var rules_gap_px: float = 8.0:
	set(value):
		rules_gap_px = value
		_relayout()
@export var lore_size_px: int = 14:
	set(value):
		lore_size_px = value
		_relayout()
@export_range(0.0, 1.0) var lore_alpha: float = 0.6:
	set(value):
		lore_alpha = value
		_redraw()
@export var lore_slant: float = 0.18:
	set(value):
		lore_slant = value
		_lore_font = null
		_relayout()
# Between the rules and the hairline, and the hairline and the lore.
@export var lore_gap_px: float = 8.0:
	set(value):
		lore_gap_px = value
		_relayout()
@export var replaces_size_px: int = 13:
	set(value):
		replaces_size_px = value
		_relayout()
@export var replaces_gap_px: float = 12.0:
	set(value):
		replaces_gap_px = value
		_relayout()
@export var replaces_color: Color = Color(0.45, 0.45, 0.47, 1.0):
	set(value):
		replaces_color = value
		_redraw()
@export var replaces_format: String = "Replaces %s: %s":
	set(value):
		replaces_format = value
		_relayout()
@export var line_pitch_em: float = 1.3:
	set(value):
		line_pitch_em = value
		_relayout()
@export_group("")

@export_group("Choice")
@export var take_text: String = "TAKE":
	set(value):
		take_text = value
		_relayout()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_relayout()
@export var action_size_px: int = 15:
	set(value):
		action_size_px = value
		_action_font = null
		_relayout()
@export_range(0.0, 1.0) var caps_tracking_em: float = 0.16:
	set(value):
		caps_tracking_em = value
		_action_font = null
		_relayout()
@export var actions_gap_px: float = 16.0:
	set(value):
		actions_gap_px = value
		_relayout()
# Between the two choices' centres, each side of the plate's middle.
@export var action_spread_px: float = 70.0:
	set(value):
		action_spread_px = value
		_relayout()
@export var action_row_height_px: float = 30.0:
	set(value):
		action_row_height_px = value
		_relayout()
# The focus hairline: the title menu's, in proportion (WorldKeepsake's).
@export var focus_hairline_length_px: float = 18.0:
	set(value):
		focus_hairline_length_px = value
		_redraw()
@export var focus_hairline_gap_px: float = 9.0:
	set(value):
		focus_hairline_gap_px = value
		_redraw()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_redraw()
@export_group("")

var _piece: TrinketData = null
var _replaced: TrinketData = null
var _show_actions: bool = false
var _focus: int = Choice.TAKE

var _shadow: Panel = null
var _paper: Control = null
var _face: Control = null
# The name on its own canvas item: the finish shader reads its local x.
var _name_layer: Control = null
var _paper_seed: float = 0.0
var _lore_font: Font = null
var _rules_font: Font = null
var _action_font: Font = null
var _finish: CardRarityFinish = null
var _name_finish: ShaderMaterial = null
var _sheen_tween: Tween = null

# Laid out, in scaled pixels.
var _plate_size: Vector2 = Vector2.ZERO
var _art_rect: Rect2 = Rect2()
var _name_baseline: float = 0.0
var _rules: TextParagraph = null
var _rules_top: float = 0.0
var _hairline_y: float = -1.0
var _lore: TextParagraph = null
var _lore_top: float = 0.0
var _replaces: TextParagraph = null
var _replaces_top: float = 0.0
var _action_rects: Array[Rect2] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow = Panel.new()
	_shadow.name = "Shadow"
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)
	_paper = Control.new()
	_paper.name = "Paper"
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.material = load(PAPER_MATERIAL_PATH) as Material
	_paper.draw.connect(_draw_paper)
	add_child(_paper)
	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.draw.connect(_draw_face)
	add_child(_face)
	_name_layer = Control.new()
	_name_layer.name = "Name"
	_name_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_layer.draw.connect(_draw_name)
	add_child(_name_layer)
	gui_input.connect(_on_gui_input)

func _ready() -> void:
	_relayout()

# The piece shown, the one worn it would replace (null: none - no line),
# and whether TAKE and LEAVE are offered.
func set_piece(piece: TrinketData, replaced: TrinketData = null, show_actions: bool = false) -> void:
	_piece = piece
	_replaced = replaced if replaced != piece else null
	_show_actions = show_actions
	_focus = Choice.TAKE
	_paper_seed = float(absi(hash(piece.id)) % 1000) / 1000.0 if piece != null else 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP if show_actions else Control.MOUSE_FILTER_IGNORE
	_apply_finish()
	_relayout()

func get_piece() -> TrinketData:
	return _piece

func get_replaced() -> TrinketData:
	return _replaced

func get_plate_size() -> Vector2:
	return _plate_size

# The "Replaces ..." line as shown, "" with nothing worn - for probes.
func replaces_text() -> String:
	if _replaced == null:
		return ""
	return replaces_format % [_replaced.display_name, _replaced.describe()]

# The name's finish material while it wears one, else null - for probes.
func get_name_finish() -> ShaderMaterial:
	return _name_layer.material as ShaderMaterial if _name_layer != null else null

func uses_placeholder() -> bool:
	return _piece != null and _piece.art == null

# One sweep of the finish's sheen across the name - CardView's, played
# once as the plate opens. Nothing for a name with no finish.
func play_name_sheen() -> void:
	if _name_finish == null or _name_layer.material != _name_finish or not is_inside_tree():
		return
	if _sheen_tween != null and _sheen_tween.is_valid():
		_sheen_tween.kill()
	_sheen_tween = create_tween()
	_sheen_tween.tween_method(_set_sheen, 0.0, 1.0, maxf(_finish.sheen_duration_sec, 0.01))
	_sheen_tween.tween_callback(_set_sheen.bind(-1.0))

func _set_sheen(t: float) -> void:
	if _name_finish != null:
		_name_finish.set_shader_parameter("sheen_t", t)

# The choice under focus, and moving it - the keys' way (ArmorExamine).
func get_focus() -> int:
	return _focus

func set_focus(index: int) -> void:
	if not _show_actions or index == _focus or index < 0 or index > Choice.LEAVE:
		return
	_focus = index
	_redraw()

# What a click or a key resolves: TAKE or LEAVE, said once.
func activate(index: int) -> void:
	if not _show_actions or index < 0 or index > Choice.LEAVE:
		return
	chosen.emit(index == Choice.TAKE)

# --- The finish ---

func _apply_finish() -> void:
	if _finish == null and not rarity_finish_path.is_empty():
		_finish = load(rarity_finish_path) as CardRarityFinish
	var rarity: CardData.CardRarity = _piece.rarity if _piece != null else CardData.CardRarity.UNSET
	if _finish == null or not _finish.has_finish(rarity):
		_name_layer.material = null
		_redraw()
		return
	var material: ShaderMaterial = _finish.name_material(rarity, _name_finish, name_finish_shader_path)
	if material == null:
		_name_layer.material = null
		return
	_name_finish = material
	_name_layer.material = _name_finish

# --- Layout ---

func _px(value: float) -> float:
	return value * plate_scale

func _font_px(value: int) -> int:
	return maxi(roundi(float(value) * plate_scale), 1)

func _pitch(font_px: int) -> float:
	return roundf(float(font_px) * line_pitch_em)

func _paragraph(text: String, font: Font, font_px: int, width: float) -> TextParagraph:
	var paragraph := TextParagraph.new()
	paragraph.width = width
	paragraph.add_string(text, font, font_px)
	return paragraph

func _paragraph_height(paragraph: TextParagraph, font_px: int) -> float:
	return _pitch(font_px) * float(paragraph.get_line_count()) if paragraph != null else 0.0

func _relayout() -> void:
	if _face == null:
		return
	if _rules_font == null:
		_rules_font = InkType.text_font()
	if _lore_font == null:
		var slanted := FontVariation.new()
		slanted.base_font = load(LORE_FONT_PATH) as Font
		slanted.variation_transform = Transform2D(Vector2(1.0, lore_slant), Vector2(0.0, 1.0), Vector2.ZERO)
		_lore_font = slanted
	var width: float = roundf(_px(plate_width))
	var pad: float = _px(padding_px)
	var text_width: float = width - pad * 2.0
	var art: float = roundf(_px(art_size_px))
	_art_rect = Rect2(roundf((width - art) / 2.0), roundf(pad), art, art)
	var name_px: int = _font_px(name_size_px)
	var name_font: Font = InkType.numeral_font()
	_name_baseline = roundf(_art_rect.end.y + _px(name_gap_px) + name_font.get_ascent(name_px))
	var y: float = _name_baseline + name_font.get_descent(name_px) + _px(rules_gap_px)
	_rules_top = y
	var rules_px: int = _font_px(rules_size_px)
	_rules = _paragraph(_piece.describe() if _piece != null else "", _rules_font, rules_px, text_width)
	y += _paragraph_height(_rules, rules_px)
	_lore = null
	_hairline_y = -1.0
	if _piece != null and not _piece.flavor_text.is_empty():
		_hairline_y = roundf(y + _px(lore_gap_px))
		_lore_top = _hairline_y + _px(lore_gap_px)
		var lore_px: int = _font_px(lore_size_px)
		_lore = _paragraph(_piece.flavor_text, _lore_font, lore_px, text_width)
		y = _lore_top + _paragraph_height(_lore, lore_px)
	_replaces = null
	if _replaced != null:
		_replaces_top = roundf(y + _px(replaces_gap_px))
		var replaces_px: int = _font_px(replaces_size_px)
		_replaces = _paragraph(replaces_text(), _rules_font, replaces_px, text_width)
		y = _replaces_top + _paragraph_height(_replaces, replaces_px)
	_action_rects.clear()
	if _show_actions:
		if _action_font == null:
			_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, caps_tracking_em)
		var row_top: float = roundf(y + _px(actions_gap_px))
		var row_height: float = _px(action_row_height_px)
		var half: float = (width - pad * 2.0) / 2.0
		_action_rects.append(Rect2(pad, row_top, half, row_height))
		_action_rects.append(Rect2(pad + half, row_top, half, row_height))
		y = row_top + row_height
	_plate_size = Vector2(width, roundf(y + pad))
	size = _plate_size
	custom_minimum_size = _plate_size
	for child: Control in [_shadow, _paper, _face]:
		child.position = Vector2.ZERO
		child.size = _plate_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.91, 0.86, 0.0)
	style.set_corner_radius_all(roundi(_px(corner_radius_px)))
	style.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	style.shadow_size = roundi(_px(shadow_size_px))
	style.shadow_offset = Vector2(0.0, _px(shadow_offset_px))
	_shadow.add_theme_stylebox_override("panel", style)
	# The name's own box: from its left edge, so the finish's u runs over
	# the word itself.
	var name_text: String = _piece.display_name if _piece != null else ""
	var name_width: float = InkType.width(name_font, name_text, name_px)
	_name_layer.position = Vector2(roundf((width - name_width) / 2.0), 0.0)
	_name_layer.size = Vector2(maxf(name_width, 1.0), _plate_size.y)
	if _name_finish != null:
		_name_finish.set_shader_parameter("text_width_px", name_width)
	_redraw()

# The choice's label: centred in its half, at its own label.
func _choice_label(index: int) -> String:
	return take_text if index == Choice.TAKE else leave_text

# --- Draw ---

func _redraw() -> void:
	for layer: Control in [_paper, _face, _name_layer]:
		if layer != null:
			layer.queue_redraw()

func _draw_paper() -> void:
	# The card's own trick: the paper shader reads its seed from red.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_paper_seed, 0.0, 0.0, 1.0)
	style.set_corner_radius_all(roundi(_px(corner_radius_px)))
	_paper.draw_style_box(style, Rect2(Vector2.ZERO, _plate_size))

func _draw_face() -> void:
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(maxi(roundi(plate_scale), 1))
	frame.border_color = Color(ink, frame_alpha)
	frame.set_corner_radius_all(roundi(_px(corner_radius_px)))
	_face.draw_style_box(frame, Rect2(Vector2.ZERO, _plate_size))
	if _piece == null:
		return
	if _piece.art != null:
		_face.draw_texture_rect(_piece.art, _art_rect, false)
	else:
		_face.draw_rect(_art_rect, placeholder_color)
		var initial: String = _piece.display_name.left(1).to_upper()
		var initial_px: int = _font_px(placeholder_initial_size_px)
		var font: Font = InkType.numeral_font()
		var initial_width: float = InkType.width(font, initial, initial_px)
		var baseline: float = _art_rect.get_center().y + (font.get_ascent(initial_px) - font.get_descent(initial_px)) * 0.5
		InkType.draw_run(_face, font, initial, Vector2(roundf(_art_rect.get_center().x - initial_width / 2.0), roundf(baseline)), initial_px, Color(ink, placeholder_initial_alpha))
	_draw_paragraph(_rules, _rules_top, _pitch(_font_px(rules_size_px)), ink)
	if _lore != null:
		var hairline_width: float = roundf(_plate_size.x * 0.22)
		_face.draw_rect(Rect2(roundf((_plate_size.x - hairline_width) / 2.0), _hairline_y, hairline_width, maxf(roundf(plate_scale), 1.0)), Color(ink, hairline_alpha))
		_draw_paragraph(_lore, _lore_top, _pitch(_font_px(lore_size_px)), Color(ink, lore_alpha))
	if _replaces != null:
		_draw_paragraph(_replaces, _replaces_top, _pitch(_font_px(replaces_size_px)), replaces_color)
	_draw_actions()

# The name at the layer's own origin - its finish (or flat ink) is the
# layer's material's to colour.
func _draw_name() -> void:
	if _piece == null:
		return
	var color: Color = ink
	if _name_layer.material == null and _finish != null:
		color = _finish.common_ink
	InkType.draw_run(_name_layer, InkType.numeral_font(), _piece.display_name, Vector2(0.0, _name_baseline), _font_px(name_size_px), color)

# The title menu's treatment: each choice centred in its half in tracked
# caps, the focused one in ink with a short hairline to its left, the
# other in the utility grey.
func _draw_actions() -> void:
	if _action_font == null:
		return
	var action_px: int = _font_px(action_size_px)
	for index in _action_rects.size():
		var row: Rect2 = _action_rects[index]
		var label: String = _choice_label(index)
		var label_width: float = InkType.width(_action_font, label, action_px)
		var left: float = roundf(row.get_center().x - label_width / 2.0)
		var baseline: float = roundf(row.get_center().y + float(action_px) * 0.35)
		var focused: bool = index == _focus
		InkType.draw_run(_face, _action_font, label, Vector2(left, baseline), action_px, ink if focused else unfocused_color)
		if focused:
			var thickness: float = maxf(roundf(_px(hairline_thickness_px)), 1.0)
			var hairline_y: float = roundf(baseline - float(action_px) * 0.35 - thickness * 0.5)
			var length: float = _px(focus_hairline_length_px)
			_face.draw_rect(Rect2(left - _px(focus_hairline_gap_px) - length, hairline_y, length, thickness), ink)

# A paragraph line by line at a fixed pitch, each line centred.
func _draw_paragraph(paragraph: TextParagraph, top: float, pitch: float, color: Color) -> void:
	if paragraph == null:
		return
	var left: float = _px(padding_px)
	var y: float = top
	for line in paragraph.get_line_count():
		var line_left: float = left + roundf((paragraph.width - paragraph.get_line_width(line)) / 2.0)
		var baseline_shift: float = pitch - paragraph.get_line_ascent(line) - paragraph.get_line_descent(line)
		paragraph.draw_line(_face.get_canvas_item(), Vector2(line_left, roundf(y + baseline_shift * 0.5)), line, color)
		y += pitch

# --- Input ---

func _hit(position: Vector2) -> int:
	for index in _action_rects.size():
		if _action_rects[index].has_point(position):
			return index
	return -1

func _on_gui_input(event: InputEvent) -> void:
	if not _show_actions:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _hit(motion.position)
		if under >= 0:
			set_focus(under)
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	var index: int = _hit(button.position)
	if index >= 0:
		activate(index)
