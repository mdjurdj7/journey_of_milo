extends CanvasLayer
class_name BelongingsScreen

# Three things set down together, as one choice over the field. Opened
# by a BelongingsCache when the Wanderer walks within its reach (see
# RegionField.open_belongings_screen()), over the same scrim-and-freeze
# the reward screen uses: the field goes DISABLED under it, the camera
# holds where it was, and this layer runs ALWAYS on layer 100.
#
# At the top, the cache's one world-voice line in Spectral, bone over
# the scrim with the reward screen's ink outline - no box, no quotes.
# Under it three columns side by side, and each column is its object
# alone - the case, the pack, the bedroll, rendered from their models
# (see _build_render()). Nothing of what is inside is drawn or named:
# no card, no gold, no label, no hover preview. A column whose slot
# rolled nothing is not drawn and cannot be focused.
#
# The focus language is on the object itself, the title menu's two
# states carried over: at rest the object is drawn down in the utility
# grey (rest_modulate); focused it is full bone, with the short hairline
# centred under it. The mouse focuses by hovering a column and takes by
# clicking it; ui_left/ui_right move across the columns (wrapping),
# ui_down drops to WALK ON, ui_up returns, ui_accept takes. Nothing is
# focused until the mouse or a key says so. WALK ON keeps the text form
# of the language (grey at rest, bone and a hairline to its left).
#
# Taking one grants it through RunState and plays the take's sound; with
# reveal_card_on_take a card then flies from the column to the
# Belongings panel - after the choice, as every other take in the game
# does - and the screen closes when it lands. WALK ON, ui_cancel, a right
# click anywhere and a fresh press of a move key all decline - the move
# keys only after move_decline_delay_sec, so a key held down while
# walking in doesn't count. Declining is final, as the reward screen's
# skip is: the cache is spent either way (see BelongingsCache).
#
# The scrim, the outlined text and the hairline are copies of
# RewardScreen's own - the shared focus-drawing extraction is deferred
# (see DESIGN.md).

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
# Each column is a square this many pixels across - its object's render.
@export var column_px: float = 300.0:
	set(value):
		column_px = value
		_refresh()
@export var column_gap_px: float = 40.0:
	set(value):
		column_gap_px = value
		_refresh()
# The columns' centre, as a fraction of the viewport height - above the
# frozen Wanderer, whose head the field camera keeps near y 0.57.
@export_range(0.0, 1.0) var columns_centre_fraction: float = 0.40:
	set(value):
		columns_centre_fraction = value
		_refresh()
# The focused object's hairline: this far under the column's square.
@export var object_hairline_gap_px: float = 10.0:
	set(value):
		object_hairline_gap_px = value
		_refresh()
@export var object_hairline_length_px: float = 56.0:
	set(value):
		object_hairline_length_px = value
		_refresh()
# An object at rest is drawn at this multiple of its bone render, which
# brings its lit faces down to about the title menu's utility grey.
@export var rest_modulate: Color = Color(0.62, 0.64, 0.70, 1.0):
	set(value):
		rest_modulate = value
		_refresh()
@export_group("")

@export_group("Objects")
# The render: one SubViewport, three cells side by side, one render. The
# models share a scale (a case stays bigger than a bedroll), fitted to
# the largest. Tinted bone - the on-dark value, as text on the scrim is.
@export var object_tint: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		object_tint = value
		_render_objects()
# Looked down on at this pitch - lower than the field camera's 50 so the
# sides read - and each object turned by its own yaw, column order.
@export var object_pitch_degrees: float = 35.0:
	set(value):
		object_pitch_degrees = value
		_render_objects()
@export var object_yaws_degrees: PackedFloat32Array = PackedFloat32Array([30.0, -25.0, 20.0]):
	set(value):
		object_yaws_degrees = value
		_render_objects()
# Fraction of each cell the largest object's bounding sphere fills.
@export_range(0.1, 1.0) var object_fill: float = 0.92:
	set(value):
		object_fill = value
		_render_objects()
# The key light, from over the viewer's left shoulder, and the flat fill.
@export var light_energy: float = 0.9:
	set(value):
		light_energy = value
		_render_objects()
@export var light_pitch_degrees: float = -55.0:
	set(value):
		light_pitch_degrees = value
		_render_objects()
@export var light_yaw_degrees: float = -35.0:
	set(value):
		light_yaw_degrees = value
		_render_objects()
@export var ambient_energy: float = 0.45:
	set(value):
		ambient_energy = value
		_render_objects()
@export var render_cell_px: int = 384
@export_group("")

@export_group("Choices")
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
# WALK ON's baseline, as a fraction of the viewport height - under the
# frozen Wanderer's feet (near y 0.72).
@export_range(0.0, 1.0) var dismiss_baseline_fraction: float = 0.84:
	set(value):
		dismiss_baseline_fraction = value
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
# A taken card flies from its column to the Belongings panel - after the
# choice. Off = the sound alone.
@export var reveal_card_on_take: bool = true
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
@export var card_flight_scale: float = 1.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
@export_group("")

var _line: String = ""
var _card: CardData = null
var _gold: int = 0
var _closed_card: CardData = null
var _object_paths: PackedStringArray = PackedStringArray()
var _deck_panel: Control = null

var _scrim: ColorRect = null
var _draw_layer: Control = null
var _line_font: Font = null
var _label_font: Font = null

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _light: DirectionalLight3D = null
var _environment: Environment = null
var _material: StandardMaterial3D = null
# Per column: the model's root (null if it didn't load) and its bbox in
# its own space.
var _models: Array[Node3D] = []
var _model_aabbs: Array[AABB] = []

# 0..2 a column, DISMISS WALK ON, -1 nothing. _mouse_on is what the
# mouse is over, so leaving it clears only a mouse focus.
var _focus: int = -1
var _mouse_on: int = -1
var _done: bool = false
var _opened_msec: int = 0

# Called by RegionField before the screen enters the tree. card and
# closed_card may be null and gold 0 - that column is then left out.
# object_paths are the three models, column order.
func setup(line: String, card: CardData, gold: int, closed_card: CardData, object_paths: PackedStringArray, deck_panel: Control) -> void:
	_line = line
	_card = card
	_gold = gold
	_closed_card = closed_card
	_object_paths = object_paths
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

	_build_render()
	if _present_slots().is_empty():
		push_warning("BelongingsScreen: nothing to offer; closing.")
		_finish(-1)
		return
	_refresh()

func _rebuild_fonts() -> void:
	_line_font = InkType.numeral_font()
	_label_font = InkType.tracked(InkType.text_bold_font(), label_size_px, label_tracking_em)
	_refresh()

func _refresh() -> void:
	if _draw_layer != null:
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

# The columns that hold something, left to right.
func _present_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if _has_slot(slot):
			slots.append(slot)
	return slots

# --- The objects' render ---

# One SubViewport three cells wide, its own world, transparent, rendered
# once (and again when a render export changes): the three models side
# by side along X, one cell apart, each centred on its own bbox and
# turned by its own yaw, under one orthographic camera whose frame is
# exactly the three cells. One shared material, lit by one key light and
# a flat ambient. Cheaper than three viewports - one world, one camera,
# one render pass - and the columns draw sub-rects of its one texture.
func _build_render() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Objects"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i(render_cell_px * SLOT_COUNT, render_cell_px)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	for slot in SLOT_COUNT:
		var model: Node3D = null
		var aabb := AABB()
		var path: String = _object_paths[slot] if slot < _object_paths.size() else ""
		var scene: PackedScene = null
		if not path.is_empty():
			scene = load(path) as PackedScene
		if scene == null:
			push_warning("BelongingsScreen: could not load object %d (%s); its column is left out." % [slot, path])
		else:
			model = scene.instantiate() as Node3D
			_viewport.add_child(model)
			var has_aabb := false
			for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh_instance as MeshInstance3D
				mi.material_override = _material
				var mi_aabb: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
				aabb = mi_aabb if not has_aabb else aabb.merge(mi_aabb)
				has_aabb = true
		_models.append(model)
		_model_aabbs.append(aabb)
		if model == null:
			_drop_slot(slot)

	_light = DirectionalLight3D.new()
	_viewport.add_child(_light)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_viewport.add_child(world_environment)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_camera)
	_render_objects()

# A column with no model is a column with nothing to take.
func _drop_slot(slot: int) -> void:
	match slot:
		Slot.CARD:
			_card = null
		Slot.GOLD:
			_gold = 0
		Slot.CLOSED:
			_closed_card = null

func _render_objects() -> void:
	if _viewport == null or _camera == null:
		return
	_material.albedo_color = object_tint
	# One cell is one bounding-sphere diameter of the largest object, over
	# object_fill.
	var diameter: float = 0.01
	for aabb in _model_aabbs:
		diameter = maxf(diameter, aabb.size.length())
	var cell: float = diameter / maxf(object_fill, 0.1)
	for slot in _models.size():
		var model: Node3D = _models[slot]
		if model == null:
			continue
		var yaw: float = deg_to_rad(object_yaws_degrees[slot]) if slot < object_yaws_degrees.size() else 0.0
		var basis := Basis(Vector3.UP, yaw)
		model.transform = Transform3D(basis, Vector3((float(slot) - 1.0) * cell, 0.0, 0.0) - basis * _model_aabbs[slot].get_center())
	var pitch: float = deg_to_rad(object_pitch_degrees)
	_camera.size = cell
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * (cell * 4.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_light.light_energy = light_energy
	_light.rotation = Vector3(deg_to_rad(light_pitch_degrees), deg_to_rad(light_yaw_degrees), 0.0)
	_environment.ambient_light_energy = ambient_energy
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_refresh()

# --- Layout ---

func _column_rect(slot: int) -> Rect2:
	var span: float = float(SLOT_COUNT) * column_px + float(SLOT_COUNT - 1) * column_gap_px
	var left: float = roundf((_draw_layer.size.x - span) / 2.0 + float(slot) * (column_px + column_gap_px))
	var top: float = roundf(_draw_layer.size.y * columns_centre_fraction - column_px / 2.0)
	return Rect2(left, top, column_px, column_px)

func _dismiss_baseline() -> float:
	return roundf(_draw_layer.size.y * dismiss_baseline_fraction)

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

func _draw_columns() -> void:
	# Once a take is under way the choice has closed: only a flying card
	# (a child of this layer) is left over the scrim.
	if _done:
		return
	var line_width: float = InkType.width(_line_font, _line, line_size_px)
	var line_baseline: float = roundf(_draw_layer.size.y * line_centre_fraction + float(line_size_px) * 0.35)
	_text(_line_font, _line, Vector2(roundf((_draw_layer.size.x - line_width) / 2.0), line_baseline), line_size_px, bone)

	var texture: Texture2D = _viewport.get_texture() if _viewport != null else null
	for slot in _present_slots():
		var rect: Rect2 = _column_rect(slot)
		var focused: bool = _focus == slot
		if texture != null:
			var source := Rect2(float(slot * render_cell_px), 0.0, float(render_cell_px), float(render_cell_px))
			_draw_layer.draw_texture_rect_region(texture, rect, source, Color.WHITE if focused else rest_modulate)
		if focused:
			var y: float = rect.end.y + object_hairline_gap_px
			_draw_layer.draw_rect(Rect2(roundf(rect.get_center().x - object_hairline_length_px / 2.0), y, object_hairline_length_px, hairline_thickness_px), bone)

	var dismiss_focused: bool = _focus == DISMISS
	var dismiss_left: float = _dismiss_label_left()
	_text(_label_font, dismiss_text, Vector2(dismiss_left, _dismiss_baseline()), label_size_px, bone if dismiss_focused else unfocused_color)
	if dismiss_focused:
		var mid: float = _dismiss_baseline() - float(label_size_px) * 0.35
		var left: float = dismiss_left - hairline_gap_px - hairline_length_px
		_draw_layer.draw_rect(Rect2(left, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

# --- Input ---

func _hit(position: Vector2) -> int:
	for slot in _present_slots():
		if _column_rect(slot).has_point(position):
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
		Slot.GOLD:
			RunState.add_gold(_gold)
			TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoldTakeAudio", "BelongingsScreen")
			print("BelongingsScreen: took %d gold (run total %d)." % [_gold, RunState.gold])
			_finish(index)
		Slot.CARD:
			_take_card(_card, index)
		Slot.CLOSED:
			_take_card(_closed_card, index)

func _take_card(card_data: CardData, index: int) -> void:
	RunState.add_card(card_data)
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "BelongingsScreen")
	print("BelongingsScreen: took '%s' (deck now %d)." % [card_data.card_name, RunState.deck.size()])
	var view: CardView = _new_card_view(card_data, index) if reveal_card_on_take else null
	if view == null:
		_finish(index)
		return
	var tween: Tween = TakeFeedback.fly_to(self, view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(func() -> void:
		_finish(index))

# The taken card, for its flight only: centred on the column it came
# from, not interactive, scaled about its top-left so TakeFeedback.
# fly_to()'s placement holds.
func _new_card_view(card_data: CardData, slot: int) -> CardView:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		return null
	var view := scene.instantiate() as CardView
	view.hover_enabled = false
	_draw_layer.add_child(view)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.pivot_offset = Vector2.ZERO
	view.set_card_data(card_data)
	view.scale = Vector2.ONE * card_flight_scale
	view.position = (_column_rect(slot).get_center() - view.card_size * card_flight_scale / 2.0).round()
	return view

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("BelongingsScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

func _finish(taken: int) -> void:
	closed.emit(taken)
	queue_free()
