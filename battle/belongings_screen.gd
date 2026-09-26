extends CanvasLayer
class_name BelongingsScreen

# Three bundles set down together, as one choice over the field. Opened
# by a BelongingsCache when the Wanderer walks within its reach (see
# RegionField.open_belongings_screen()), over the same scrim-and-freeze
# the reward screen uses: the field goes DISABLED under it, the camera
# holds where it was, and this layer runs ALWAYS on layer 100.
#
# At the top, the cache's one world-voice line in Spectral, bone over
# the scrim with the reward screen's ink outline - no box, no quotes.
# Under it three columns side by side, each with the same small grey
# bundle silhouette (see _build_silhouette()) above what it holds:
#   - the card, as a CardView at item_scale, not interactive - TAKE is
#     the button, the card is to read;
#   - the gold, as the loot window's ring and numeral;
#   - the closed one - the silhouette alone. Nothing about what is inside
#     is drawn or instanced until it is taken: no name, no type colour,
#     no hover preview.
# A column whose slot rolled nothing is not drawn and cannot be focused.
#
# TAKE under each column, and WALK ON under the row, in the title menu's
# focus language: the utility grey at rest, full bone with a short
# hairline to the left when focused. Hovering anywhere in a column
# focuses its TAKE and a click there takes; ui_left/ui_right move across
# the columns (wrapping), ui_down drops to WALK ON, ui_up returns, and
# ui_accept activates. Nothing is focused until the mouse or a key says
# so.
#
# Taking one grants it through RunState, plays the take's sound, and a
# card flies to the Belongings panel (the closed one's card appears only
# for that flight); the screen closes when it lands. WALK ON, ui_cancel,
# a right click anywhere and a fresh press of a move key all decline -
# the move keys only after move_decline_delay_sec, so a key held down
# while walking in doesn't count. Declining is final, as the reward
# screen's skip is: the cache is spent either way (see BelongingsCache).
#
# The scrim, the outlined text, the hairline and the gold ring are
# copies of RewardScreen's and LootScreen's own - the shared focus-
# drawing extraction is deferred (see DESIGN.md).

# The column taken, or -1 for a decline.
signal closed(taken: int)

enum Slot { CARD, GOLD, CLOSED }

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"
const SLOT_COUNT := 3
# The focus index WALK ON takes, after the three columns.
const DISMISS := SLOT_COUNT

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
# The 1 px outline under every bone run (RewardScreen's legibility
# treatment for text sitting over the dimmed world).
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_refresh()
@export var text_outline_px: int = 1:
	set(value):
		text_outline_px = value
		_refresh()

@export_group("World Line")
@export var line_size_px: int = 28:
	set(value):
		line_size_px = value
		_refresh()
# The line's centre, as a fraction of the viewport height.
@export_range(0.0, 1.0) var line_centre_fraction: float = 0.12:
	set(value):
		line_centre_fraction = value
		_refresh()
@export_group("")

@export_group("Columns")
# The card's scale against CardView's 1x card_size - 1.6 is 320 x 448.
@export var item_scale: float = 1.6:
	set(value):
		item_scale = value
		_refresh()
@export var min_column_width_px: float = 200.0:
	set(value):
		min_column_width_px = value
		_refresh()
@export var column_gap_px: float = 64.0:
	set(value):
		column_gap_px = value
		_refresh()
# The block's centre (silhouette to TAKE), as a fraction of the viewport
# height.
@export_range(0.0, 1.0) var columns_centre_fraction: float = 0.54:
	set(value):
		columns_centre_fraction = value
		_refresh()
@export var silhouette_px: float = 72.0:
	set(value):
		silhouette_px = value
		_refresh()
@export var silhouette_gap_px: float = 18.0:
	set(value):
		silhouette_gap_px = value
		_refresh()
@export var take_gap_px: float = 36.0:
	set(value):
		take_gap_px = value
		_refresh()
@export_group("")

@export_group("Silhouette")
# The bundle's model, rendered once into one small viewport shared by all
# three columns (flat, unshaded, this grey).
@export_file("*.glb", "*.tscn") var silhouette_model_path: String = BundleProp.MODEL_SCENE_PATH
@export var silhouette_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		silhouette_color = value
		_render_silhouette()
# Looked down on at the field camera's pitch, turned by the yaw.
@export var silhouette_pitch_degrees: float = 50.0:
	set(value):
		silhouette_pitch_degrees = value
		_render_silhouette()
@export var silhouette_yaw_degrees: float = 30.0:
	set(value):
		silhouette_yaw_degrees = value
		_render_silhouette()
@export var silhouette_resolution: int = 256
@export_group("")

@export_group("Gold")
@export var gold_size_px: int = 48:
	set(value):
		gold_size_px = value
		_refresh()
@export var ring_radius_px: float = 13.0:
	set(value):
		ring_radius_px = value
		_refresh()
@export var ring_width_px: float = 2.0:
	set(value):
		ring_width_px = value
		_refresh()
@export var ring_gap_px: float = 12.0:
	set(value):
		ring_gap_px = value
		_refresh()
@export_group("")

@export_group("Choices")
@export var take_text: String = "TAKE":
	set(value):
		take_text = value
		_refresh()
@export var dismiss_text: String = "WALK ON":
	set(value):
		dismiss_text = value
		_refresh()
@export var label_size_px: int = 22:
	set(value):
		label_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var label_tracking_em: float = 0.16:
	set(value):
		label_tracking_em = value
		_rebuild_fonts()
# From the TAKE row's baseline to WALK ON's.
@export var dismiss_gap_px: float = 64.0:
	set(value):
		dismiss_gap_px = value
		_refresh()
# The title menu's unfocused item: CardView's keyline_utility.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
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
# A move key pressed sooner than this after opening is ignored.
@export var move_decline_delay_sec: float = 0.3
@export_group("")

@export_group("Take")
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
@export_group("")

var _line: String = ""
var _card: CardData = null
var _gold: int = 0
var _closed_card: CardData = null
var _deck_panel: Control = null

var _scrim: ColorRect = null
var _draw_layer: Control = null
var _card_view: CardView = null
var _card_size: Vector2 = Vector2(200.0, 280.0)
var _line_font: Font = null
var _gold_font: Font = null
var _label_font: Font = null

var _viewport: SubViewport = null
var _silhouette_camera: Camera3D = null
var _silhouette_material: StandardMaterial3D = null
var _silhouette_aabb: AABB = AABB()

# 0..2 a column, DISMISS WALK ON, -1 nothing. _mouse_on is what the
# mouse is over, so leaving it clears only a mouse focus.
var _focus: int = -1
var _mouse_on: int = -1
var _done: bool = false
var _opened_msec: int = 0

# Called by RegionField before the screen enters the tree. card and
# closed_card may be null and gold 0 - that column is then left out.
func setup(line: String, card: CardData, gold: int, closed_card: CardData, deck_panel: Control) -> void:
	_line = line
	_card = card
	_gold = gold
	_closed_card = closed_card
	_deck_panel = deck_panel

func _ready() -> void:
	# The field is frozen under this (see RegionField.open_belongings_
	# screen()); this layer has to opt out of the freeze or stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_opened_msec = Time.get_ticks_msec()
	_rebuild_fonts()

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field and order the Wanderer off.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Columns"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_columns)
	_draw_layer.resized.connect(_refresh)
	add_child(_draw_layer)

	_build_silhouette()
	_spawn_card()
	if not _has_slot(Slot.CARD) and not _has_slot(Slot.GOLD) and not _has_slot(Slot.CLOSED):
		push_warning("BelongingsScreen: nothing to offer; closing.")
		_finish(-1)
		return
	_refresh()

func _rebuild_fonts() -> void:
	_line_font = InkType.numeral_font()
	_gold_font = InkType.numeral_font()
	_label_font = InkType.tracked(InkType.text_bold_font(), label_size_px, label_tracking_em)
	_refresh()

# Re-seats the card and redraws - every layout export's setter lands here.
func _refresh() -> void:
	if _draw_layer == null:
		return
	if _card_view != null and is_instance_valid(_card_view) and not _done:
		_seat_card(_card_view, Slot.CARD)
	_draw_layer.queue_redraw()

func _has_slot(slot: int) -> bool:
	match slot:
		Slot.CARD:
			return _card != null
		Slot.GOLD:
			return _gold > 0
		Slot.CLOSED:
			return _closed_card != null
	return false

# --- Silhouette ---

# One SubViewport, its own world, transparent, rendered once: the bundle
# model in a flat unshaded grey under an orthographic camera fitted to
# its bbox. Its one texture is drawn under all three columns.
func _build_silhouette() -> void:
	var scene := load(silhouette_model_path) as PackedScene
	if scene == null:
		push_warning("BelongingsScreen: could not load %s; no silhouettes." % silhouette_model_path)
		return
	_viewport = SubViewport.new()
	_viewport.name = "Silhouette"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(silhouette_resolution, silhouette_resolution)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	var model := scene.instantiate() as Node3D
	_viewport.add_child(model)
	_silhouette_material = StandardMaterial3D.new()
	_silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var has_aabb := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = _silhouette_material
		var mi_aabb: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		_silhouette_aabb = mi_aabb if not has_aabb else _silhouette_aabb.merge(mi_aabb)
		has_aabb = true

	_silhouette_camera = Camera3D.new()
	_silhouette_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_silhouette_camera)
	_render_silhouette()

# Aims the camera and colours the mesh, then asks for one more frame.
func _render_silhouette() -> void:
	if _viewport == null or _silhouette_camera == null:
		return
	_silhouette_material.albedo_color = silhouette_color
	var centre: Vector3 = _silhouette_aabb.get_center()
	var extent: float = maxf(_silhouette_aabb.size.length(), 0.01)
	var pitch: float = deg_to_rad(silhouette_pitch_degrees)
	var yaw: float = deg_to_rad(silhouette_yaw_degrees)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_silhouette_camera.size = extent
	_silhouette_camera.position = centre + direction * (extent * 2.0 + 1.0)
	_silhouette_camera.look_at(centre, Vector3.UP)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _draw_layer != null:
		_draw_layer.queue_redraw()

# --- Card ---

func _spawn_card() -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("BelongingsScreen: could not load %s; the card column is left out." % CARD_VIEW_SCENE_PATH)
		_card = null
		return
	var reference := scene.instantiate() as CardView
	_card_size = reference.card_size
	reference.free()
	if _card != null:
		_card_view = _new_card_view(_card)

# A CardView for reading, not for clicking: no hover, IGNORE (set after
# add_child - CardView._ready() makes itself STOP), scaled about its
# top-left so TakeFeedback.fly_to()'s placement holds.
func _new_card_view(card_data: CardData) -> CardView:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var view := scene.instantiate() as CardView
	view.hover_enabled = false
	_draw_layer.add_child(view)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.pivot_offset = Vector2.ZERO
	view.set_card_data(card_data)
	return view

func _seat_card(view: CardView, slot: int) -> void:
	var item: Rect2 = _item_rect(slot)
	var width: float = _card_size.x * item_scale
	view.scale = Vector2.ONE * item_scale
	view.position = Vector2(roundf(item.position.x + (item.size.x - width) / 2.0), item.position.y)

# --- Layout ---

func _column_width() -> float:
	return maxf(_card_size.x * item_scale, min_column_width_px)

func _item_height() -> float:
	return _card_size.y * item_scale

# Silhouette to TAKE's caps, one column.
func _block_height() -> float:
	return silhouette_px + silhouette_gap_px + _item_height() + take_gap_px + float(label_size_px)

func _block_top() -> float:
	return roundf(_draw_layer.size.y * columns_centre_fraction - _block_height() / 2.0)

func _column_left(slot: int) -> float:
	var span: float = float(SLOT_COUNT) * _column_width() + float(SLOT_COUNT - 1) * column_gap_px
	return roundf((_draw_layer.size.x - span) / 2.0 + float(slot) * (_column_width() + column_gap_px))

func _silhouette_rect(slot: int) -> Rect2:
	var centre_x: float = _column_left(slot) + _column_width() / 2.0
	return Rect2(roundf(centre_x - silhouette_px / 2.0), _block_top(), silhouette_px, silhouette_px)

func _item_rect(slot: int) -> Rect2:
	return Rect2(_column_left(slot), _block_top() + silhouette_px + silhouette_gap_px, _column_width(), _item_height())

func _take_baseline() -> float:
	return _block_top() + _block_height()

func _take_label_left(slot: int) -> float:
	return roundf(_column_left(slot) + (_column_width() - InkType.width(_label_font, take_text, label_size_px)) / 2.0)

# The whole column, silhouette to TAKE - where the mouse focuses and takes.
func _column_rect(slot: int) -> Rect2:
	return Rect2(_column_left(slot), _block_top(), _column_width(), _block_height() + float(label_size_px) * 0.3)

func _dismiss_baseline() -> float:
	return _take_baseline() + dismiss_gap_px

func _dismiss_label_left() -> float:
	return roundf((_draw_layer.size.x - InkType.width(_label_font, dismiss_text, label_size_px)) / 2.0)

# WALK ON's label and the hairline's room to its left.
func _dismiss_rect() -> Rect2:
	var label_left: float = _dismiss_label_left()
	var left: float = label_left - hairline_gap_px - hairline_length_px
	var right: float = label_left + InkType.width(_label_font, dismiss_text, label_size_px)
	return Rect2(left, _dismiss_baseline() - float(label_size_px), right - left, float(label_size_px) * 1.3)

# --- Draw ---

# One bone run over its ink outline, the outline carrying the run's alpha.
func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

func _draw_hairline(label_left: float, baseline: float) -> void:
	var mid: float = baseline - float(label_size_px) * 0.35
	var left: float = label_left - hairline_gap_px - hairline_length_px
	_draw_layer.draw_rect(Rect2(left, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

func _draw_columns() -> void:
	# Once a take is under way the choice has closed: only the flying card
	# (a child of this layer) is left over the scrim.
	if _done:
		return
	var line_width: float = InkType.width(_line_font, _line, line_size_px)
	var line_baseline: float = roundf(_draw_layer.size.y * line_centre_fraction + float(line_size_px) * 0.35)
	_text(_line_font, _line, Vector2(roundf((_draw_layer.size.x - line_width) / 2.0), line_baseline), line_size_px, bone)

	var silhouette: Texture2D = _viewport.get_texture() if _viewport != null else null
	for slot in SLOT_COUNT:
		if not _has_slot(slot):
			continue
		if silhouette != null:
			_draw_layer.draw_texture_rect(silhouette, _silhouette_rect(slot), false)
		if slot == Slot.GOLD:
			_draw_gold(_item_rect(slot))
		var focused: bool = _focus == slot
		var label_left: float = _take_label_left(slot)
		_text(_label_font, take_text, Vector2(label_left, _take_baseline()), label_size_px, bone if focused else unfocused_color)
		if focused:
			_draw_hairline(label_left, _take_baseline())

	var dismiss_focused: bool = _focus == DISMISS
	var dismiss_left: float = _dismiss_label_left()
	_text(_label_font, dismiss_text, Vector2(dismiss_left, _dismiss_baseline()), label_size_px, bone if dismiss_focused else unfocused_color)
	if dismiss_focused:
		_draw_hairline(dismiss_left, _dismiss_baseline())

# The loot window's ring and numeral, centred in the item's rect.
func _draw_gold(item: Rect2) -> void:
	var text: String = str(_gold)
	var width: float = ring_radius_px * 2.0 + ring_gap_px + InkType.width(_gold_font, text, gold_size_px)
	var left: float = roundf(item.position.x + (item.size.x - width) / 2.0)
	var centre_y: float = roundf(item.position.y + item.size.y / 2.0)
	var ring_centre := Vector2(left + ring_radius_px, centre_y)
	if text_outline_px > 0:
		_draw_layer.draw_arc(ring_centre, ring_radius_px, 0.0, TAU, 48, ink, ring_width_px + float(text_outline_px) * 2.0, true)
	_draw_layer.draw_arc(ring_centre, ring_radius_px, 0.0, TAU, 48, bone, ring_width_px, true)
	var baseline: float = centre_y + float(gold_size_px) * 0.3
	_text(_gold_font, text, Vector2(left + ring_radius_px * 2.0 + ring_gap_px, baseline), gold_size_px, bone)

# --- Input ---

func _hit(position: Vector2) -> int:
	for slot in SLOT_COUNT:
		if _has_slot(slot) and _column_rect(slot).has_point(position):
			return slot
	if _dismiss_rect().has_point(position):
		return DISMISS
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
		_activate(DISMISS)
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _hit(button.position)
		if index >= 0:
			_activate(index)
		_draw_layer.accept_event()

# The columns that hold something, left to right.
func _present_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if _has_slot(slot):
			slots.append(slot)
	return slots

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var slots: Array[int] = _present_slots()
	var at: int = slots.find(_focus)
	if event.is_action_pressed("ui_right"):
		_set_focus(slots[posmod(at + 1, slots.size())] if at >= 0 else slots[0])
	elif event.is_action_pressed("ui_left"):
		_set_focus(slots[posmod(at - 1, slots.size())] if at >= 0 else slots[slots.size() - 1])
	elif event.is_action_pressed("ui_down"):
		_set_focus(DISMISS)
	elif event.is_action_pressed("ui_up"):
		if at < 0:
			_set_focus(slots[int(float(slots.size()) / 2.0)])
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_focus)
	elif event.is_action_pressed("ui_cancel"):
		_activate(DISMISS)
	elif _is_move_press(event):
		if float(Time.get_ticks_msec() - _opened_msec) / 1000.0 < move_decline_delay_sec:
			return
		_activate(DISMISS)
	else:
		return
	get_viewport().set_input_as_handled()

# A fresh press (never an echo) of one of the Wanderer's move keys.
func _is_move_press(event: InputEvent) -> bool:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		if event.is_action_pressed(action):
			return true
	return false

# The one gate: the first activation wins.
func _activate(index: int) -> void:
	if _done:
		return
	if index == DISMISS:
		_done = true
		print("BelongingsScreen: walked on.")
		_finish(-1)
		return
	if not _has_slot(index):
		return
	_done = true
	_draw_layer.queue_redraw()
	match index:
		Slot.CARD:
			_take_card(_card, _card_view, index)
		Slot.GOLD:
			RunState.add_gold(_gold)
			TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoldTakeAudio", "BelongingsScreen")
			print("BelongingsScreen: took %d gold (run total %d)." % [_gold, RunState.gold])
			_finish(index)
		Slot.CLOSED:
			# Only now does the closed bundle's card exist on screen - for
			# its flight, from where the item would have been.
			var view: CardView = _new_card_view(_closed_card)
			if view != null:
				_seat_card(view, Slot.CLOSED)
			_take_card(_closed_card, view, index)

func _take_card(card_data: CardData, view: CardView, index: int) -> void:
	if _card_view != null and is_instance_valid(_card_view) and _card_view != view:
		_card_view.queue_free()
	RunState.add_card(card_data)
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "BelongingsScreen")
	print("BelongingsScreen: took '%s' (deck now %d)." % [card_data.card_name, RunState.deck.size()])
	if view == null:
		_finish(index)
		return
	var tween: Tween = TakeFeedback.fly_to(self, view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(func() -> void:
		_finish(index))

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("BelongingsScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

func _finish(taken: int) -> void:
	closed.emit(taken)
	queue_free()
