extends CanvasLayer
class_name BelongingsScreen

# Three things set down together, as one choice over the field. Opened
# by a BelongingsCache when the Wanderer walks within its reach (see
# RegionField.open_belongings_screen()), over the same scrim-and-freeze
# the reward screen uses: the field goes DISABLED under it, the camera
# holds where it was, and this layer runs ALWAYS on layer 100.
#
# At the top, the cache's one world-voice line in Spectral, bone over
# the scrim with the reward screen's ink outline - no box, no quotes -
# and under it the rule, TAKE ONE, in the system voice's tracked caps.
# Under that three columns side by side, each its object alone - the
# case, the pack, the bedroll, rendered from their models (see _build_
# render()). The kind of thing each holds is fixed (Slot) - the case
# coin, the pack a card, the bedroll a keepsake, any one of them perhaps
# Glassbone too - but which thing is a mystery until it's taken: nothing
# of what is inside is drawn or named before. A column whose slot rolled
# nothing is not drawn and cannot be focused.
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
# Taking one is the reveal. The taken column stays full bone with its
# hairline, the other two dim (dimmed_modulate), TAKE ONE and WALK ON go,
# and what was inside shows on the screen itself, in full bone - the
# field HUD under the scrim only echoes it:
#   the case     "+45 gold"
#   the pack     its card, lifted at the deck view's inspect size (card_
#                inspect_scale) over the screen
#   the bedroll  its keepsake's KeepsakeTile, at keepsake_tile_scale over
#                the bedroll's column
# and "+ Glassbone ×1" under whichever carried it. Everything is granted
# through RunState as it's revealed, and the take's sound plays; the
# reveal holds for result_hold_time, then a card flies to the Belongings
# panel (reveal_card_on_take) and the screen closes as it lands, anything
# else closes at once. The bedroll's keepsake counts as offered (RunState.
# note_keepsake_offered()) only here, once it has been seen.
#
# The bedroll taken with the keepsake slot already full: the reveal shows
# the held keepsake's tile and the new one's side by side at the same
# scale, labelled HELD and OFFERED, centred on the screen, and asks under
# them REPLACE <held> or KEEP <held>, in
# the WALK ON form of the focus language - and holds, with no timeout,
# until one is chosen. REPLACE puts the new one in the slot; KEEP leaves
# it behind. Either closes the screen, and the take is spent either way
# (Glassbone the bedroll carried is granted with the reveal, before the
# question). The mouse focuses by hovering and chooses by clicking;
# ui_up/ui_down/ui_left/ui_right move between the two, ui_accept chooses,
# ui_cancel and a right click are KEEP.
#
# Before a take, WALK ON, ui_cancel, a right click anywhere and a fresh
# press of a move key all decline and grant nothing - the move keys only
# after move_decline_delay_sec, so a key held down while walking in
# doesn't count. Declining is final, as the reward screen's skip is: the
# cache is spent either way (see BelongingsCache).
#
# The scrim, the outlined text and the hairline are copies of
# RewardScreen's own - the shared focus-drawing extraction is deferred
# (see DESIGN.md).

# The column taken, or -1 for a decline.
signal closed(taken: int)

# Column order - the case, the pack, the bedroll (BelongingsCache).
enum Slot { GOLD, CARD, KEEPSAKE }
# The full-slot question's two answers, top to bottom.
enum Choice { REPLACE, KEEP }

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
@export_range(0.0, 1.0) var line_centre_fraction: float = 0.08:
	set(value):
		line_centre_fraction = value
		_refresh()
# The rule, in the choices' tracked caps (label_size_px, label_tracking_
# em), its baseline this far under the world line's.
@export var take_one_text: String = "TAKE ONE":
	set(value):
		take_one_text = value
		_refresh()
@export var take_one_gap_px: float = 40.0:
	set(value):
		take_one_gap_px = value
		_refresh()
@export_group("")

@export_group("Columns")
# Each column is a square this many pixels across - its object's render.
@export var column_px: float = 300.0:
	set(value):
		column_px = value
		_render_objects()
		_refresh()
@export var column_gap_px: float = 40.0:
	set(value):
		column_gap_px = value
		_refresh()
# The columns' centre, as a fraction of the viewport height - high
# enough that the lines under them clear the frozen Wanderer, whose head
# the field camera keeps near y 0.57.
@export_range(0.0, 1.0) var columns_centre_fraction: float = 0.28:
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

@export_group("Reveal")
# What the taken column held, under it in Alegreya Sans: the first
# baseline this far under the column's square, each line after one pitch
# further.
@export var contents_size_px: int = 21:
	set(value):
		contents_size_px = value
		_rebuild_fonts()
@export var contents_gap_px: float = 44.0:
	set(value):
		contents_gap_px = value
		_refresh()
@export var contents_pitch_px: float = 27.0:
	set(value):
		contents_pitch_px = value
		_refresh()
@export var gold_format: String = "+%d gold":
	set(value):
		gold_format = value
		_refresh()
@export var glassbone_format: String = "+ Glassbone ×%d":
	set(value):
		glassbone_format = value
		_refresh()
@export_group("")

@export_group("Full Slot")
# The bedroll's question when the slot is full: each choice this word in
# the choices' tracked caps at choice_word_size_px, then the held
# keepsake's name - REPLACE first, KEEP under it, the first baseline
# choice_gap_px below where a next line of the reveal would sit, the
# second one choice_pitch_px further. Focused, a choice is bone with the hairline to its
# left; at rest, the utility grey.
@export var replace_text: String = "REPLACE":
	set(value):
		replace_text = value
		_refresh()
@export var keep_text: String = "KEEP":
	set(value):
		keep_text = value
		_refresh()
@export var choice_word_size_px: int = 17:
	set(value):
		choice_word_size_px = value
		_rebuild_fonts()
@export var choice_gap_px: float = 16.0:
	set(value):
		choice_gap_px = value
		_refresh()
@export var choice_pitch_px: float = 34.0:
	set(value):
		choice_pitch_px = value
		_refresh()
@export_group("")

@export_group("Keepsake Tile")
# The bedroll's keepsake, revealed: its KeepsakeTile at this scale, its
# centre at keepsake_tile_centre_fraction of the viewport height - over
# the bedroll's column alone, centred on the screen beside the held one.
@export var keepsake_tile_scale: float = 1.3:
	set(value):
		keepsake_tile_scale = value
		_refresh()
@export_range(0.0, 1.0) var keepsake_tile_centre_fraction: float = 0.47:
	set(value):
		keepsake_tile_centre_fraction = value
		_refresh()
@export var keepsake_tile_gap_px: float = 40.0:
	set(value):
		keepsake_tile_gap_px = value
		_refresh()
# Over each tile when one is held, this far above it.
@export var held_label_text: String = "HELD":
	set(value):
		held_label_text = value
		_refresh()
@export var offered_label_text: String = "OFFERED":
	set(value):
		offered_label_text = value
		_refresh()
@export var keepsake_label_gap_px: float = 12.0:
	set(value):
		keepsake_label_gap_px = value
		_refresh()
@export_group("")

@export_group("Card Inspect")
# The pack's card, revealed: lifted at the deck view's inspect size
# (DeckView.inspect_scale), centred on the pack's column, its centre at
# this fraction of the viewport height. A Glassbone line hangs under it.
@export var card_inspect_scale: float = 2.2:
	set(value):
		card_inspect_scale = value
		_refresh()
@export_range(0.0, 1.0) var card_inspect_centre_fraction: float = 0.47:
	set(value):
		card_inspect_centre_fraction = value
		_refresh()
@export_group("")

@export_group("Result")
# Seconds the reveal holds before the screen closes (a card flies
# first). Read on the take. The full-slot question has no timeout.
@export var result_hold_time: float = 1.2
# The two columns not taken, through the reveal: their objects at this
# multiple of the bone render.
@export var dimmed_modulate: Color = Color(0.62, 0.64, 0.70, 0.35):
	set(value):
		dimmed_modulate = value
		_refresh()
@export_group("")

@export_group("Objects")
# The render: one SubViewport, three cells side by side, one render. The
# models keep their relative sizes at the cache's object_scales (the
# same as on the sand), the largest fitted to its cell. Tinted bone - the on-dark value, as text on the scrim is.
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
# Each cell renders at its column's on-screen size - column_px times the
# window's stretch scale - so the objects draw 1:1 at any window size,
# re-rendered when the window changes. Capped here (768 covers a 5K
# fullscreen).
@export var render_cell_max_px: int = 768:
	set(value):
		render_cell_max_px = value
		_render_objects()
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
# Glassbone has no take sound of its own: the gold take, under it
# (RewardScreen.glassbone_volume_db).
@export var glassbone_volume_db: float = -24.0
@export var keepsake_volume_db: float = -18.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
@export_group("")

var _line: String = ""
var _gold: int = 0
var _card: CardData = null
var _keepsake: TrinketData = null
var _glassbone_slot: int = -1
var _glassbone_amount: int = 0
var _object_paths: PackedStringArray = PackedStringArray()
var _object_scales: PackedFloat32Array = PackedFloat32Array()
var _deck_panel: Control = null
# The keepsake held as the screen opened - what the bedroll's keepsake
# would replace (the full-slot question).
var _held: TrinketData = null

var _scrim: ColorRect = null
var _draw_layer: Control = null
var _line_font: Font = null
var _label_font: Font = null
var _contents_font: Font = null
var _choice_font: Font = null
# The pack's card while it's lifted (_sync_card_lift()), else null.
var _lifted: CardView = null
# The bedroll's keepsake and the held one while they're shown
# (_sync_keepsake_tiles()), else null.
var _offered_tile: KeepsakeTile = null
var _held_tile: KeepsakeTile = null

var _viewport: SubViewport = null
var _cell_px: int = 1
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
# The column taken, through its reveal; -1 before. _flying once a
# taken card has left for the Belongings panel - nothing else is drawn.
var _taken: int = -1
var _flying: bool = false
# The full-slot question (Choice), open after the bedroll's reveal: its
# focus and what the mouse is over, as _focus and _mouse_on are for the
# columns.
var _asking: bool = false
var _choice_focus: int = -1
var _choice_mouse_on: int = -1

# Called by RegionField before the screen enters the tree. gold may be 0
# and card or keepsake null - that column is then left out. glassbone_slot
# is the column that also holds glassbone_amount Glassbone, -1 for none.
# object_paths are the three models and object_scales their scales, column
# order - the same scales the cache puts on the sand.
func setup(line: String, gold: int, card: CardData, keepsake: TrinketData, glassbone_slot: int, glassbone_amount: int, object_paths: PackedStringArray, object_scales: PackedFloat32Array, deck_panel: Control) -> void:
	_line = line
	_gold = gold
	_card = card
	_keepsake = keepsake
	_glassbone_slot = glassbone_slot
	_glassbone_amount = glassbone_amount
	_object_paths = object_paths
	_object_scales = object_scales
	_deck_panel = deck_panel

func _ready() -> void:
	# The field is frozen under this (see RegionField.open_belongings_
	# screen()); this layer has to opt out of the freeze or stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_opened_msec = Time.get_ticks_msec()
	_held = RunState.keepsake
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
	_contents_font = InkType.text_font()
	_choice_font = InkType.tracked(InkType.text_bold_font(), choice_word_size_px, label_tracking_em)
	_refresh()

func _refresh() -> void:
	if _draw_layer != null:
		_draw_layer.queue_redraw()
	_place_lift()
	_place_keepsake_tiles()

func _has_slot(slot: int) -> bool:
	match slot:
		Slot.GOLD:
			return _gold > 0
		Slot.CARD:
			return _card != null
		Slot.KEEPSAKE:
			return _keepsake != null
	return false

# The Glassbone a column holds alongside its own thing, 0 for none.
func _glassbone_in(slot: int) -> int:
	return maxi(_glassbone_amount, 0) if slot == _glassbone_slot and _has_slot(slot) else 0

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
	_cell_px = _render_cell_size()
	_viewport.size = Vector2i(_cell_px * SLOT_COUNT, _cell_px)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	get_viewport().size_changed.connect(_render_objects)

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
		Slot.GOLD:
			_gold = 0
		Slot.CARD:
			_card = null
		Slot.KEEPSAKE:
			_keepsake = null

func _render_objects() -> void:
	if _viewport == null or _camera == null:
		return
	_material.albedo_color = object_tint
	# One cell is one bounding-sphere diameter of the largest object, over
	# object_fill.
	var diameter: float = 0.01
	for slot in _model_aabbs.size():
		diameter = maxf(diameter, _model_aabbs[slot].size.length() * _scale_of(slot))
	var cell: float = diameter / maxf(object_fill, 0.1)
	for slot in _models.size():
		var model: Node3D = _models[slot]
		if model == null:
			continue
		var yaw: float = deg_to_rad(object_yaws_degrees[slot]) if slot < object_yaws_degrees.size() else 0.0
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * _scale_of(slot))
		model.transform = Transform3D(basis, Vector3((float(slot) - 1.0) * cell, 0.0, 0.0) - basis * _model_aabbs[slot].get_center())
	var pitch: float = deg_to_rad(object_pitch_degrees)
	_camera.size = cell
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * (cell * 4.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_light.light_energy = light_energy
	_light.rotation = Vector3(deg_to_rad(light_pitch_degrees), deg_to_rad(light_yaw_degrees), 0.0)
	_environment.ambient_light_energy = ambient_energy
	_cell_px = _render_cell_size()
	_viewport.size = Vector2i(_cell_px * SLOT_COUNT, _cell_px)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_refresh()

func _scale_of(slot: int) -> float:
	return _object_scales[slot] if slot < _object_scales.size() else 1.0

# One column's on-screen size in window pixels (see render_cell_max_px).
func _render_cell_size() -> int:
	var stretch: float = get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	return clampi(ceili(column_px * stretch), 1, maxi(render_cell_max_px, 1))

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

# Centred on x, baseline y.
func _text_centred(font: Font, text: String, x: float, y: float, size_px: int, color: Color) -> void:
	_text(font, text, Vector2(roundf(x - InkType.width(font, text, size_px) / 2.0), y), size_px, color)

func _draw_columns() -> void:
	# Once a taken card is flying the choice has closed: only the card (a
	# child of this layer) is left over the scrim.
	if _flying:
		return
	var line_width: float = InkType.width(_line_font, _line, line_size_px)
	var line_baseline: float = roundf(_draw_layer.size.y * line_centre_fraction + float(line_size_px) * 0.35)
	_text(_line_font, _line, Vector2(roundf((_draw_layer.size.x - line_width) / 2.0), line_baseline), line_size_px, bone)
	if _taken < 0:
		_text_centred(_label_font, take_one_text, _draw_layer.size.x / 2.0, roundf(line_baseline + take_one_gap_px), label_size_px, bone)

	var texture: Texture2D = _viewport.get_texture() if _viewport != null else null
	for slot in _present_slots():
		var rect: Rect2 = _column_rect(slot)
		var lit: bool = _is_lit(slot)
		var tint: Color = rest_modulate
		if lit:
			tint = Color.WHITE
		elif _taken >= 0:
			tint = dimmed_modulate
		if texture != null:
			var source := Rect2(float(slot * _cell_px), 0.0, float(_cell_px), float(_cell_px))
			_draw_layer.draw_texture_rect_region(texture, rect, source, tint)
		if lit:
			var y: float = rect.end.y + object_hairline_gap_px
			_draw_layer.draw_rect(Rect2(roundf(rect.get_center().x - object_hairline_length_px / 2.0), y, object_hairline_length_px, hairline_thickness_px), bone)

	if _taken >= 0:
		_reveal(_taken, true)
		if _asking:
			_draw_keepsake_labels()
			for choice in [Choice.REPLACE, Choice.KEEP]:
				_draw_choice(choice)
		return
	var dismiss_focused: bool = _focus == DISMISS
	var dismiss_left: float = _dismiss_label_left()
	_text(_label_font, dismiss_text, Vector2(dismiss_left, _dismiss_baseline()), label_size_px, bone if dismiss_focused else unfocused_color)
	if dismiss_focused:
		_hairline_left_of(dismiss_left, _dismiss_baseline(), label_size_px)

# The focus language's text form: the short hairline to the left of a
# label at `left`, at its mid-height.
func _hairline_left_of(left: float, baseline: float, size_px: int) -> void:
	var mid: float = baseline - float(size_px) * 0.35
	_draw_layer.draw_rect(Rect2(left - hairline_gap_px - hairline_length_px, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

# Full bone: the focused column before the take, the taken one after.
func _is_lit(slot: int) -> bool:
	return slot == _taken if _taken >= 0 else slot == _focus

# What the taken column held, line by line in full bone under it - or,
# for the pack, under its lifted card, the card speaking for itself.
# Drawn when `draw`; either way, returns where a next line's baseline
# would sit (the full-slot question hangs from it).
func _reveal(slot: int, draw: bool) -> float:
	var rect: Rect2 = _column_rect(slot)
	var x: float = rect.get_center().x
	var y: float = rect.end.y + contents_gap_px
	match slot:
		Slot.GOLD:
			if draw:
				_text_centred(_contents_font, gold_format % _gold, x, y, contents_size_px, bone)
			y += contents_pitch_px
		Slot.CARD:
			var lift: Rect2 = _lift_rect()
			if lift.has_area():
				y = lift.end.y + contents_gap_px
		Slot.KEEPSAKE:
			# The tile speaks for it; lines hang under the tiles.
			var tiles: Rect2 = _keepsake_tiles_rect()
			if tiles.has_area():
				x = tiles.get_center().x
				y = tiles.end.y + contents_gap_px
	var glassbone: int = _glassbone_in(slot)
	if glassbone > 0:
		if draw:
			_text_centred(_contents_font, glassbone_format % glassbone, x, y, contents_size_px, bone)
		y += contents_pitch_px
	return y

# --- The full-slot question ---

# Each choice is its word in the choices' caps, a space and the held
# keepsake's name, centred under the bedroll.
func _choice_baseline(choice: int) -> float:
	return roundf(_reveal(Slot.KEEPSAKE, false) + choice_gap_px + float(choice) * choice_pitch_px)

func _choice_word(choice: int) -> String:
	return replace_text if choice == Choice.REPLACE else keep_text

func _choice_width(choice: int) -> float:
	var gap: float = InkType.width(_contents_font, " ", contents_size_px)
	return InkType.width(_choice_font, _choice_word(choice), choice_word_size_px) + gap + InkType.width(_contents_font, _held.display_name, contents_size_px)

func _choice_left(choice: int) -> float:
	var tiles: Rect2 = _keepsake_tiles_rect()
	var centre: float = tiles.get_center().x if tiles.has_area() else _column_rect(Slot.KEEPSAKE).get_center().x
	return roundf(centre - _choice_width(choice) / 2.0)

# The choice and the hairline's room to its left.
func _choice_rect(choice: int) -> Rect2:
	var left: float = _choice_left(choice) - hairline_gap_px - hairline_length_px
	var right: float = _choice_left(choice) + _choice_width(choice)
	return Rect2(left, _choice_baseline(choice) - float(contents_size_px), right - left, float(contents_size_px) * 1.3)

func _draw_choice(choice: int) -> void:
	var focused: bool = _choice_focus == choice
	var color: Color = bone if focused else unfocused_color
	var left: float = _choice_left(choice)
	var baseline: float = _choice_baseline(choice)
	var word: String = _choice_word(choice)
	var word_width: float = InkType.width(_choice_font, word, choice_word_size_px)
	_text(_choice_font, word, Vector2(left, baseline), choice_word_size_px, color)
	_text(_contents_font, _held.display_name, Vector2(left + word_width + InkType.width(_contents_font, " ", contents_size_px), baseline), contents_size_px, color)
	if focused:
		_hairline_left_of(left, baseline, choice_word_size_px)

# --- The bedroll's keepsake ---

# The tiles' row on screen: the offered tile alone over the bedroll's
# column (held inside the screen), or the held and the offered side by
# side, centred on the screen. Empty while none is shown.
func _keepsake_tiles_rect() -> Rect2:
	if _offered_tile == null or _draw_layer == null:
		return Rect2()
	var tile: Vector2 = _offered_tile.get_tile_size()
	var both: bool = _held_tile != null
	var width: float = tile.x * (2.0 if both else 1.0) + (keepsake_tile_gap_px if both else 0.0)
	var view: Vector2 = _draw_layer.size
	var centre_x: float = view.x / 2.0
	if not both:
		centre_x = clampf(_column_rect(Slot.KEEPSAKE).get_center().x, width / 2.0 + 24.0, view.x - width / 2.0 - 24.0)
	var top: float = view.y * keepsake_tile_centre_fraction - tile.y / 2.0
	return Rect2(Vector2(centre_x - width / 2.0, top).round(), Vector2(width, tile.y))

# Up through the bedroll's reveal: its tile, and the held one beside it
# while the full slot is asked about.
func _sync_keepsake_tiles() -> void:
	var wanted: bool = _keepsake != null and not _flying and _taken == Slot.KEEPSAKE
	var wanted_held: bool = wanted and _asking and _held != null
	if wanted and _offered_tile == null:
		_offered_tile = _new_tile(_keepsake)
	elif not wanted and _offered_tile != null:
		_offered_tile.queue_free()
		_offered_tile = null
	if wanted_held and _held_tile == null:
		_held_tile = _new_tile(_held)
	elif not wanted_held and _held_tile != null:
		_held_tile.queue_free()
		_held_tile = null
	_place_keepsake_tiles()

func _new_tile(keepsake: TrinketData) -> KeepsakeTile:
	var tile := KeepsakeTile.new()
	tile.tile_scale = keepsake_tile_scale
	_draw_layer.add_child(tile)
	tile.set_keepsake(keepsake)
	return tile

func _place_keepsake_tiles() -> void:
	var row: Rect2 = _keepsake_tiles_rect()
	if not row.has_area():
		return
	for tile: KeepsakeTile in [_held_tile, _offered_tile]:
		if tile != null and not is_equal_approx(tile.tile_scale, keepsake_tile_scale):
			tile.tile_scale = keepsake_tile_scale
	if _held_tile != null:
		_held_tile.position = row.position
		_offered_tile.position = row.position + Vector2(_offered_tile.get_tile_size().x + keepsake_tile_gap_px, 0.0)
	else:
		_offered_tile.position = row.position

# HELD and OFFERED, each centred over its tile, in the labels' caps.
func _draw_keepsake_labels() -> void:
	if _held_tile == null or _offered_tile == null:
		return
	for pair: Array in [[_held_tile, held_label_text], [_offered_tile, offered_label_text]]:
		var tile: KeepsakeTile = pair[0]
		var centre: float = tile.position.x + tile.get_tile_size().x / 2.0
		_text_centred(_label_font, pair[1], centre, roundf(tile.position.y - keepsake_label_gap_px), label_size_px, bone)

# For probes: the tiles up now (held first when both), empty with none.
func get_keepsake_tiles() -> Array[KeepsakeTile]:
	var tiles: Array[KeepsakeTile] = []
	for tile: KeepsakeTile in [_held_tile, _offered_tile]:
		if tile != null:
			tiles.append(tile)
	return tiles

# --- The pack's card ---

# Where the lifted card sits: centred on the pack's column, at card_
# inspect_scale. Empty while nothing is lifted.
func _lift_rect() -> Rect2:
	if _lifted == null or _draw_layer == null:
		return Rect2()
	var size: Vector2 = _lifted.card_size * card_inspect_scale
	var centre := Vector2(_column_rect(Slot.CARD).get_center().x, _draw_layer.size.y * card_inspect_centre_fraction)
	return Rect2((centre - size / 2.0).round(), size)

# The card is up through the pack's own reveal, until it flies.
func _sync_card_lift() -> void:
	var wanted: bool = _card != null and not _flying and _taken == Slot.CARD
	if wanted and _lifted == null:
		_lifted = _new_card_view(_card)
		# Up for inspection: its keywords define themselves on hover.
		if _lifted != null:
			_lifted.set_keyword_inspect(true)
		_place_lift()
		# Revealed, the pack's card has arrived: its name sheens once.
		if _lifted != null:
			_lifted.play_name_sheen()
	elif not wanted and _lifted != null:
		_lifted.queue_free()
		_lifted = null

func _place_lift() -> void:
	if _lifted == null or _flying:
		return
	_lifted.scale = Vector2.ONE * card_inspect_scale
	_lifted.position = _lift_rect().position

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

func _choice_hit(position: Vector2) -> int:
	for choice in [Choice.REPLACE, Choice.KEEP]:
		if _choice_rect(choice).has_point(position):
			return choice
	return -1

func _set_choice_focus(choice: int) -> void:
	if choice == _choice_focus:
		return
	_choice_focus = choice
	_draw_layer.queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	# The lifted card takes no mouse of its own (_new_card_view()), so
	# its keyword hover reads the motion here.
	if event is InputEventMouseMotion and _lifted != null:
		_lifted.update_keyword_hover()
	if _asking:
		_on_choice_gui_input(event)
		return
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

# The full-slot question's mouse: hover focuses, a click answers, a right
# click anywhere is KEEP.
func _on_choice_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _choice_hit(motion.position)
		if under != _choice_mouse_on:
			if under >= 0:
				_set_choice_focus(under)
			elif _choice_focus == _choice_mouse_on:
				_set_choice_focus(-1)
			_choice_mouse_on = under
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_answer(Choice.KEEP)
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var choice: int = _choice_hit(button.position)
		if choice >= 0:
			_answer(choice)
		_draw_layer.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _asking:
		_on_choice_key(event)
		return
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

# The full-slot question's keys: any arrow moves between the two (from
# nothing, to REPLACE), ui_accept answers, ui_cancel is KEEP.
func _on_choice_key(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_set_choice_focus(Choice.KEEP if _choice_focus == Choice.REPLACE else Choice.REPLACE)
	elif event.is_action_pressed("ui_accept"):
		if _choice_focus >= 0:
			_answer(_choice_focus)
	elif event.is_action_pressed("ui_cancel"):
		_answer(Choice.KEEP)
	else:
		return
	get_viewport().set_input_as_handled()

# A fresh press (never an echo) of one of the Wanderer's move keys.
func _is_move_press(event: InputEvent) -> bool:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		if event.is_action_pressed(action):
			return true
	return false

# The one gate: the first activation wins. A take reveals that column's
# contents and grants them - with its Glassbone - and nothing else; the
# reveal then holds. The bedroll with the slot full grants its Glassbone
# only, and asks (_answer()).
func _activate(index: int) -> void:
	if _done:
		return
	if index == DISMISS:
		_done = true
		print("BelongingsScreen: walked on.")
		_log_choice(-1, 0, null)
		_finish(-1)
		return
	if not _has_slot(index):
		return
	_done = true
	_taken = index
	var glassbone: int = _glassbone_in(index)
	if glassbone > 0:
		RunState.add_glassbone(glassbone)
		TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, glassbone_volume_db, "GlassboneTakeAudio", "BelongingsScreen")
		print("BelongingsScreen: took %d Glassbone with it (run total %d)." % [glassbone, RunState.glassbone])
	match index:
		Slot.GOLD:
			RunState.add_gold(_gold)
			_log_choice(index, glassbone, null)
			TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoldTakeAudio", "BelongingsScreen")
			print("BelongingsScreen: took %d gold (run total %d)." % [_gold, RunState.gold])
		Slot.CARD:
			RunState.add_card(_card)
			_log_choice(index, glassbone, null)
			TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "BelongingsScreen")
			print("BelongingsScreen: took '%s' (deck now %d)." % [_card.card_name, RunState.deck.size()])
		Slot.KEEPSAKE:
			# Offered once it is seen - here, at the reveal.
			RunState.note_keepsake_offered(_keepsake)
			_held = RunState.keepsake
			if _held != null:
				_asking = true
				print("BelongingsScreen: found '%s'; asking whether to replace '%s'." % [_keepsake.display_name, _held.display_name])
			else:
				RunState.equip_keepsake(_keepsake)
				_log_choice(index, glassbone, null)
				TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, keepsake_volume_db, "KeepsakeTakeAudio", "BelongingsScreen")
				print("BelongingsScreen: took '%s'." % _keepsake.display_name)
	_sync_card_lift()
	_sync_keepsake_tiles()
	_draw_layer.queue_redraw()
	if _asking:
		return
	var hold: Tween = create_tween()
	hold.tween_interval(maxf(result_hold_time, 0.0))
	hold.tween_callback(_end_hold)

# The full-slot question answered - the first answer wins. REPLACE puts
# the bedroll's keepsake in the slot, whatever was held gone; KEEP leaves
# it behind. Either closes the screen; the take is spent either way.
func _answer(choice: int) -> void:
	if not _asking:
		return
	_asking = false
	_log_choice(Slot.KEEPSAKE, _glassbone_in(Slot.KEEPSAKE), choice == Choice.REPLACE)
	if choice == Choice.REPLACE:
		RunState.equip_keepsake(_keepsake)
		TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, keepsake_volume_db, "KeepsakeTakeAudio", "BelongingsScreen")
		print("BelongingsScreen: took '%s' (left '%s')." % [_keepsake.display_name, _held.display_name])
	else:
		print("BelongingsScreen: left '%s' (kept '%s')." % [_keepsake.display_name, _held.display_name])
	_finish(Slot.KEEPSAKE)

# The choice, for the run log: what each column held, which was taken
# (-1 walked on), the Glassbone that came with it, and - when the slot
# was full - whether the bedroll's keepsake replaced the one held (null
# when there was nothing to replace).
func _log_choice(taken: int, glassbone_taken: int, replaced: Variant) -> void:
	var glassbone_slot: String = String(Slot.find_key(_glassbone_slot)).to_lower() if _glassbone_slot >= 0 else ""
	var offered: Dictionary = {
		"gold": _gold if _has_slot(Slot.GOLD) else 0,
		"card": RunLogger.or_null(_card.card_name if _has_slot(Slot.CARD) else ""),
		"keepsake": RunLogger.keepsake_id(_keepsake if _has_slot(Slot.KEEPSAKE) else null),
		"glassbone": {"slot": RunLogger.or_null(glassbone_slot), "amount": maxi(_glassbone_amount, 0)},
	}
	RunLogger.event("belongings", {
		"offered": offered,
		"taken": RunLogger.or_null(String(Slot.find_key(taken)).to_lower() if taken >= 0 else ""),
		"glassbone_taken": glassbone_taken,
		"held_before": RunLogger.keepsake_id(_held),
		"replaced": replaced,
	})

# The hold is over: a taken card flies to the Belongings panel and the
# screen closes as it lands; anything else closes now.
func _end_hold() -> void:
	var view: CardView = _lifted if _taken == Slot.CARD and reveal_card_on_take else null
	if view == null:
		_finish(_taken)
		return
	_flying = true
	_lifted = null
	view.set_keyword_inspect(false)
	_draw_layer.queue_redraw()
	var taken: int = _taken
	var tween: Tween = TakeFeedback.fly_to(self, view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(func() -> void:
		_finish(taken))

# The pack's card at inspect size: not interactive anywhere on its face,
# and scaled about its top-left so TakeFeedback.fly_to()'s placement
# holds.
func _new_card_view(card_data: CardData) -> CardView:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("BelongingsScreen: could not load %s; no card shown." % CARD_VIEW_SCENE_PATH)
		return null
	var view := scene.instantiate() as CardView
	view.hover_enabled = false
	_draw_layer.add_child(view)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in view.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.pivot_offset = Vector2.ZERO
	view.set_card_data(card_data)
	return view

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("BelongingsScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

func _finish(taken: int) -> void:
	closed.emit(taken)
	queue_free()
