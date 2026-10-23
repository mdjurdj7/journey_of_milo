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
# Under the rule, TAKE ONE, in the system voice's tracked caps, the three
# as they were set down: the case, the pack and the shard of Glassbone,
# rendered from their models (see _build_render()), on one worn cloth
# with two stones holding it (the Scene group) - the cloth turned a
# little off the screen's square, each thing where it lies, at its own
# angle and tilt, seated on the cloth's own surface over a soft contact
# shadow. One fixed composition, the same every time. A soft band of the
# ink, feathered top and bottom, darkens the screen's full width behind
# the scene and behind WALK ON, over the scrim - the ground the labels
# read on. What each offers is fixed (Slot) and named under it in the
# choices' tracked caps - 45 GOLD (the cache's coin_amount), LOOK INSIDE,
# GLASSBONE ×1; which cards, stay a mystery until it's taken. Each thing
# is still a column of the choice: one with nothing to offer is not
# drawn and cannot be focused.
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
# hairline centred under it. Each object's hit area is its bounds on
# screen (item_rect()), its kind under them. The mouse focuses by
# hovering an object and takes by clicking it; ui_left/ui_right move
# across the columns, left to right (wrapping),
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
# The render layers: the ground under the objects, and the first
# object's - each object on its own, OBJECT_LAYER + its column.
const OBJECT_LAYER := 2
const GROUND_LAYER := 1
# The cameras stand this far from the scene, down the view.
const CAMERA_DISTANCE_M := 10.0
# The cloth's triangles are bucketed on a grid of this cell in its own
# space; an object rests on up to MODEL_POINTS of its vertices, those in
# the lowest SEAT_BAND of its height.
const CLOTH_GRID_M := 0.05
const MODEL_POINTS := 600
const SEAT_BAND := 0.35
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
# em): over the scene, its baseline at take_one_baseline_fraction of the
# viewport height; over the pack's cards, take_one_gap_px above them.
@export var take_one_text: String = "TAKE ONE":
	set(value):
		take_one_text = value
		_refresh()
@export_range(0.0, 1.0) var take_one_baseline_fraction: float = 0.289:
	set(value):
		take_one_baseline_fraction = value
		_render_objects()
@export var take_one_gap_px: float = 12.0:
	set(value):
		take_one_gap_px = value
		_refresh()
@export_group("")

@export_group("Items")
# The focused object's hairline: this far under its bounds on screen.
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
# Each object's kind under it, in the choices' tracked caps (choice_word_
# size_px): the coin's amount (the cache's coin_amount) in gold_kind_
# format, LOOK INSIDE, the Glassbone on offer in glassbone_kind_format -
# centred under the object, the baseline kind_label_gap_px under its
# bounds, so it follows the object wherever it lies. Grey at rest
# (unfocused_color), bone on focus; gone with the take.
@export var gold_kind_format: String = "%d GOLD":
	set(value):
		gold_kind_format = value
		_render_objects()
@export var card_kind_text: String = "LOOK INSIDE":
	set(value):
		card_kind_text = value
		_render_objects()
@export var glassbone_kind_format: String = "GLASSBONE ×%d":
	set(value):
		glassbone_kind_format = value
		_render_objects()
@export var kind_label_gap_px: float = 34.0:
	set(value):
		kind_label_gap_px = value
		_render_objects()
@export var choice_word_size_px: int = 17:
	set(value):
		choice_word_size_px = value
		_rebuild_fonts()
@export_group("")

@export_group("Band")
# Behind the scene - from band_pad_px over TAKE ONE's caps to band_pad_px
# under the lowest kind - and behind WALK ON: the ink at band_alpha across the
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
# What the taken column held, under its object in Alegreya Sans: the
# first baseline this far under the object's bounds, each line after one
# pitch further.
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
# The render: one world - the cloth and the three objects in it - each
# object drawn by a view of its own (_build_render()). The models keep
# their relative sizes at the cache's object_scales (the same as on the
# sand), times object_screen_scales, at scene_px_per_metre on screen.
# Each its own colour map times this tint - the cache's object_tint, which
# RegionField hands over, so the render matches the sand. A column with a
# material of its own (setup()) wears that, untinted.
@export var object_tint: Color = Color(0.76, 0.62, 0.46, 1.0):
	set(value):
		object_tint = value
		_render_objects()
# Looked down on at this pitch - lower than the field camera's 50 so the
# sides read.
@export var object_pitch_degrees: float = 35.0:
	set(value):
		object_pitch_degrees = value
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
# The scene renders at the window's stretch scale, so it draws 1:1 at any
# window size, re-rendered when the window changes - its longer side
# capped at this many pixels.
@export var render_max_px: int = 2048:
	set(value):
		render_max_px = value
		_render_objects()
@export_group("")

@export_group("Scene")
# The three are set down on one worn cloth - cloth_scene_path, its two
# stones part of it - on its own colour map (cloth_colour_path) under
# the painted shader the objects wear, times cloth_tint, lit as they are.
# Its base on the ground, scaled cloth_scale, turned cloth_yaw_degrees:
# its long side across the screen, a little off the square. The scene
# draws at scene_px_per_metre, centred across the screen, its top
# scene_top_gap_px under TAKE ONE.
@export_file("*.glb") var cloth_scene_path: String = "res://assets/models/props/belongings/belongings_cloth.glb":
	set(value):
		cloth_scene_path = value
		_rebuild_cloth()
@export_file("*.png") var cloth_colour_path: String = "res://assets/models/props/belongings/belongings_cloth_colour.png":
	set(value):
		cloth_colour_path = value
		_rebuild_cloth()
@export var cloth_tint: Color = Color.WHITE:
	set(value):
		cloth_tint = value
		if _cloth_material != null:
			BelongingsObject.set_material_tint(_cloth_material, cloth_tint)
		_render_objects()
@export var cloth_scale: float = 1.5:
	set(value):
		cloth_scale = value
		_render_objects()
@export var cloth_yaw_degrees: float = 102.0:
	set(value):
		cloth_yaw_degrees = value
		_render_objects()
@export var scene_px_per_metre: float = 380.0:
	set(value):
		scene_px_per_metre = value
		_render_objects()
@export var scene_top_gap_px: float = 28.0:
	set(value):
		scene_top_gap_px = value
		_render_objects()
# Each object where it was set down, column order (the case, the pack,
# the shard): its footprint's centre in metres from the cloth's centre
# (x across the screen, z toward the viewer), its yaw, and its tilt - x
# about the screen's horizontal (+ dips its near side), y its roll (+
# lifts its right side). The shard's tilt lays it flat, its thin side
# down. Each sits on the
# cloth's own surface where it lies (_seat()), whatever its tilt: its
# underside on the highest cloth under it, none in a crease, none sunk in
# the fold. Kept off the stones, and apart, by hand.
@export var item_offsets_m: PackedVector2Array = PackedVector2Array([Vector2(0.05, 0.52), Vector2(0.53, -0.31), Vector2(-0.47, -0.20)]):
	set(value):
		item_offsets_m = value
		_render_objects()
@export var object_yaws_degrees: PackedFloat32Array = PackedFloat32Array([16.0, -32.0, 70.0]):
	set(value):
		object_yaws_degrees = value
		_render_objects()
@export var item_tilts_degrees: PackedVector2Array = PackedVector2Array([Vector2(4.0, -3.0), Vector2(-6.0, 14.0), Vector2(86.0, 5.0)]):
	set(value):
		item_tilts_degrees = value
		_render_objects()
# Each object casts a soft contact shadow on the cloth: shadow_color,
# shadow_scale of its footprint, its edge fading from shadow_softness of
# the way out.
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

# The objects' world: its host renders nothing itself. Each object is
# drawn by a view of its own (column order, each seeing only its object's
# layer, OBJECT_LAYER + its column), the ground - the cloth, the shadows -
# by another, drawn first, under them.
var _viewport: SubViewport = null
var _object_viewports: Array[SubViewport] = []
var _object_cameras: Array[Camera3D] = []
var _ground_viewport: SubViewport = null
var _ground_camera: Camera3D = null
var _cloth: Node3D = null
var _cloth_material: ShaderMaterial = null
# The cloth's bbox and triangles in its own space, the triangles bucketed
# on an XZ grid of CLOTH_GRID_M cells - each cell the first vertex index
# of every triangle over it - for _cloth_height_at().
var _cloth_aabb: AABB = AABB()
var _cloth_faces: PackedVector3Array = PackedVector3Array()
var _cloth_grid: Dictionary[Vector2i, Array] = {}
var _shadows: Array[MeshInstance3D] = []
# The render's rect on screen, and its pixels per screen pixel.
var _render_rect: Rect2 = Rect2()
var _render_scale: float = 1.0
# Each object's bounds on screen - its hit area, its kind's base - column
# order; empty with no model.
var _item_rects: Array[Rect2] = [Rect2(), Rect2(), Rect2()]
# The overlaps the last layout warned of, so a live edit warns once.
var _warned_overlaps: String = ""
# Each column's lift now (focus_lift_px when focused), and its tween.
var _lift: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
var _lift_tweens: Array[Tween] = [null, null, null]
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
# Per column: the model's root (null if it didn't load), its bbox in its
# own space, and up to MODEL_POINTS of its vertices there - what _seat()
# rests on the cloth.
var _models: Array[Node3D] = []
var _model_aabbs: Array[AABB] = []
var _model_points: Array[PackedVector3Array] = []

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

# One world, its own, held by a host viewport that never renders: the
# three models in it, each on its own painted material - or the material
# its column names - and on its own layer, seen by its own SubViewport
# under its own orthographic camera; the ground pass's view of the same
# world, the cloth and the shadows; one directional light and a flat
# ambient. All the views alike (_render_objects()): one rect of the
# screen, one projection, each rendered once (and again when a render
# export changes) - so each object dims and lifts on its own wherever it
# lies, and the columns draw their own texture over the ground's.
func _build_render() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Objects"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i.ONE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	get_viewport().size_changed.connect(_render_objects)
	var world: World3D = _viewport.find_world_3d()

	for slot in SLOT_COUNT:
		var model: Node3D = null
		var material: Material = null
		var tinted: bool = false
		var aabb := AABB()
		var points := PackedVector3Array()
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
			var vertices := PackedVector3Array()
			for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
				var mi := mesh_instance as MeshInstance3D
				mi.material_override = material
				mi.layers = 1 << (OBJECT_LAYER + slot - 1)
				var to_model: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
				var mi_aabb: AABB = to_model * mi.get_aabb()
				aabb = mi_aabb if not has_aabb else aabb.merge(mi_aabb)
				has_aabb = true
				if mi.mesh != null:
					for vertex: Vector3 in mi.mesh.get_faces():
						vertices.append(to_model * vertex)
			var stride: int = maxi(ceili(float(vertices.size()) / float(MODEL_POINTS)), 1)
			for index in range(0, vertices.size(), stride):
				points.append(vertices[index])
		_models.append(model)
		_model_aabbs.append(aabb)
		_model_points.append(points)
		_materials.append(material)
		_tinted.append(tinted)
		if model == null:
			_drop_slot(slot)

		var view := SubViewport.new()
		view.name = "Object%d" % slot
		view.transparent_bg = true
		view.msaa_3d = Viewport.MSAA_4X
		view.size = Vector2i.ONE
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(view)
		view.world_3d = world
		var camera: Camera3D = _new_camera(OBJECT_LAYER + slot)
		view.add_child(camera)
		_object_viewports.append(view)
		_object_cameras.append(camera)

	_light = DirectionalLight3D.new()
	_viewport.add_child(_light)
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _environment
	_viewport.add_child(world_environment)
	_build_ground()
	_rebuild_cloth()

func _new_camera(layer_number: int) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = 1 << (layer_number - 1)
	return camera

# The ground pass: its own view of the objects' world, seeing only the
# ground layer - the cloth (_rebuild_cloth()) and a shadow under each
# object.
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

# The cloth, again: its model on the ground layer, on its painted colour
# map, its bbox and triangles taken in its own space and the triangles
# bucketed for _cloth_height_at(). Without it the objects lie on the bare
# ground (height 0).
func _rebuild_cloth() -> void:
	if _viewport == null:
		return
	if _cloth != null:
		_cloth.free()
		_cloth = null
	_cloth_material = null
	_cloth_aabb = AABB()
	_cloth_faces = PackedVector3Array()
	_cloth_grid.clear()
	var scene: PackedScene = load(cloth_scene_path) as PackedScene if ResourceLoader.exists(cloth_scene_path) else null
	if scene == null:
		push_warning("BelongingsScreen: could not load the cloth (%s); the objects lie on the bare ground." % cloth_scene_path)
		_render_objects()
		return
	_cloth = scene.instantiate() as Node3D
	_cloth.name = "Cloth"
	_viewport.add_child(_cloth)
	_cloth_material = PaintedProp.material(cloth_colour_path, cloth_tint)
	var has_aabb := false
	for mesh_instance in _cloth.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.layers = 1 << (GROUND_LAYER - 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _cloth_material != null:
			mi.material_override = _cloth_material
		var to_cloth: Transform3D = _cloth.global_transform.affine_inverse() * mi.global_transform
		var mi_aabb: AABB = to_cloth * mi.get_aabb()
		_cloth_aabb = mi_aabb if not has_aabb else _cloth_aabb.merge(mi_aabb)
		has_aabb = true
		if mi.mesh != null:
			for vertex: Vector3 in mi.mesh.get_faces():
				_cloth_faces.append(to_cloth * vertex)
	for start in range(0, _cloth_faces.size() - 2, 3):
		var a: Vector3 = _cloth_faces[start]
		var b: Vector3 = _cloth_faces[start + 1]
		var c: Vector3 = _cloth_faces[start + 2]
		var low := Vector2i(floori(minf(minf(a.x, b.x), c.x) / CLOTH_GRID_M), floori(minf(minf(a.z, b.z), c.z) / CLOTH_GRID_M))
		var high := Vector2i(floori(maxf(maxf(a.x, b.x), c.x) / CLOTH_GRID_M), floori(maxf(maxf(a.z, b.z), c.z) / CLOTH_GRID_M))
		for cell_x in range(low.x, high.x + 1):
			for cell_z in range(low.y, high.y + 1):
				var cell := Vector2i(cell_x, cell_z)
				if not _cloth_grid.has(cell):
					_cloth_grid[cell] = []
				_cloth_grid[cell].append(start)
	_render_objects()

# The cloth: its base on the ground, scaled cloth_scale, turned
# cloth_yaw_degrees about its centre.
func _cloth_transform() -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(cloth_yaw_degrees)) * Basis.from_scale(Vector3.ONE * maxf(cloth_scale, 0.01))
	var centre := Vector3(_cloth_aabb.get_center().x, _cloth_aabb.position.y, _cloth_aabb.get_center().z)
	return Transform3D(basis, -(basis * centre))

# The cloth's top at the world's (x, z) - the highest of its faces over
# that point - or the ground's 0 off it.
func _cloth_height_at(x: float, z: float) -> float:
	if _cloth == null or _cloth_faces.is_empty():
		return 0.0
	var local: Vector3 = _cloth.transform.affine_inverse() * Vector3(x, 0.0, z)
	var point := Vector2(local.x, local.z)
	var starts: Array = _cloth_grid.get(Vector2i(floori(local.x / CLOTH_GRID_M), floori(local.z / CLOTH_GRID_M)), [])
	var found := false
	var top: float = 0.0
	for start: int in starts:
		var a: Vector3 = _cloth_faces[start]
		var b: Vector3 = _cloth_faces[start + 1]
		var c: Vector3 = _cloth_faces[start + 2]
		var weights: Vector3 = _barycentric(point, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
		if weights.x < 0.0 or weights.y < 0.0 or weights.z < 0.0:
			continue
		var y: float = a.y * weights.x + b.y * weights.y + c.y * weights.z
		top = y if not found else maxf(top, y)
		found = true
	if not found:
		return 0.0
	return maxf((_cloth.transform * Vector3(local.x, top, local.z)).y, 0.0)

# `point`'s weights over the triangle (a, b, c); any negative outside it.
static func _barycentric(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var d: float = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-12:
		return Vector3(-1.0, -1.0, -1.0)
	var u: float = ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / d
	var v: float = ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / d
	return Vector3(u, v, 1.0 - u - v)

# An object turned as it lies: its roll, then its tilt, then its yaw, at
# its scale.
func _item_basis(slot: int) -> Basis:
	var yaw: float = deg_to_rad(object_yaws_degrees[slot]) if slot < object_yaws_degrees.size() else 0.0
	var tilt: Vector2 = item_tilts_degrees[slot] if slot < item_tilts_degrees.size() else Vector2.ZERO
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(tilt.x)) * Basis(Vector3.BACK, deg_to_rad(tilt.y)) * Basis.from_scale(Vector3.ONE * _scale_of(slot))

# An object where it lies: its footprint centred on its offset, then
# set down until its low points (the lowest SEAT_BAND of its height) meet
# the cloth's top where they stand, none under it - so it rests on the
# highest cloth under it, in no crease, not sunk in the fold, not afloat.
func _seat(slot: int) -> Transform3D:
	var basis: Basis = _item_basis(slot)
	var at: Vector2 = item_offsets_m[slot] if slot < item_offsets_m.size() else Vector2.ZERO
	var placed: AABB = Transform3D(basis, Vector3.ZERO) * _model_aabbs[slot]
	var origin := Vector3(at.x - placed.get_center().x, -placed.position.y, at.y - placed.get_center().z)
	var band: float = placed.size.y * SEAT_BAND
	var raise: float = 0.0
	var touched := false
	var points: PackedVector3Array = _model_points[slot] if slot < _model_points.size() else PackedVector3Array()
	for point: Vector3 in points:
		var p: Vector3 = basis * point + origin
		if p.y > band:
			continue
		var need: float = _cloth_height_at(p.x, p.z) - p.y
		raise = need if not touched else maxf(raise, need)
		touched = true
	return Transform3D(basis, origin + Vector3(0.0, raise, 0.0))

# An object's box in the world as it lies: its vertices' (MODEL_POINTS of
# them), tighter than its turned bbox; the bbox without them.
func _seated_box(slot: int, seated: Transform3D) -> AABB:
	var points: PackedVector3Array = _model_points[slot] if slot < _model_points.size() else PackedVector3Array()
	if points.is_empty():
		return seated * _model_aabbs[slot]
	var box := AABB(seated * points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(seated * point)
	return box

# A column with no model is a column with nothing to take.
func _drop_slot(slot: int) -> void:
	match slot:
		Slot.GOLD:
			_gold = 0
		Slot.CARD:
			_cards.clear()
		Slot.GLASSBONE:
			_glassbone_offer = 0

# The scene laid out and rendered: the cloth and each object placed,
# every view framing the same rect of the screen - the scene's bounds,
# centred across it, its top scene_top_gap_px under TAKE ONE, room left
# over each object for its lift - at scene_px_per_metre.
func _render_objects() -> void:
	if _viewport == null or _ground_camera == null or _draw_layer == null or _object_cameras.size() < SLOT_COUNT:
		return
	for slot in _materials.size():
		if _tinted[slot]:
			BelongingsObject.set_material_tint(_materials[slot], object_tint)
	var px_per_m: float = maxf(scene_px_per_metre, 1.0)
	var pitch: float = deg_to_rad(object_pitch_degrees)
	if _cloth != null:
		_cloth.transform = _cloth_transform()
	# The bounds in screen pixels from the cloth's centre on the ground.
	var bounds := Rect2()
	var has_bounds := false
	if _cloth != null and _cloth_aabb.has_volume():
		bounds = _screen_bounds(_cloth.transform * _cloth_aabb, pitch, px_per_m)
		has_bounds = true
	var item_bounds: Array[Rect2] = [Rect2(), Rect2(), Rect2()]
	for slot in _models.size():
		var model: Node3D = _models[slot]
		var shadow: MeshInstance3D = _shadows[slot] if slot < _shadows.size() else null
		if model == null:
			if shadow != null:
				shadow.visible = false
			continue
		model.transform = _seat(slot)
		var world_aabb: AABB = _seated_box(slot, model.transform)
		item_bounds[slot] = _screen_bounds(world_aabb, pitch, px_per_m)
		var lifted: Rect2 = item_bounds[slot].grow_side(SIDE_TOP, maxf(focus_lift_px, 0.0))
		bounds = lifted if not has_bounds else bounds.merge(lifted)
		has_bounds = true
		if shadow != null:
			var yaw: float = deg_to_rad(object_yaws_degrees[slot]) if slot < object_yaws_degrees.size() else 0.0
			# Its footprint in its own yawed frame: tilted, but not turned.
			var footprint: AABB = Transform3D(Basis(Vector3.UP, -yaw) * _item_basis(slot), Vector3.ZERO) * _model_aabbs[slot]
			var centre: Vector3 = world_aabb.get_center()
			shadow.visible = true
			shadow.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(footprint.size.x, 1.0, footprint.size.z) * shadow_scale), Vector3(centre.x, _cloth_height_at(centre.x, centre.z) + 0.004, centre.z))
			var shadow_material := shadow.material_override as StandardMaterial3D
			shadow_material.albedo_color = shadow_color
			var soft := shadow_material.albedo_texture as GradientTexture2D
			soft.gradient.offsets = PackedFloat32Array([clampf(1.0 - shadow_softness, 0.0, 0.99), 1.0])
			soft.gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	# The cloth's centre on screen: centred across, the scene's top under
	# TAKE ONE.
	var origin := Vector2(_draw_layer.size.x / 2.0, _take_one_baseline() + scene_top_gap_px - bounds.position.y)
	for slot in SLOT_COUNT:
		_item_rects[slot] = Rect2(item_bounds[slot].position + origin, item_bounds[slot].size) if _models[slot] != null else Rect2()
	var pad: float = 8.0
	_render_rect = Rect2(bounds.position + origin, bounds.size).grow(pad)
	# Rendered in whole pixels at the window's scale: the rect takes the
	# size those pixels cover, so the cameras map to it exactly.
	_render_scale = _render_pixel_scale(_render_rect.size)
	var pixels := Vector2i(maxi(ceili(_render_rect.size.x * _render_scale), 1), maxi(ceili(_render_rect.size.y * _render_scale), 1))
	_render_rect.size = Vector2(pixels) / _render_scale
	var cameras: Array[Camera3D] = [_ground_camera]
	cameras.append_array(_object_cameras)
	for camera in cameras:
		camera.size = _render_rect.size.y / px_per_m
		camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * CAMERA_DISTANCE_M
		camera.look_at(Vector3.ZERO, Vector3.UP)
		camera.h_offset = (_render_rect.get_center().x - origin.x) / px_per_m
		camera.v_offset = (origin.y - _render_rect.get_center().y) / px_per_m
	if _field_lit:
		_light.light_color = _field_light_color
		_light.light_energy = _field_light_energy
		var up: Vector3 = Vector3.UP if absf(_field_light_direction.normalized().y) < 0.99 else Vector3.FORWARD
		_light.look_at_from_position(Vector3.ZERO, _field_light_direction, up)
		_light.shadow_enabled = true
		_light.shadow_opacity = _field_shadow_opacity
		_light.directional_shadow_max_distance = CAMERA_DISTANCE_M * 2.0
		_environment.ambient_light_color = _field_ambient_color
		_environment.ambient_light_energy = _field_ambient_energy
		_environment.tonemap_mode = _field_tonemap_mode
		_environment.tonemap_exposure = _field_tonemap_exposure
	else:
		_light.light_energy = light_energy
		_light.rotation = Vector3(deg_to_rad(light_pitch_degrees), deg_to_rad(light_yaw_degrees), 0.0)
		_environment.ambient_light_energy = ambient_energy
	var views: Array[SubViewport] = [_ground_viewport]
	views.append_array(_object_viewports)
	for view in views:
		view.size = pixels
		view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_warn_overlaps()
	_refresh()

# A world box on screen, in pixels from the cloth's centre on the ground:
# the orthographic view down `pitch`.
static func _screen_bounds(box: AABB, pitch: float, px_per_m: float) -> Rect2:
	var rect := Rect2()
	for corner in 8:
		var p: Vector3 = box.get_endpoint(corner)
		var on_screen := Vector2(p.x, -(p.y * cos(pitch) - p.z * sin(pitch))) * px_per_m
		rect = Rect2(on_screen, Vector2.ZERO) if corner == 0 else rect.expand(on_screen)
	return rect

# What a layout leaves overlapping - an object's bounds and another's, a
# kind and any object's bounds or another kind - warned of once.
func _warn_overlaps() -> void:
	var boxes: Array[Rect2] = []
	var names: Array[String] = []
	for slot in _present_slots():
		boxes.append(_item_rects[slot])
		names.append("%s's object" % String(Slot.find_key(slot)).to_lower())
		boxes.append(_kind_rect(slot))
		names.append("%s's kind" % String(Slot.find_key(slot)).to_lower())
	var found: PackedStringArray = PackedStringArray()
	for i in boxes.size():
		for j in range(i + 1, boxes.size()):
			# An object's own kind sits under it by design.
			if j == i + 1 and i % 2 == 0:
				continue
			if boxes[i].intersects(boxes[j]):
				found.append("%s / %s" % [names[i], names[j]])
	var text: String = ", ".join(found)
	if text != _warned_overlaps and not text.is_empty():
		push_warning("BelongingsScreen: the scene overlaps - %s." % text)
	_warned_overlaps = text

func _scale_of(slot: int) -> float:
	var on_sand: float = _object_scales[slot] if slot < _object_scales.size() else 1.0
	return on_sand * (object_screen_scales[slot] if slot < object_screen_scales.size() else 1.0)

# The render's pixels per screen pixel: the window's stretch scale, the
# longer side capped at render_max_px.
func _render_pixel_scale(rect_size: Vector2) -> float:
	var stretch: float = get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	var longest: float = maxf(maxf(rect_size.x, rect_size.y), 1.0)
	return maxf(minf(stretch, float(maxi(render_max_px, 1)) / longest), 0.01)

# --- Layout ---

# For probes: an object's bounds on screen - its hit area; empty when its
# column is left out.
func item_rect(slot: int) -> Rect2:
	return _item_rects[slot] if slot >= 0 and slot < _item_rects.size() else Rect2()

# An object's kind under it: the box its caps take, centred under its
# bounds.
func _kind_rect(slot: int) -> Rect2:
	var width: float = InkType.width(_choice_font, kind_text(slot), choice_word_size_px) if _choice_font != null else 0.0
	var baseline: float = _kind_baseline(slot)
	return Rect2(item_rect(slot).get_center().x - width / 2.0, baseline - float(choice_word_size_px) * 0.75, width, float(choice_word_size_px))

# The columns drawn back to front: the far ones first.
func _draw_order() -> Array[int]:
	var order: Array[int] = _present_slots()
	order.sort_custom(func(a: int, b: int) -> bool: return _item_depth(a) < _item_depth(b))
	return order

func _item_depth(slot: int) -> float:
	return item_offsets_m[slot].y if slot < item_offsets_m.size() else 0.0

# TAKE ONE's baseline, over the scene - the pack's cards' while they're
# up.
func _take_one_baseline() -> float:
	if _picking:
		return roundf(_pick_row().position.y - take_one_gap_px)
	return roundf(_draw_layer.size.y * take_one_baseline_fraction)

# An object's kind: its baseline under the object's bounds.
func _kind_baseline(slot: int) -> float:
	return roundf(item_rect(slot).end.y + kind_label_gap_px)

# The lowest kind's baseline - the scene band's foot.
func _lowest_kind_baseline() -> float:
	var lowest: float = _take_one_baseline()
	for slot in _present_slots():
		lowest = maxf(lowest, _kind_baseline(slot))
	return lowest

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

	# The ground first, whole; then each object, back to front, its own
	# render over the same rect - drawn down at rest, lifted when focused.
	var ground: Texture2D = _ground_viewport.get_texture() if _ground_viewport != null else null
	if ground != null:
		_draw_layer.draw_texture_rect(ground, _render_rect, false)
	for slot in _draw_order():
		var rect: Rect2 = item_rect(slot)
		var lit: bool = _is_lit(slot)
		var tint: Color = rest_modulate
		if lit:
			tint = Color.WHITE
		elif _taken >= 0:
			tint = dimmed_modulate
		var texture: Texture2D = _object_viewports[slot].get_texture() if slot < _object_viewports.size() else null
		if texture != null:
			var lift: float = _lift[slot] if slot < _lift.size() else 0.0
			_draw_layer.draw_texture_rect(texture, Rect2(_render_rect.position - Vector2(0.0, lift), _render_rect.size), false, tint)
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

# The bands: behind the scene, solid from over TAKE ONE's caps to under
# the lowest kind, and behind WALK ON until the take - feathered to nothing above and
# below, the full width.
func _draw_band() -> void:
	if band_alpha <= 0.0:
		return
	_draw_band_over(_take_one_baseline() - float(label_size_px) * 0.72 - band_pad_px, _lowest_kind_baseline() + band_pad_px)
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
	var rect: Rect2 = item_rect(slot)
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

# The frontmost object under `position`, else WALK ON.
func _hit(position: Vector2) -> int:
	var order: Array[int] = _draw_order()
	order.reverse()
	for slot in order:
		if can_take(slot) and item_rect(slot).has_point(position):
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
