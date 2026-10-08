extends CanvasLayer
class_name KeepsakeOffer

# Keepsake Found: a dropped keepsake shown as the object it is, on its
# own panel, after the normal reward has closed (see RegionField.open_
# keepsake_offer()). A different class of reward from the card choice -
# never in its grid. The field is frozen under it and a scrim dims it;
# this layer runs ALWAYS on layer 100.
#
# The panel is card stock - the card's bone paper (card_paper_material),
# a charcoal frame, a soft shadow - sized to what it holds, and reads top
# to bottom:
#   KEEPSAKE FOUND   small tracked caps, a printed rule under it
#   the keepsake     its KeepsakeTile (art, name, what it does, its lore)
#                    at tile_scale, centred - or, with one already held,
#                    the held tile and the offered one side by side at the
#                    same scale, labelled HELD and OFFERED in tracked caps
#   Dropped by ...   quiet, only when the drop has a named source
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
# Opening is a quiet reveal: the panel fades in and the offered tile
# settles from a hair smaller. Nothing else moves.

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
# The panel's least size; it grows to hold its tiles.
@export var panel_size_px: Vector2 = Vector2(480.0, 560.0):
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

@export_group("Tiles")
# The tiles' scale (KeepsakeTile.tile_scale), the room between the held
# and the offered one, and from the header rule to the tiles' top.
@export var tile_scale: float = 1.3:
	set(value):
		tile_scale = value
		_layout()
@export var tile_gap_px: float = 40.0:
	set(value):
		tile_gap_px = value
		_layout()
@export var tiles_top_gap_px: float = 28.0:
	set(value):
		tiles_top_gap_px = value
		_layout()
# Above each tile when one is held: HELD and OFFERED, tracked caps, this
# far over the tile.
@export var held_label_text: String = "HELD":
	set(value):
		held_label_text = value
		_refresh()
@export var offered_label_text: String = "OFFERED":
	set(value):
		offered_label_text = value
		_refresh()
@export var tile_label_size_px: int = 12:
	set(value):
		tile_label_size_px = value
		_rebuild_fonts()
@export var tile_label_gap_px: float = 12.0:
	set(value):
		tile_label_gap_px = value
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
@export var source_gap_px: float = 30.0:
	set(value):
		source_gap_px = value
		_layout()
# From the tiles (or the source line) down to the actions' rule, from
# that rule to the actions' centre line, and on to the panel's foot.
@export var actions_top_gap_px: float = 28.0:
	set(value):
		actions_top_gap_px = value
		_layout()
@export var actions_rule_gap_px: float = 44.0:
	set(value):
		actions_rule_gap_px = value
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
@export var reveal_tile_sec: float = 0.4
@export_range(0.5, 1.0) var reveal_tile_start_scale: float = 0.94
@export_group("")

var _offered: TrinketData = null
var _held: TrinketData = null
var _source: String = ""

var _scrim: ColorRect = null
var _panel: Control = null
var _shadow: Panel = null
var _paper: Control = null
var _face: Control = null
var _offered_tile: KeepsakeTile = null
var _held_tile: KeepsakeTile = null
var _header_font: Font = null
var _label_font: Font = null
var _action_font: Font = null
var _text_font: Font = null
var _paper_seed: float = 0.0
# The panel's size this layout, and its sections in panel space.
var _panel_size: Vector2 = Vector2.ZERO
var _header_rule_y: float = 0.0
var _labels_baseline: float = 0.0
var _source_baseline: float = 0.0
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

	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_STOP
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.gui_input.connect(_on_face_gui_input)
	_face.draw.connect(_draw_face)
	_panel.add_child(_face)

	# Over the face: the tiles ignore the mouse, so the face still hears it.
	_held_tile = KeepsakeTile.new()
	_held_tile.name = "HeldTile"
	_panel.add_child(_held_tile)
	_offered_tile = KeepsakeTile.new()
	_offered_tile.name = "OfferedTile"
	_panel.add_child(_offered_tile)

	_held_tile.set_keepsake(_held)
	_held_tile.visible = _held != null
	_offered_tile.set_keepsake(_offered)
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
	_label_font = InkType.tracked(InkType.text_bold_font(), tile_label_size_px, caps_tracking_em)
	_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, caps_tracking_em)
	_text_font = InkType.text_font()
	_layout()

func _refresh() -> void:
	for canvas: Control in [_paper, _face]:
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
	for tile: KeepsakeTile in [_held_tile, _offered_tile]:
		if not is_equal_approx(tile.tile_scale, tile_scale):
			tile.tile_scale = tile_scale
	var tile_size: Vector2 = _offered_tile.get_tile_size()
	var row_width: float = tile_size.x * (2.0 if _held != null else 1.0) + (tile_gap_px if _held != null else 0.0)
	_header_rule_y = header_baseline_px + header_rule_gap_px
	var tiles_top: float = _header_rule_y + tiles_top_gap_px
	if _held != null:
		_labels_baseline = tiles_top + float(tile_label_size_px)
		tiles_top = _labels_baseline + tile_label_gap_px
	var below: float = tiles_top + tile_size.y
	if not _source.is_empty():
		_source_baseline = below + source_gap_px
		below = _source_baseline
	_actions_rule_y = roundf(below + actions_top_gap_px)
	_panel_size = Vector2(maxf(panel_size_px.x, row_width + side_padding_px * 2.0), maxf(panel_size_px.y, _actions_rule_y + actions_rule_gap_px + actions_lift_px)).round()
	var viewport_size: Vector2 = _scrim.size
	_panel.size = _panel_size
	_panel.position = ((viewport_size - _panel_size) / 2.0).round()
	for child: Control in [_shadow, _paper, _face]:
		child.position = Vector2.ZERO
		child.size = _panel_size
	var left: float = roundf((_panel_size.x - row_width) / 2.0)
	if _held != null:
		_held_tile.position = Vector2(left, tiles_top)
		_offered_tile.position = Vector2(left + tile_size.x + tile_gap_px, tiles_top)
	else:
		_offered_tile.position = Vector2(left, tiles_top)
	_offered_tile.pivot_offset = tile_size / 2.0
	_refresh_shadow()
	_refresh()

func _actions_centre_y() -> float:
	return _actions_rule_y + actions_rule_gap_px

func _take_rect() -> Rect2:
	var total: float = take_plate_size_px.x + action_gap_px + InkType.width(_action_font, _choice_label(Choice.DECLINE), action_size_px)
	var left: float = roundf((_panel_size.x - total) / 2.0)
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
	_paper.draw_style_box(style, Rect2(Vector2.ZERO, _panel_size))

func _text_centred(canvas: CanvasItem, font: Font, text: String, baseline: float, size_px: int, color: Color) -> void:
	var left: float = roundf((_panel_size.x - InkType.width(font, text, size_px)) / 2.0)
	InkType.draw_run(canvas, font, text, Vector2(left, baseline), size_px, color)

func _rule(y: float) -> void:
	var color: Color = ink
	color.a = rule_alpha
	_face.draw_rect(Rect2(side_padding_px, y, _panel_size.x - side_padding_px * 2.0, hairline_thickness_px), color)

func _draw_face() -> void:
	if _offered == null:
		return
	var face_rect := Rect2(Vector2.ZERO, _panel_size)
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(1)
	frame.border_color = Color(ink, frame_alpha)
	frame.set_corner_radius_all(corner_radius_px)
	_face.draw_style_box(frame, face_rect)

	var label: Color = Color(ink, label_alpha)
	_text_centred(_face, _header_font, header_text, header_baseline_px, header_size_px, label)
	_rule(_header_rule_y)
	# HELD and OFFERED, each centred over its tile.
	if _held != null:
		for pair: Array in [[_held_tile, held_label_text], [_offered_tile, offered_label_text]]:
			var tile: KeepsakeTile = pair[0]
			var text: String = pair[1]
			var width: float = InkType.width(_label_font, text, tile_label_size_px)
			InkType.draw_run(_face, _label_font, text, Vector2(roundf(tile.position.x + (tile.get_tile_size().x - width) / 2.0), _labels_baseline), tile_label_size_px, label)
	if not _source.is_empty():
		_text_centred(_face, _text_font, source_format % _source, _source_baseline, source_size_px, Color(ink, source_alpha))
	_rule(_actions_rule_y)
	_draw_actions()

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
	_offered_tile.scale = Vector2.ONE * reveal_tile_start_scale
	var settle: Tween = create_tween()
	settle.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	settle.tween_property(_offered_tile, "scale", Vector2.ONE, maxf(reveal_tile_sec, 0.01))

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
