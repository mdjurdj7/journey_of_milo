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
# Lower, one row of three columns side by side, centred across the
# screen at columns_centre_fraction of its height, each its object alone
# - the case, the pack, the shard of Glassbone, rendered from their
# models (see _build_render()) - and just above the row the rule, TAKE
# ONE, in the system voice's tracked caps. The three lie on one worn
# blanket on the sand, on one baseline, each over a soft contact shadow,
# the shard on a small folded square of cloth with a corner turned back
# (the Ground group) - rendered as a second view of the objects' world.
# A soft band of the ink, feathered top and bottom, darkens the screen's
# full width behind the row and behind WALK ON, over the scrim - the
# ground the labels read on. What each offers is fixed (Slot) and named
# under its column in the choices' tracked caps - 45 GOLD (the cache's
# coin_amount), LOOK INSIDE, GLASSBONE ×1; which cards, stay a mystery
# until it's taken. A column with nothing to offer is not drawn and
# cannot be focused.
#
# The objects wear what they wear on the sand: each model's own colour
# map on the painted shader, times the cache's object_tint (Belongings
# Object.painted_material()) - or, where the cache names a material for
# its column, that material untinted (the shard's Glassbone) - lit by
# the field's own sun and ambient as the field camera sees them
# (light_like()).
#
# The focus language is on the object itself, the title menu's two
# states carried over: at rest the object is drawn down (rest_modulate)
# and its kind in the rest grey; focused it is drawn as rendered, lifted
# focus_lift_px off the cloth (eased), its kind in bone, with the short
# hairline centred under it. The mouse focuses by hovering a column and takes by
# clicking it; ui_left/ui_right move across the columns (wrapping),
# ui_down drops to WALK ON, ui_up returns, ui_accept takes. Nothing is
# focused until the mouse or a key says so. WALK ON keeps the text form
# of the language (grey at rest, bone and a hairline to its left).
#
# The coin or the Glassbone taken is the reveal. The taken column stays
# full bone with its hairline, the other two dim (dimmed_modulate), TAKE
# ONE and WALK ON go, and what it held shows under it in full bone -
# "+45 gold", "+ Glassbone ×1" - granted through RunState as it's
# revealed, with the take's sound. The reveal holds for result_hold_time
# and the screen closes.
#
# LOOK INSIDE commits to the pack: the coin and the Glassbone are no
# longer on offer. The row and its band go, and the pack's cards - the
# distinct ones BelongingsCache.roll() drew with the floor - are laid out
# in a level row at card_inspect_scale, centred, card_pick_gap_fraction
# of a card's width apart, their centre line at card_inspect_centre_
# fraction of the height; TAKE ONE over them, TAKE NOTHING under them in
# WALK ON's place and form. The cards and TAKE NOTHING are one focus set,
# a focused card wearing the column's hairline under it. The mouse
# focuses by hovering and takes by clicking; ui_left/ui_right move across
# the cards (wrapping), ui_down drops to TAKE NOTHING, ui_up returns,
# ui_accept takes; ui_cancel and a right click are TAKE NOTHING. Each
# card's keywords define themselves on hover. A card taken goes into the
# deck (RunState.add_card()) and the others go; it holds for result_
# hold_time, then flies to the Belongings panel (reveal_card_on_take) and
# the screen closes as it lands. TAKE NOTHING closes at once. The pack is
# spent either way.
#
# Glassbone may also ride with the coin or the pack (BelongingsCache.
# glassbone_chance - 0 on floor 2's): "+ Glassbone ×N" under the coin's
# reveal, or under the pack's cards once it's opened, granted as either
# is taken.
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

# Column order - the case, the pack, the shard (BelongingsCache).
enum Slot { GOLD, CARD, GLASSBONE }

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"
const SLOT_COUNT := 3
# The two passes' render layers: the objects, and the ground under them.
const OBJECT_LAYER := 2
const GROUND_LAYER := 1
# The focus index WALK ON takes, after the three columns - and TAKE
# NOTHING, in its place, while the pack's cards are up.
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
# em), its baseline this far above the row's top - the columns', or the
# pack's cards'.
@export var take_one_text: String = "TAKE ONE":
	set(value):
		take_one_text = value
		_refresh()
@export var take_one_gap_px: float = 12.0:
	set(value):
		take_one_gap_px = value
		_refresh()
@export_group("")

@export_group("Columns")
# Each column is a square this many pixels across - its object's render;
# at 216 no object stands taller than a fifth of a 1080 screen.
@export var column_px: float = 216.0:
	set(value):
		column_px = value
		_render_objects()
		_refresh()
@export var column_gap_px: float = 96.0:
	set(value):
		column_gap_px = value
		_refresh()
# The row's centre, as a fraction of the viewport height - between the
# world line and WALK ON, its kinds clearing the frozen Wanderer, whose
# head the field camera keeps near y 0.57.
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
# An object at rest is drawn at this multiple of its render - neutral, so
# its colours only dim.
@export var rest_modulate: Color = Color(0.78, 0.78, 0.78, 1.0):
	set(value):
		rest_modulate = value
		_refresh()
# Each column's kind under it, in the choices' tracked caps (choice_word_
# size_px): the coin's amount (the cache's coin_amount) in gold_kind_
# format, LOOK INSIDE, the Glassbone on offer in glassbone_kind_format -
# the baseline kind_label_gap_px under the column's square. Grey at rest
# (unfocused_color), bone on focus; gone with the take.
@export var gold_kind_format: String = "%d GOLD":
	set(value):
		gold_kind_format = value
		_refresh()
@export var card_kind_text: String = "LOOK INSIDE":
	set(value):
		card_kind_text = value
		_refresh()
@export var glassbone_kind_format: String = "GLASSBONE ×%d":
	set(value):
		glassbone_kind_format = value
		_refresh()
@export var kind_label_gap_px: float = 34.0:
	set(value):
		kind_label_gap_px = value
		_refresh()
@export var choice_word_size_px: int = 17:
	set(value):
		choice_word_size_px = value
		_rebuild_fonts()
@export_group("")

@export_group("Band")
# Behind the row - from band_pad_px over TAKE ONE's caps to band_pad_px
# under the kinds - and behind WALK ON: the ink at band_alpha across the
# full width, eased to nothing over band_feather_px above and below - over
# the scrim. It is the ground the labels read on: at 0.6, over the pale
# sand (the fog's 0.87) under the scrim, bone reads about 6:1 and
# unfocused_color about 4.9:1.
@export_range(0.0, 1.0) var band_alpha: float = 0.6:
	set(value):
		band_alpha = value
		_refresh()
@export var band_pad_px: float = 24.0:
	set(value):
		band_pad_px = value
		_refresh()
@export var band_feather_px: float = 70.0:
	set(value):
		band_feather_px = value
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

@export_group("Card Inspect")
# The pack's cards, once it's opened: each at the deck view's inspect size
# (DeckView.inspect_scale), card_pick_gap_fraction of a card's width
# apart, the row centred, its centre line at this fraction of the
# viewport height. A Glassbone line hangs under the row.
@export var card_inspect_scale: float = 2.2:
	set(value):
		card_inspect_scale = value
		_refresh()
@export_range(0.0, 1.0) var card_pick_gap_fraction: float = 0.2:
	set(value):
		card_pick_gap_fraction = value
		_refresh()
@export_range(0.0, 1.0) var card_inspect_centre_fraction: float = 0.47:
	set(value):
		card_inspect_centre_fraction = value
		_refresh()
# The focused card's hairline: this far under the card.
@export var card_hairline_gap_px: float = 14.0:
	set(value):
		card_hairline_gap_px = value
		_refresh()
# In WALK ON's place and form while the cards are up.
@export var take_nothing_text: String = "TAKE NOTHING":
	set(value):
		take_nothing_text = value
		_refresh()
@export_group("")

@export_group("Result")
# Seconds the reveal holds before the screen closes (a card flies
# first). Read on the take.
@export var result_hold_time: float = 1.2
# The two columns not taken, through the reveal: their objects at this
# multiple of their render - neutral, as rest_modulate is.
@export var dimmed_modulate: Color = Color(0.6, 0.6, 0.6, 0.35):
	set(value):
		dimmed_modulate = value
		_refresh()
@export_group("")

@export_group("Objects")
# The render: one SubViewport, three cells side by side, one render. The
# models keep their relative sizes at the cache's object_scales (the
# same as on the sand), the largest fitted to its cell.
# Each its own colour map times this tint - the cache's object_tint, which
# RegionField hands over, so the render matches the sand. A column with a
# material of its own (setup()) wears that, untinted.
@export var object_tint: Color = Color(0.76, 0.62, 0.46, 1.0):
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
# Without the field's light (light_like()): the key light, from over the
# viewer's left shoulder, and the flat fill.
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
# Each object's own scale on the screen on top of the cache's (column
# order) - the case a little larger, so the three weigh alike.
@export var object_screen_scales: PackedFloat32Array = PackedFloat32Array([1.25, 1.0, 1.0]):
	set(value):
		object_screen_scales = value
		_render_objects()
# The row's baseline: every object stands on it, this far down its
# column's square.
@export_range(0.0, 1.0) var base_line_fraction: float = 0.8:
	set(value):
		base_line_fraction = value
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

@export_group("Ground")
# The three lie on one worn blanket on the sand, in the region's cool
# palette: cloth_color, worn toward cloth_wear_color in soft patches
# (cloth_wear_scale of them across the cloth). On screen it reaches
# cloth_side_px past the outer columns, cloth_back_px above the baseline
# and cloth_front_px below it - clear of the kinds. Each object casts a
# soft contact shadow: shadow_color, shadow_scale of its footprint, its
# edge fading from shadow_softness of the way out. The shard rests on a
# small folded square of cloth (fold_color, its turned-back corner fold_
# flap_color), fold_scale of its footprint, the corner turned fold_turn_
# fraction of the way in, turned fold_yaw_degrees. All re-apply live.
@export var cloth_color: Color = Color(0.33, 0.36, 0.39, 1.0):
	set(value):
		cloth_color = value
		_render_objects()
@export var cloth_wear_color: Color = Color(0.44, 0.47, 0.49, 1.0):
	set(value):
		cloth_wear_color = value
		_render_objects()
@export var cloth_wear_scale: float = 3.0:
	set(value):
		cloth_wear_scale = value
		_render_objects()
@export var cloth_side_px: float = 48.0:
	set(value):
		cloth_side_px = value
		_render_objects()
@export var cloth_back_px: float = 70.0:
	set(value):
		cloth_back_px = value
		_render_objects()
@export var cloth_front_px: float = 22.0:
	set(value):
		cloth_front_px = value
		_render_objects()
@export var shadow_color: Color = Color(0.06, 0.07, 0.09, 0.55):
	set(value):
		shadow_color = value
		_render_objects()
@export var shadow_scale: float = 1.3:
	set(value):
		shadow_scale = value
		_render_objects()
@export_range(0.0, 1.0) var shadow_softness: float = 0.35:
	set(value):
		shadow_softness = value
		_render_objects()
@export var fold_color: Color = Color(0.52, 0.55, 0.58, 1.0):
	set(value):
		fold_color = value
		_render_objects()
@export var fold_flap_color: Color = Color(0.43, 0.46, 0.49, 1.0):
	set(value):
		fold_flap_color = value
		_render_objects()
@export var fold_scale: float = 1.5:
	set(value):
		fold_scale = value
		_render_objects()
@export_range(0.0, 0.9) var fold_turn_fraction: float = 0.35:
	set(value):
		fold_turn_fraction = value
		_render_objects()
@export var fold_yaw_degrees: float = 10.0:
	set(value):
		fold_yaw_degrees = value
		_render_objects()
# The focused object lifts focus_lift_px off the cloth, eased over
# focus_lift_sec; its shadow stays.
@export var focus_lift_px: float = 6.0
@export var focus_lift_sec: float = 0.15
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
# A label at rest - the kinds, WALK ON, TAKE NOTHING: light enough to
# hold 4.5:1 on the band (band_alpha).
@export var unfocused_color: Color = Color(0.82, 0.82, 0.84, 1.0):
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
# A taken card flies from its place to the Belongings panel - after the
# choice. Off = the sound alone.
@export var reveal_card_on_take: bool = true
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
# Glassbone has no take sound of its own: the gold take, under it
# (RewardScreen.glassbone_volume_db).
@export var glassbone_volume_db: float = -24.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
@export_group("")

var _line: String = ""
var _gold: int = 0
# The pack's cards, distinct; empty = that column is left out.
var _cards: Array[CardData] = []
# What the shard's column holds; 0 = that column is left out.
var _glassbone_offer: int = 0
var _glassbone_slot: int = -1
var _glassbone_amount: int = 0
var _object_paths: PackedStringArray = PackedStringArray()
var _object_scales: PackedFloat32Array = PackedFloat32Array()
var _object_materials: PackedStringArray = PackedStringArray()
var _deck_panel: Control = null

var _scrim: ColorRect = null
var _draw_layer: Control = null
var _line_font: Font = null
var _label_font: Font = null
var _contents_font: Font = null
var _choice_font: Font = null
# The pack's cards while they're up (_open_pack()), in _cards' order; the
# taken one alone once it's taken, until it flies.
var _pick_views: Array[CardView] = []

var _viewport: SubViewport = null
# The ground pass - the cloth, the shadows, the fold - a second view of
# the same world (layer GROUND_LAYER), drawn first.
var _ground_viewport: SubViewport = null
var _ground_camera: Camera3D = null
var _cloth: MeshInstance3D = null
var _cloth_material: StandardMaterial3D = null
var _shadows: Array[MeshInstance3D] = []
var _fold: MeshInstance3D = null
# The render's rect on screen, and its pixels per screen pixel.
var _render_rect: Rect2 = Rect2()
var _render_scale: float = 1.0
# Each column's lift now (focus_lift_px when focused), and its tween.
var _lift: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _lift_tweens: Array[Tween] = [null, null, null]
var _camera: Camera3D = null
var _light: DirectionalLight3D = null
var _environment: Environment = null
# Per column, the model's material (null with no model), and whether it's
# the painted one that wears object_tint.
var _materials: Array[Material] = []
var _tinted: Array[bool] = []
# The field's light, once light_like() has it.
var _field_lit: bool = false
var _field_light_direction: Vector3 = Vector3.DOWN
var _field_light_color: Color = Color.WHITE
var _field_light_energy: float = 1.0
var _field_shadow_opacity: float = 1.0
var _field_ambient_color: Color = Color.WHITE
var _field_ambient_energy: float = 1.0
var _field_tonemap_mode: Environment.ToneMapper = Environment.TONE_MAPPER_LINEAR
var _field_tonemap_exposure: float = 1.0
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
# The pack opened (LOOK INSIDE): its cards up, and the one focused - a
# card's index, DISMISS for TAKE NOTHING, -1 nothing - and what the mouse
# is over, as _focus and _mouse_on are for the columns. _picked is the
# card taken, -1 before (or for nothing).
var _picking: bool = false
var _pick_focus: int = -1
var _pick_mouse_on: int = -1
var _picked: int = -1

# Called by RegionField before the screen enters the tree, after setup():
# the objects' light is the field's - sun (its direction turned into the
# field camera's yaw, so a face lit on the sand is lit here), ambient and
# tonemap. Without it the render keeps the exports' key light and fill.
func light_like(sun: DirectionalLight3D, sky: RegionSky, camera: Camera3D) -> void:
	if sun == null or sky == null or camera == null:
		return
	_field_lit = true
	_field_light_direction = (-sun.global_basis.z).rotated(Vector3.UP, -camera.global_basis.get_euler().y)
	_field_light_color = sun.light_color
	_field_light_energy = sun.light_energy
	_field_shadow_opacity = sun.shadow_opacity
	_field_ambient_color = sky.ambient_color
	_field_ambient_energy = sky.ambient_energy
	_field_tonemap_mode = sky.tonemap_mode
	_field_tonemap_exposure = sky.tonemap_exposure
	_render_objects()

# Called by RegionField before the screen enters the tree. gold and
# glassbone_offer may be 0 and cards empty - that column is then left
# out. glassbone_slot is the column that also holds glassbone_amount
# Glassbone (the coin's or the pack's), -1 for none. object_paths are the
# three models and object_scales their scales, column order - the same
# scales the cache puts on the sand; object_materials, where a column
# names one, the material its model wears instead of the painted one.
func setup(line: String, gold: int, cards: Array[CardData], glassbone_offer: int, glassbone_slot: int, glassbone_amount: int, object_paths: PackedStringArray, object_scales: PackedFloat32Array, object_materials: PackedStringArray, deck_panel: Control) -> void:
	_line = line
	_gold = gold
	_cards = cards.duplicate()
	_glassbone_offer = glassbone_offer
	_glassbone_slot = glassbone_slot
	_glassbone_amount = glassbone_amount
	_object_paths = object_paths
	_object_scales = object_scales
	_object_materials = object_materials
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
	_draw_layer.resized.connect(_render_objects)
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
	_place_pick()

func _has_slot(slot: int) -> bool:
	match slot:
		Slot.GOLD:
			return _gold > 0
		Slot.CARD:
			return not _cards.is_empty()
		Slot.GLASSBONE:
			return _glassbone_offer > 0
	return false

# Whether a column can be taken: it holds something.
func can_take(slot: int) -> bool:
	return _has_slot(slot)

# What's named under a column before the take: its kind, and how much.
func kind_text(slot: int) -> String:
	match slot:
		Slot.GOLD:
			return gold_kind_format % _gold
		Slot.CARD:
			return card_kind_text
		Slot.GLASSBONE:
			return glassbone_kind_format % _glassbone_offer
	return ""

# The Glassbone that rides with a column (the coin's or the pack's), 0
# for none.
func _glassbone_in(slot: int) -> int:
	return maxi(_glassbone_amount, 0) if slot == _glassbone_slot and _has_slot(slot) else 0

# The columns that hold something, left to right - drawn and takeable.
func _present_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if _has_slot(slot):
			slots.append(slot)
	return slots

# The columns that can be taken, left to right - what focus moves through.
func _takeable_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in SLOT_COUNT:
		if can_take(slot):
			slots.append(slot)
	return slots

# For probes: whether the pack is open, and its cards' views while it is.
func is_picking() -> bool:
	return _picking

func get_pick_views() -> Array[CardView]:
	return _pick_views.duplicate()

# --- The objects' render ---

# One SubViewport three cells wide, its own world, transparent, rendered
# once (and again when a render export changes): the three models side
# by side along X, one cell apart, each centred on its own bbox and
# turned by its own yaw, under one orthographic camera whose frame is
# exactly the three cells. Each model on its own painted material - or the
# material its column names - lit by one directional light and a flat
# ambient. Cheaper than three viewports - one world, one camera,
# one render pass - and the columns draw sub-rects of its one texture.
func _build_render() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Objects"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.size = Vector2i.ONE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	get_viewport().size_changed.connect(_render_objects)

	for slot in SLOT_COUNT:
		var model: Node3D = null
		var material: Material = null
		var tinted: bool = false
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
			var own_path: String = _object_materials[slot] if slot < _object_materials.size() else ""
			if not own_path.is_empty():
				material = load(own_path) as Material
				if material == null:
					push_warning("BelongingsScreen: could not load object %d's material (%s); painted instead." % [slot, own_path])
			if material == null:
				tinted = true
				material = BelongingsObject.painted_material(path, object_tint)
				if material == null:
					material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
					BelongingsObject.set_material_tint(material, object_tint)
			var has_aabb := false
			for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh_instance as MeshInstance3D
				mi.material_override = material
				mi.layers = 1 << (OBJECT_LAYER - 1)
				var mi_aabb: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
				aabb = mi_aabb if not has_aabb else aabb.merge(mi_aabb)
				has_aabb = true
		_models.append(model)
		_model_aabbs.append(aabb)
		_materials.append(material)
		_tinted.append(tinted)
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
	_camera = _new_camera(OBJECT_LAYER)
	_viewport.add_child(_camera)
	_build_ground()
	_render_objects()

func _new_camera(layer_number: int) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = 1 << (layer_number - 1)
	return camera

# The ground pass: its own view of the objects' world, seeing only the
# ground layer - the cloth, a shadow under each object, the shard's fold.
func _build_ground() -> void:
	_ground_viewport = SubViewport.new()
	_ground_viewport.name = "Ground"
	_ground_viewport.transparent_bg = true
	_ground_viewport.msaa_3d = Viewport.MSAA_4X
	_ground_viewport.size = Vector2i.ONE
	_ground_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_ground_viewport)
	_ground_viewport.world_3d = _viewport.find_world_3d()
	_ground_camera = _new_camera(GROUND_LAYER)
	_ground_viewport.add_child(_ground_camera)

	_cloth = MeshInstance3D.new()
	_cloth.name = "Cloth"
	_cloth.layers = 1 << (GROUND_LAYER - 1)
	_cloth.mesh = PlaneMesh.new()
	_cloth_material = StandardMaterial3D.new()
	_cloth_material.roughness = 1.0
	var wear := NoiseTexture2D.new()
	wear.seamless = true
	wear.noise = FastNoiseLite.new()
	wear.color_ramp = Gradient.new()
	_cloth_material.albedo_texture = wear
	_cloth.material_override = _cloth_material
	_viewport.add_child(_cloth)

	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.gradient = Gradient.new()
	for slot in SLOT_COUNT:
		var shadow := MeshInstance3D.new()
		shadow.name = "Shadow%d" % slot
		shadow.layers = 1 << (GROUND_LAYER - 1)
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE
		shadow.mesh = quad
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = soft
		shadow.material_override = material
		shadow.visible = false
		_viewport.add_child(shadow)
		_shadows.append(shadow)

	_fold = MeshInstance3D.new()
	_fold.name = "Fold"
	_fold.layers = 1 << (GROUND_LAYER - 1)
	var fold_material := StandardMaterial3D.new()
	fold_material.roughness = 1.0
	fold_material.vertex_color_use_as_albedo = true
	_fold.material_override = fold_material
	_fold.visible = false
	_viewport.add_child(_fold)

# A column with no model is a column with nothing to take.
func _drop_slot(slot: int) -> void:
	match slot:
		Slot.GOLD:
			_gold = 0
		Slot.CARD:
			_cards.clear()
		Slot.GLASSBONE:
			_glassbone_offer = 0

func _render_objects() -> void:
	if _viewport == null or _camera == null or _ground_camera == null or _draw_layer == null:
		return
	for slot in _materials.size():
		if _tinted[slot]:
			BelongingsObject.set_material_tint(_materials[slot], object_tint)
	# One column is one bounding-sphere diameter of the largest object,
	# over object_fill: px_per_m screen pixels to the metre.
	var diameter: float = 0.01
	for slot in _model_aabbs.size():
		diameter = maxf(diameter, _model_aabbs[slot].size.length() * _scale_of(slot))
	var cell: float = diameter / maxf(object_fill, 0.1)
	var px_per_m: float = column_px / cell
	var pitch: float = deg_to_rad(object_pitch_degrees)
	var depth_px: float = maxf(sin(pitch), 0.05) * px_per_m
	var row_centre_x: float = _draw_layer.size.x / 2.0
	var base_y: float = _base_line_y()
	# The render's rect: the columns' tops to past the cloth's front edge,
	# the cloth's width, each side padded for the shadows.
	var cloth_left: float = _column_rect(0).position.x - cloth_side_px
	var cloth_right: float = _column_rect(SLOT_COUNT - 1).end.x + cloth_side_px
	var pad: float = column_px * 0.1
	var top: float = minf(_column_rect(0).position.y, base_y - cloth_back_px) - pad
	var bottom: float = maxf(base_y + cloth_front_px, base_y) + pad
	_render_rect = Rect2(cloth_left - pad, top, cloth_right - cloth_left + pad * 2.0, bottom - top).abs()
	# Rendered in whole pixels at the window's scale: the rect takes the
	# size those pixels cover, so the cameras map to it exactly.
	_render_scale = float(_render_cell_size()) / maxf(column_px, 1.0)
	var pixels := Vector2i(maxi(ceili(_render_rect.size.x * _render_scale), 1), maxi(ceili(_render_rect.size.y * _render_scale), 1))
	_render_rect.size = Vector2(pixels) / _render_scale
	# Each object on the baseline at its column's centre: its base on y 0,
	# its footprint centred on z 0.
	for slot in _models.size():
		var model: Node3D = _models[slot]
		var shadow: MeshInstance3D = _shadows[slot] if slot < _shadows.size() else null
		if model == null:
			if shadow != null:
				shadow.visible = false
			continue
		var yaw: float = deg_to_rad(object_yaws_degrees[slot]) if slot < object_yaws_degrees.size() else 0.0
		var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * _scale_of(slot))
		var placed: AABB = Transform3D(basis, Vector3.ZERO) * _model_aabbs[slot]
		var x: float = (_column_rect(slot).get_center().x - row_centre_x) / px_per_m
		var centre := Vector3(placed.get_center().x, placed.position.y, placed.get_center().z)
		model.transform = Transform3D(basis, Vector3(x, 0.0, 0.0) - centre)
		if shadow != null:
			shadow.visible = true
			shadow.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(placed.size.x, 1.0, placed.size.z) * shadow_scale), Vector3(x, 0.002, 0.0))
			var shadow_material := shadow.material_override as StandardMaterial3D
			shadow_material.albedo_color = shadow_color
			var soft := shadow_material.albedo_texture as GradientTexture2D
			soft.gradient.offsets = PackedFloat32Array([clampf(1.0 - shadow_softness, 0.0, 0.99), 1.0])
			soft.gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
		if slot == Slot.GLASSBONE:
			_place_fold(Vector3(x, 0.0, 0.0), placed.size, yaw)
	# The cloth, from the screen's edges back to the ground: a ground point
	# z metres toward the viewer sits z * depth_px lower on screen.
	var plane := _cloth.mesh as PlaneMesh
	var back_z: float = -cloth_back_px / depth_px
	var front_z: float = cloth_front_px / depth_px
	plane.size = Vector2((cloth_right - cloth_left) / px_per_m, front_z - back_z)
	_cloth.position = Vector3((cloth_left + cloth_right) / 2.0 / px_per_m - row_centre_x / px_per_m, 0.0, (back_z + front_z) / 2.0)
	var wear := _cloth_material.albedo_texture as NoiseTexture2D
	wear.color_ramp.colors = PackedColorArray([cloth_color, cloth_wear_color])
	_cloth_material.uv1_scale = Vector3(maxf(cloth_wear_scale, 0.01), maxf(cloth_wear_scale, 0.01) * plane.size.y / maxf(plane.size.x, 0.01), 1.0)
	# Both cameras alike: the baseline at the row's centre lands on screen
	# at (row centre, base_y) of the render's rect.
	for camera: Camera3D in [_camera, _ground_camera]:
		camera.size = _render_rect.size.y / px_per_m
		camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * (cell * 4.0)
		camera.look_at(Vector3.ZERO, Vector3.UP)
		camera.h_offset = (_render_rect.get_center().x - row_centre_x) / px_per_m
		camera.v_offset = (base_y - _render_rect.get_center().y) / px_per_m
	if _field_lit:
		_light.light_color = _field_light_color
		_light.light_energy = _field_light_energy
		var up: Vector3 = Vector3.UP if absf(_field_light_direction.normalized().y) < 0.99 else Vector3.FORWARD
		_light.look_at_from_position(Vector3.ZERO, _field_light_direction, up)
		_light.shadow_enabled = true
		_light.shadow_opacity = _field_shadow_opacity
		_light.directional_shadow_max_distance = cell * 8.0
		_environment.ambient_light_color = _field_ambient_color
		_environment.ambient_light_energy = _field_ambient_energy
		_environment.tonemap_mode = _field_tonemap_mode
		_environment.tonemap_exposure = _field_tonemap_exposure
	else:
		_light.light_energy = light_energy
		_light.rotation = Vector3(deg_to_rad(light_pitch_degrees), deg_to_rad(light_yaw_degrees), 0.0)
		_environment.ambient_light_energy = ambient_energy
	for viewport: SubViewport in [_viewport, _ground_viewport]:
		viewport.size = pixels
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_refresh()

# The shard's folded square under it: fold_scale of its footprint, turned
# fold_yaw_degrees on its own, the corner nearest the viewer turned back
# fold_turn_fraction of the way in - the flap lying on top, its underside
# up (fold_flap_color), the ground showing where the corner was.
func _place_fold(at: Vector3, footprint: Vector3, yaw: float) -> void:
	var half: float = maxf(footprint.x, footprint.z) * fold_scale * 0.5
	var turn: float = half * 2.0 * clampf(fold_turn_fraction, 0.0, 0.9)
	var a := Vector3(-half, 0.0, -half)
	var b := Vector3(half, 0.0, -half)
	var d := Vector3(-half, 0.0, half)
	var m1 := Vector3(half, 0.0, half - turn)
	var m2 := Vector3(half - turn, 0.0, half)
	var flap := Vector3(half - turn, 0.0, half - turn)
	var lift := Vector3(0.0, 0.001, 0.0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	surface.set_color(fold_color)
	for vertex: Vector3 in [a, b, m1, a, m1, m2, a, m2, d]:
		surface.add_vertex(vertex)
	surface.set_color(fold_flap_color)
	for vertex: Vector3 in [m1 + lift, flap + lift, m2 + lift]:
		surface.add_vertex(vertex)
	_fold.mesh = surface.commit()
	_fold.transform = Transform3D(Basis(Vector3.UP, yaw + deg_to_rad(fold_yaw_degrees)), at + Vector3(0.0, 0.003, 0.0))
	_fold.visible = true

# The row's baseline on screen.
func _base_line_y() -> float:
	return _column_rect(0).position.y + column_px * clampf(base_line_fraction, 0.0, 1.0)

func _scale_of(slot: int) -> float:
	var on_sand: float = _object_scales[slot] if slot < _object_scales.size() else 1.0
	return on_sand * (object_screen_scales[slot] if slot < object_screen_scales.size() else 1.0)

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

# TAKE ONE's baseline, just above the row - the pack's cards' while
# they're up.
func _take_one_baseline() -> float:
	if _picking:
		return roundf(_pick_row().position.y - take_one_gap_px)
	return roundf(_column_rect(Slot.GOLD).position.y - take_one_gap_px)

# A column's kind: its baseline under the square.
func _kind_baseline(slot: int) -> float:
	return roundf(_column_rect(slot).end.y + kind_label_gap_px)

func _dismiss_text() -> String:
	return take_nothing_text if _picking else dismiss_text

func _dismiss_baseline() -> float:
	return roundf(_draw_layer.size.y * dismiss_baseline_fraction)

func _dismiss_label_left() -> float:
	return roundf((_draw_layer.size.x - InkType.width(_label_font, _dismiss_text(), label_size_px)) / 2.0)

# WALK ON's label (TAKE NOTHING's) and the hairline's room to its left.
func _dismiss_rect() -> Rect2:
	var label_left: float = _dismiss_label_left()
	var left: float = label_left - hairline_gap_px - hairline_length_px
	var right: float = label_left + InkType.width(_label_font, _dismiss_text(), label_size_px)
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
	if _picking:
		_text(_line_font, _line, Vector2(roundf((_draw_layer.size.x - line_width) / 2.0), line_baseline), line_size_px, bone)
		_draw_pick()
		return
	_draw_band()
	_text(_line_font, _line, Vector2(roundf((_draw_layer.size.x - line_width) / 2.0), line_baseline), line_size_px, bone)
	if _taken < 0:
		_text_centred(_label_font, take_one_text, _draw_layer.size.x / 2.0, _take_one_baseline(), label_size_px, bone)

	# The ground first, whole; then each object in its column - drawn down
	# at rest, lifted when focused.
	var ground: Texture2D = _ground_viewport.get_texture() if _ground_viewport != null else null
	if ground != null:
		_draw_layer.draw_texture_rect(ground, _render_rect, false)
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
			var lift: float = _lift[slot] if slot < _lift.size() else 0.0
			var dest := Rect2(rect.position.x, _render_rect.position.y - lift, rect.size.x, _render_rect.size.y)
			var source := Rect2((rect.position.x - _render_rect.position.x) * _render_scale, 0.0, rect.size.x * _render_scale, _render_rect.size.y * _render_scale)
			_draw_layer.draw_texture_rect_region(texture, dest, source, tint)
		if lit:
			var y: float = rect.end.y + object_hairline_gap_px
			_draw_layer.draw_rect(Rect2(roundf(rect.get_center().x - object_hairline_length_px / 2.0), y, object_hairline_length_px, hairline_thickness_px), bone)
		if _taken < 0:
			_text_centred(_choice_font, kind_text(slot), rect.get_center().x, _kind_baseline(slot), choice_word_size_px, bone if lit else unfocused_color)

	if _taken >= 0:
		_reveal(_taken)
		return
	_draw_dismiss(_focus == DISMISS)

# WALK ON - or TAKE NOTHING - in the text form of the focus language.
func _draw_dismiss(focused: bool) -> void:
	var left: float = _dismiss_label_left()
	_text(_label_font, _dismiss_text(), Vector2(left, _dismiss_baseline()), label_size_px, bone if focused else unfocused_color)
	if focused:
		_hairline_left_of(left, _dismiss_baseline(), label_size_px)

# The bands: behind the row, solid from over TAKE ONE's caps to under the
# kinds, and behind WALK ON until the take - feathered to nothing above and
# below, the full width.
func _draw_band() -> void:
	if band_alpha <= 0.0:
		return
	_draw_band_over(_take_one_baseline() - float(label_size_px) * 0.72 - band_pad_px, _kind_baseline(Slot.GOLD) + band_pad_px)
	if _taken < 0:
		_draw_band_over(_dismiss_baseline() - float(label_size_px) * 0.72 - band_pad_px, _dismiss_baseline() + band_pad_px)

# One band, solid from `top` to `bottom`, feathered above and below.
func _draw_band_over(top: float, bottom: float) -> void:
	var on := Color(ink.r, ink.g, ink.b, band_alpha)
	var off := Color(ink.r, ink.g, ink.b, 0.0)
	var ys: Array[float] = [top - band_feather_px, top, bottom, bottom + band_feather_px]
	var colors: Array[Color] = [off, on, on, off]
	var width: float = _draw_layer.size.x
	for i in 3:
		if ys[i + 1] <= ys[i]:
			continue
		_draw_layer.draw_polygon(
			PackedVector2Array([Vector2(0.0, ys[i]), Vector2(width, ys[i]), Vector2(width, ys[i + 1]), Vector2(0.0, ys[i + 1])]),
			PackedColorArray([colors[i], colors[i], colors[i + 1], colors[i + 1]]))

# The focus language's text form: the short hairline to the left of a
# label at `left`, at its mid-height.
func _hairline_left_of(left: float, baseline: float, size_px: int) -> void:
	var mid: float = baseline - float(size_px) * 0.35
	_draw_layer.draw_rect(Rect2(left - hairline_gap_px - hairline_length_px, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

# Full bone: the focused column before the take, the taken one after.
func _is_lit(slot: int) -> bool:
	return slot == _taken if _taken >= 0 else slot == _focus

# What the taken coin or Glassbone column held, line by line in full bone
# under it.
func _reveal(slot: int) -> void:
	var rect: Rect2 = _column_rect(slot)
	var x: float = rect.get_center().x
	var y: float = rect.end.y + contents_gap_px
	match slot:
		Slot.GOLD:
			_text_centred(_contents_font, gold_format % _gold, x, y, contents_size_px, bone)
			y += contents_pitch_px
		Slot.GLASSBONE:
			_text_centred(_contents_font, glassbone_format % _glassbone_offer, x, y, contents_size_px, bone)
			y += contents_pitch_px
	_reveal_glassbone(slot, x, y)

# The "+ Glassbone" line under a reveal, where Glassbone rode with it.
func _reveal_glassbone(slot: int, x: float, y: float) -> void:
	var glassbone: int = _glassbone_in(slot)
	if glassbone > 0:
		_text_centred(_contents_font, glassbone_format % glassbone, x, y, contents_size_px, bone)

# --- The pack's cards ---

# The size of one card at card_inspect_scale.
func _pick_card_size() -> Vector2:
	var card_size: Vector2 = _pick_views[0].card_size if not _pick_views.is_empty() and is_instance_valid(_pick_views[0]) else Vector2(200.0, 280.0)
	return card_size * card_inspect_scale

# The cards' row: centred, its centre line at card_inspect_centre_
# fraction of the height - laid out for every card shown, so the one
# taken stays where it was.
func _pick_row() -> Rect2:
	var card: Vector2 = _pick_card_size()
	var count: int = maxi(_cards.size(), 1)
	var gap: float = card.x * card_pick_gap_fraction
	var span: float = float(count) * card.x + float(count - 1) * gap
	var left: float = roundf((_draw_layer.size.x - span) / 2.0)
	var top: float = roundf(_draw_layer.size.y * card_inspect_centre_fraction - card.y / 2.0)
	return Rect2(left, top, span, card.y)

# Card `index`'s face, in _cards' order.
func _pick_rect(index: int) -> Rect2:
	var card: Vector2 = _pick_card_size()
	var row: Rect2 = _pick_row()
	return Rect2(roundf(row.position.x + float(index) * card.x * (1.0 + card_pick_gap_fraction)), row.position.y, card.x, card.y)

# LOOK INSIDE: the cards up, TAKE ONE over them and TAKE NOTHING under,
# nothing focused yet.
func _open_pack() -> void:
	_picking = true
	_pick_focus = -1
	_pick_mouse_on = -1
	for card in _cards:
		var view: CardView = _new_card_view(card)
		if view == null:
			continue
		# Up for inspection: its keywords define themselves on hover.
		view.set_keyword_inspect(true)
		_pick_views.append(view)
	if _pick_views.size() != _cards.size():
		push_warning("BelongingsScreen: a card view failed to load; the pack offers TAKE NOTHING alone.")
		for view in _pick_views:
			view.queue_free()
		_pick_views.clear()
	_place_pick()
	# Opened, the pack's cards have arrived: each name sheens once.
	for view in _pick_views:
		view.play_name_sheen()
	_draw_layer.queue_redraw()

func _place_pick() -> void:
	if _flying or _draw_layer == null:
		return
	for index in _pick_views.size():
		var view: CardView = _pick_views[index]
		if not is_instance_valid(view):
			continue
		view.scale = Vector2.ONE * card_inspect_scale
		view.position = _pick_rect(_picked if _picked >= 0 else index).position

# Over the scrim while the pack is open: TAKE ONE, the focused card's
# hairline, TAKE NOTHING - and, once a card is taken, the Glassbone that
# rode with the pack under the row.
func _draw_pick() -> void:
	var row: Rect2 = _pick_row()
	if _picked >= 0:
		_reveal_glassbone(Slot.CARD, row.get_center().x, row.end.y + contents_gap_px)
		return
	_text_centred(_label_font, take_one_text, _draw_layer.size.x / 2.0, _take_one_baseline(), label_size_px, bone)
	if _pick_focus >= 0 and _pick_focus < _pick_views.size():
		var rect: Rect2 = _pick_rect(_pick_focus)
		_draw_layer.draw_rect(Rect2(roundf(rect.get_center().x - object_hairline_length_px / 2.0), rect.end.y + card_hairline_gap_px, object_hairline_length_px, hairline_thickness_px), bone)
	_draw_dismiss(_pick_focus == DISMISS)
	_reveal_glassbone(Slot.CARD, row.get_center().x, _dismiss_baseline() - contents_pitch_px * 1.5)

func _pick_hit(position: Vector2) -> int:
	for index in _pick_views.size():
		if _pick_rect(index).has_point(position):
			return index
	if _dismiss_rect().has_point(position):
		return DISMISS
	return -1

func _set_pick_focus(index: int) -> void:
	if index == _pick_focus:
		return
	_pick_focus = index
	_draw_layer.queue_redraw()

# The pack's answer - the first one wins. A card into the deck, the
# others gone, the reveal holding before it flies; TAKE NOTHING closes
# now.
func _take_pick(index: int) -> void:
	if not _picking or _picked >= 0:
		return
	if index == DISMISS:
		_picking = false
		print("BelongingsScreen: looked inside, took nothing.")
		_log_choice(Slot.CARD, _glassbone_in(Slot.CARD), null)
		_finish(Slot.CARD)
		return
	if index < 0 or index >= _pick_views.size():
		return
	_picked = index
	var card: CardData = _cards[index]
	RunState.add_card(card)
	_log_choice(Slot.CARD, _glassbone_in(Slot.CARD), card)
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "BelongingsScreen")
	print("BelongingsScreen: took '%s' (deck now %d)." % [card.card_name, RunState.deck.size()])
	var kept: CardView = _pick_views[index]
	for view in _pick_views:
		if view != kept:
			view.queue_free()
	_pick_views = [kept]
	_place_pick()
	_draw_layer.queue_redraw()
	var hold: Tween = create_tween()
	hold.tween_interval(maxf(result_hold_time, 0.0))
	hold.tween_callback(_end_hold)

# --- Input ---

func _hit(position: Vector2) -> int:
	for slot in _takeable_slots():
		if _column_rect(slot).has_point(position):
			return slot
	if _dismiss_rect().has_point(position):
		return DISMISS
	return -1

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	_focus = index
	_ease_lifts()
	_draw_layer.queue_redraw()

# Each column toward its lift: focus_lift_px for the focused one, none for
# the rest, eased over focus_lift_sec.
func _ease_lifts() -> void:
	for slot in SLOT_COUNT:
		var target: float = focus_lift_px if slot == _focus else 0.0
		if is_equal_approx(_lift[slot], target):
			continue
		if _lift_tweens[slot] != null and _lift_tweens[slot].is_valid():
			_lift_tweens[slot].kill()
		var tween: Tween = create_tween()
		tween.tween_method(_set_lift.bind(slot), _lift[slot], target, maxf(focus_lift_sec, 0.001)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_lift_tweens[slot] = tween

func _set_lift(value: float, slot: int) -> void:
	_lift[slot] = value
	_refresh()

# For probes: how far a column's object is lifted now.
func lift_of(slot: int) -> float:
	return _lift[slot] if slot >= 0 and slot < _lift.size() else 0.0

func _on_gui_input(event: InputEvent) -> void:
	# The cards take no mouse of their own (_new_card_view()), so their
	# keyword hover reads the motion here.
	if event is InputEventMouseMotion:
		for view in _pick_views:
			if is_instance_valid(view):
				view.update_keyword_hover()
	if _picking:
		_on_pick_gui_input(event)
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

# The pack's mouse: hover focuses, a click takes, a right click anywhere
# is TAKE NOTHING.
func _on_pick_gui_input(event: InputEvent) -> void:
	if _picked >= 0:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _pick_hit(motion.position)
		if under != _pick_mouse_on:
			if under >= 0:
				_set_pick_focus(under)
			elif _pick_focus == _pick_mouse_on:
				_set_pick_focus(-1)
			_pick_mouse_on = under
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_take_pick(DISMISS)
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _pick_hit(button.position)
		if index >= 0:
			_take_pick(index)
		_draw_layer.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _picking:
		_on_pick_key(event)
		return
	if _done:
		return
	var slots: Array[int] = _takeable_slots()
	var at: int = slots.find(_focus)
	if event.is_action_pressed("ui_right"):
		if not slots.is_empty():
			_set_focus(slots[posmod(at + 1, slots.size())] if at >= 0 else slots[0])
	elif event.is_action_pressed("ui_left"):
		if not slots.is_empty():
			_set_focus(slots[posmod(at - 1, slots.size())] if at >= 0 else slots[slots.size() - 1])
	elif event.is_action_pressed("ui_down"):
		_set_focus(DISMISS)
	elif event.is_action_pressed("ui_up"):
		if at < 0 and not slots.is_empty():
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

# The pack's keys: left/right across the cards (wrapping), down to TAKE
# NOTHING, up back to the cards, ui_accept takes, ui_cancel is TAKE
# NOTHING. The move keys do nothing here - the pack is already opened.
func _on_pick_key(event: InputEvent) -> void:
	if _picked >= 0:
		return
	var cards: int = _pick_views.size()
	var on_card: bool = _pick_focus >= 0 and _pick_focus < cards
	if event.is_action_pressed("ui_right"):
		if cards > 0:
			_set_pick_focus(posmod(_pick_focus + 1, cards) if on_card else 0)
	elif event.is_action_pressed("ui_left"):
		if cards > 0:
			_set_pick_focus(posmod(_pick_focus - 1, cards) if on_card else cards - 1)
	elif event.is_action_pressed("ui_down"):
		_set_pick_focus(DISMISS)
	elif event.is_action_pressed("ui_up"):
		if not on_card and cards > 0:
			_set_pick_focus(int(float(cards) / 2.0))
	elif event.is_action_pressed("ui_accept"):
		if _pick_focus >= 0:
			_take_pick(_pick_focus)
	elif event.is_action_pressed("ui_cancel"):
		_take_pick(DISMISS)
	else:
		return
	get_viewport().set_input_as_handled()

# A fresh press (never an echo) of one of the Wanderer's move keys.
func _is_move_press(event: InputEvent) -> bool:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		if event.is_action_pressed(action):
			return true
	return false

# The one gate: the first activation wins. The coin or the Glassbone
# taken reveals and grants what it held - with any Glassbone riding with
# it - and the reveal holds. LOOK INSIDE grants any Glassbone riding with
# the pack and opens it (_open_pack()); its own answer is _take_pick()'s.
func _activate(index: int) -> void:
	if _done:
		return
	if index == DISMISS:
		_done = true
		print("BelongingsScreen: walked on.")
		_log_choice(-1, 0, null)
		_finish(-1)
		return
	if not can_take(index):
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
		Slot.GLASSBONE:
			RunState.add_glassbone(_glassbone_offer)
			_log_choice(index, glassbone, null)
			TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, glassbone_volume_db, "GlassboneTakeAudio", "BelongingsScreen")
			print("BelongingsScreen: took %d Glassbone (run total %d)." % [_glassbone_offer, RunState.glassbone])
		Slot.CARD:
			print("BelongingsScreen: looked inside.")
			_open_pack()
			return
	_draw_layer.queue_redraw()
	var hold: Tween = create_tween()
	hold.tween_interval(maxf(result_hold_time, 0.0))
	hold.tween_callback(_end_hold)

# The choice, for the run log: what each column offered - the coin, the
# pack's cards, the Glassbone, and any Glassbone riding with one - which
# was taken (-1 walked on), the riding Glassbone that came with it, and,
# for the pack, the card taken from it (null for TAKE NOTHING).
func _log_choice(taken: int, glassbone_taken: int, card: CardData) -> void:
	var glassbone_slot: String = String(Slot.find_key(_glassbone_slot)).to_lower() if _glassbone_slot >= 0 else ""
	var shown: Array[String] = []
	for each in _cards:
		shown.append(each.card_name)
	var offered: Dictionary = {
		"gold": _gold if _has_slot(Slot.GOLD) else 0,
		"cards": shown,
		"glassbone": _glassbone_offer if _has_slot(Slot.GLASSBONE) else 0,
		"glassbone_rider": {"slot": RunLogger.or_null(glassbone_slot), "amount": maxi(_glassbone_amount, 0)},
	}
	var taken_name: String = String(Slot.find_key(taken)).to_lower() if taken >= 0 else ""
	RunLogger.event("belongings", {
		"offered": offered,
		"taken": RunLogger.or_null(taken_name),
		"card_taken": RunLogger.or_null(card.card_name if card != null else "") if taken == Slot.CARD else null,
		"glassbone_taken": glassbone_taken,
	})

# The hold is over: a taken card flies to the Belongings panel and the
# screen closes as it lands; anything else closes now.
func _end_hold() -> void:
	var view: CardView = _pick_views[0] if _taken == Slot.CARD and _picked >= 0 and not _pick_views.is_empty() and reveal_card_on_take else null
	if view == null:
		_finish(_taken)
		return
	_flying = true
	_pick_views.clear()
	view.set_keyword_inspect(false)
	_draw_layer.queue_redraw()
	var taken: int = _taken
	var tween: Tween = TakeFeedback.fly_to(self, view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(func() -> void:
		_finish(taken))

# One of the pack's cards at inspect size: not interactive anywhere on its
# face, and scaled about its top-left so TakeFeedback.fly_to()'s placement
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
