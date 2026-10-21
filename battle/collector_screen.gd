extends CanvasLayer
class_name CollectorScreen

# What the collector has, set out as a ledger over the field. Opened by
# RegionField.open_collector_screen() on the collector's open_requested:
# the field goes DISABLED under it (the Wanderer locked, the camera held)
# and this layer runs ALWAYS on layer 100. No box, no panel, no button
# chrome, no glow - ink on the world, the cards bone, hairlines.
#
# The field stays in view under a veil of the fog's own colour (RegionSky.
# fog_color), paler rather than darker and strongest on the right where
# the ledger sits, so the ink reads. The camera eases sideways (Camera3D.
# h_offset - the rig never writes it) until the collector stands at
# camera_target_fraction of the width, and eases back on close.
#
# By the collector, on the left, the world voice in Spectral Italic,
# following its body on screen as the camera eases: open_line and, greyer,
# second_line; after a purchase, purchase_line alone for purchase_line_
# seconds.
#
# The ledger, in a right-hand column (column_left_fraction to column_
# right_margin_fraction):
#   GOLD and the run's gold, top right.
#   CARDS, a caps label over a hairline: the rolled stock (Collector.
#     get_stock()) and its fixed card (Samphire) a little apart at the
#     row's end, at card_scale; under each, "HAVE N" small and grey when
#     the deck holds the card, then its price in Spectral SemiBold. A card
#     clicked opens at inspect_card_scale with TAKE FOR <price> and BACK.
#     A bought card's slot stays empty - the row never shifts.
#   EQUIPMENT, the same: one line per stocked good (Collector.get_goods())
#     - its art, its name, a caps type line under it (the kind, then MAX
#     HP a → b if taking it changes max HP, else REPLACES <name> if its
#     slot is filled), its price, CHOOSE. CHOOSE opens its ItemPlate over
#     the screen (ArmorExamine) - REPLACES and the Max HP line on the
#     plate, TAKE FOR <price> and BACK. A good taken is equipped at once,
#     whatever it replaces gone (the collector keeps it), and its line
#     leaves the list. Then the removal line: "Remove a card", OPENS YOUR
#     DECK, its price, CHOOSE - the deck as a picker (DeckView pick
#     confirm): a card lifted shows GIVE IT <NAME> with the price, DECK
#     n → n-1 and BACK; given, exactly that card leaves and the line goes.
#     Once per collector (Collector.is_removal_used()), and only while it
#     can be paid for and the deck holds a card - else its CHOOSE is grey
#     and inert.
#   LEAVE, bottom right. Escape and a right click close it too.
# A group with nothing stocked is hidden.
#
# A price the run can't pay is grey. CHOOSE and a card's click still open
# the plate or the card to look at, with TAKE grey and inert; no red, no
# shake. Every purchase and removal is logged (RunLogger) with the item's
# id, kind, price and gold before and after.
#
# Focus is the title menu's: the focused card or line is full ink with a
# short hairline to its left, the rest grey. The mouse focuses by hovering
# and acts by clicking; ui_left/ui_right move along the card row, ui_down
# drops to the equipment lines and then LEAVE, ui_up climbs back,
# ui_accept acts. Nothing is focused until the mouse or a key says so.
#
# Ink is the shared theme's Battle ink (ui/battle_theme.tres) - on a pale
# veil, the dark element; grey and inert are that ink at unfocused_alpha
# and inert_alpha. Every size is authored at reference_height and scaled
# by the window's own.

signal closed()

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"
const THEME_PATH := "res://ui/battle_theme.tres"
const VOICE_FONT_PATH := "res://assets/fonts/Spectral-Italic.ttf"

enum Kind { WORN, KEEPSAKE, WEAPON, REMOVAL }

@export_group("Veil")
# The fog's colour from the left edge (veil_left_alpha) to the right
# (veil_right_alpha), the ramp between veil_ramp_start_fraction and
# veil_ramp_end_fraction of the width; veil_fallback_color with no sky.
@export_range(0.0, 1.0) var veil_left_alpha: float = 0.12:
	set(value):
		veil_left_alpha = value
		_apply_veil()
@export_range(0.0, 1.0) var veil_right_alpha: float = 0.74:
	set(value):
		veil_right_alpha = value
		_apply_veil()
@export_range(0.0, 1.0) var veil_ramp_start_fraction: float = 0.22:
	set(value):
		veil_ramp_start_fraction = value
		_apply_veil()
@export_range(0.0, 1.0) var veil_ramp_end_fraction: float = 0.5:
	set(value):
		veil_ramp_end_fraction = value
		_apply_veil()
@export var veil_fallback_color: Color = Color(0.86, 0.85, 0.82, 1.0):
	set(value):
		veil_fallback_color = value
		_apply_veil()
@export_group("")

@export_group("Ink")
@export_range(0.0, 1.0) var unfocused_alpha: float = 0.55:
	set(value):
		unfocused_alpha = value
		_refresh()
@export_range(0.0, 1.0) var inert_alpha: float = 0.3:
	set(value):
		inert_alpha = value
		_refresh()
# The headings' hairlines, and the fainter one under each line.
@export_range(0.0, 1.0) var rule_alpha: float = 0.35:
	set(value):
		rule_alpha = value
		_refresh()
@export_range(0.0, 1.0) var line_rule_alpha: float = 0.18:
	set(value):
		line_rule_alpha = value
		_refresh()
# A line's art at rest; full when focused.
@export_range(0.0, 1.0) var art_unfocused_alpha: float = 0.8:
	set(value):
		art_unfocused_alpha = value
		_refresh()
@export var rule_thickness_px: float = 1.0:
	set(value):
		rule_thickness_px = value
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

@export_group("Camera")
# Where the collector's body settles across the width while the screen is
# open; the offset never passes camera_offset_max_m either way.
@export_range(0.0, 1.0) var camera_target_fraction: float = 0.2:
	set(value):
		camera_target_fraction = value
		if is_node_ready() and not _closing:
			_ease_camera(_wanted_camera_offset())
@export var camera_offset_max_m: float = 3.0:
	set(value):
		camera_offset_max_m = value
		if is_node_ready() and not _closing:
			_ease_camera(_wanted_camera_offset())
@export var camera_ease_seconds: float = 0.45
@export_group("")

@export_group("Voice")
@export var open_line: String = "It has sorted what it has.":
	set(value):
		open_line = value
		_refresh()
@export var second_line: String = "It does not look up.":
	set(value):
		second_line = value
		_refresh()
@export var purchase_line: String = "It takes the coin before you let go.":
	set(value):
		purchase_line = value
		_refresh()
# The removal picker's heading (DeckView.header_voice).
@export var removal_header_text: String = "It will not give it back."
@export var purchase_line_seconds: float = 3.5
@export var voice_size_px: int = 26:
	set(value):
		voice_size_px = value
		_relayout()
@export_range(0.0, 1.0) var second_line_alpha: float = 0.55:
	set(value):
		second_line_alpha = value
		_refresh()
@export var voice_line_gap_px: float = 8.0:
	set(value):
		voice_line_gap_px = value
		_refresh()
# Above the top of the body's box on screen.
@export var voice_clearance_px: float = 28.0:
	set(value):
		voice_clearance_px = value
		_refresh()
# Kept this far inside the screen's left edge and the column's.
@export var voice_margin_px: float = 32.0:
	set(value):
		voice_margin_px = value
		_refresh()
@export_group("")

@export_group("Column")
@export var reference_height: float = 1080.0:
	set(value):
		reference_height = value
		_relayout()
@export_range(0.0, 1.0) var column_left_fraction: float = 0.43:
	set(value):
		column_left_fraction = value
		_relayout()
@export_range(0.0, 0.5) var column_right_margin_fraction: float = 0.05:
	set(value):
		column_right_margin_fraction = value
		_relayout()
# GOLD's baseline, from the top.
@export var top_margin_px: float = 64.0:
	set(value):
		top_margin_px = value
		_refresh()
@export var gold_text: String = "GOLD":
	set(value):
		gold_text = value
		_refresh()
@export var gold_size_px: int = 26:
	set(value):
		gold_size_px = value
		_relayout()
@export var gold_gap_px: float = 14.0:
	set(value):
		gold_gap_px = value
		_refresh()
# The caps: GOLD, the headings, CHOOSE, LEAVE, TAKE FOR, BACK.
@export var label_size_px: int = 16:
	set(value):
		label_size_px = value
		_relayout()
@export_range(0.0, 1.0) var label_tracking_em: float = 0.16:
	set(value):
		label_tracking_em = value
		_relayout()
@export var cards_heading_text: String = "CARDS":
	set(value):
		cards_heading_text = value
		_refresh()
@export var equipment_heading_text: String = "EQUIPMENT":
	set(value):
		equipment_heading_text = value
		_refresh()
# The first heading's baseline, from the top.
@export var first_heading_px: float = 150.0:
	set(value):
		first_heading_px = value
		_relayout()
@export var heading_rule_gap_px: float = 10.0:
	set(value):
		heading_rule_gap_px = value
		_relayout()
@export var heading_content_gap_px: float = 22.0:
	set(value):
		heading_content_gap_px = value
		_relayout()
# From the cards' price baseline to the next heading's baseline.
@export var group_gap_px: float = 64.0:
	set(value):
		group_gap_px = value
		_relayout()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_refresh()
# LEAVE's baseline, from the bottom.
@export var leave_bottom_px: float = 64.0:
	set(value):
		leave_bottom_px = value
		_refresh()
@export_group("")

@export_group("Cards")
@export var card_scale: float = 0.75:
	set(value):
		card_scale = value
		_relayout()
# Between two cards, as a fraction of a card's width.
@export var card_gap_fraction: float = 0.12:
	set(value):
		card_gap_fraction = value
		_relayout()
# The extra room before the fixed card, as a fraction of a card's width.
@export var fixed_gap_fraction: float = 0.25:
	set(value):
		fixed_gap_fraction = value
		_relayout()
# A card the deck already holds: "HAVE N" in small grey caps over its
# price - a tempered copy counted as the card. Nothing at 0.
@export var have_format: String = "HAVE %d":
	set(value):
		have_format = value
		_refresh()
@export var have_size_px: int = 11:
	set(value):
		have_size_px = value
		_relayout()
@export var have_gap_px: float = 10.0:
	set(value):
		have_gap_px = value
		_relayout()
@export var price_size_px: int = 24:
	set(value):
		price_size_px = value
		_relayout()
@export var price_gap_px: float = 8.0:
	set(value):
		price_gap_px = value
		_relayout()
@export_group("")

@export_group("Equipment")
@export var line_height_px: float = 66.0:
	set(value):
		line_height_px = value
		_relayout()
@export var item_size_px: int = 24:
	set(value):
		item_size_px = value
		_relayout()
@export var type_size_px: int = 12:
	set(value):
		type_size_px = value
		_relayout()
@export var type_gap_px: float = 6.0:
	set(value):
		type_gap_px = value
		_relayout()
@export var icon_size_px: float = 40.0:
	set(value):
		icon_size_px = value
		_relayout()
@export var icon_gap_px: float = 14.0:
	set(value):
		icon_gap_px = value
		_relayout()
# From the price's right edge to CHOOSE.
@export var price_column_gap_px: float = 36.0:
	set(value):
		price_column_gap_px = value
		_refresh()
@export var choose_text: String = "CHOOSE":
	set(value):
		choose_text = value
		_refresh()
@export var worn_kind_text: String = "WORN":
	set(value):
		worn_kind_text = value
		_refresh()
@export var keepsake_kind_text: String = "KEEPSAKE":
	set(value):
		keepsake_kind_text = value
		_refresh()
@export var weapon_kind_text: String = "WEAPON":
	set(value):
		weapon_kind_text = value
		_refresh()
@export var max_hp_format: String = "MAX HP %d → %d":
	set(value):
		max_hp_format = value
		_refresh()
@export var replaces_format: String = "REPLACES %s":
	set(value):
		replaces_format = value
		_refresh()
@export var type_separator: String = " · ":
	set(value):
		type_separator = value
		_refresh()
@export var removal_name: String = "Remove a card":
	set(value):
		removal_name = value
		_refresh()
@export var removal_type_text: String = "OPENS YOUR DECK":
	set(value):
		removal_type_text = value
		_refresh()
# The picker's footer (DeckView pick confirm): the name goes in the %s,
# the deck's count and one fewer in the %d's.
@export var removal_confirm_format: String = "GIVE IT %s"
@export var removal_detail_format: String = "DECK %d → %d"
@export_group("")

@export_group("Take")
@export var take_format: String = "TAKE FOR %d":
	set(value):
		take_format = value
		_refresh_inspect()
@export var back_text: String = "BACK":
	set(value):
		back_text = value
		_refresh_inspect()
# A card looked at: the fog's veil deepened to this, the card at
# inspect_card_scale centred on the column, its centre at inspect_centre_
# fraction of the height, TAKE FOR and BACK under it.
@export_range(0.0, 1.0) var inspect_veil_alpha: float = 0.6:
	set(value):
		inspect_veil_alpha = value
		_apply_veil()
@export var inspect_card_scale: float = 1.0:
	set(value):
		inspect_card_scale = value
		_relayout_inspect()
@export_range(0.0, 1.0) var inspect_centre_fraction: float = 0.42:
	set(value):
		inspect_centre_fraction = value
		_relayout_inspect()
@export var inspect_actions_gap_px: float = 36.0:
	set(value):
		inspect_actions_gap_px = value
		_refresh_inspect()
@export var inspect_line_gap_px: float = 16.0:
	set(value):
		inspect_line_gap_px = value
		_refresh_inspect()
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
# The plate's and the picker's layer, over this one.
@export var offer_layer_offset: int = 1
@export_group("")

var _collector: Collector = null
var _deck_panel: Control = null
var _veil: TextureRect = null
var _gradient: Gradient = null
var _draw_layer: Control = null
var _inspect_layer: Control = null
var _inspect_veil: ColorRect = null
var _ink: Color = Color(0.165, 0.165, 0.18, 1.0)
var _fog: Color = Color(0.86, 0.85, 0.82, 1.0)
# Held, as every drawn face is: a font loaded and dropped in a draw
# callback is freed with its glyphs as the callback returns.
var _numeral_font: Font = null
var _label_font: Font = null
var _have_font: Font = null
var _type_font: Font = null
var _voice_font: Font = null
var _fit: float = 1.0
var _row_fit: float = 1.0
# Fitted sizes.
var _label_px: int = 16
var _gold_px: int = 26
var _price_px: int = 24
var _have_px: int = 11
var _item_px: int = 24
var _type_px: int = 12
var _voice_px: int = 26
# One per slot: the rolled stock, then the fixed card - null once bought
# (or a slot that rolled nothing). _views alongside.
var _cards: Array[CardData] = []
var _views: Array[CardView] = []
# The equipment list as it stands: each line {kind, good_index, good}.
var _lines: Array[Dictionary] = []
# Focus: a card slot, then the lines, then LEAVE; -1 = nothing.
var _focus: int = -1
var _mouse_on: int = -1
var _offer: ArmorExamine = null
var _offer_line: Dictionary = {}
var _picker: DeckView = null
# A card looked at: its slot, its own CardView at inspect size, which of
# TAKE (0) and BACK (1) has focus.
var _inspect_slot: int = -1
var _inspect_view: CardView = null
var _inspect_focus: int = -1
var _purchase_left: float = 0.0
var _voice_anchor: Vector2 = Vector2(-1.0, -1.0)
var _camera: Camera3D = null
var _camera_rest_offset: float = 0.0
var _camera_tween: Tween = null
var _closing: bool = false

# Called by RegionField before the screen enters the tree.
func setup(collector: Collector, deck_panel: Control) -> void:
	_collector = collector
	_deck_panel = deck_panel

func _ready() -> void:
	# The field is frozen under this (RegionField.open_collector_screen());
	# this layer opts out of the freeze or would stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	var theme := load(THEME_PATH) as Theme
	if theme != null and theme.has_color(&"ink", &"Battle"):
		_ink = theme.get_color(&"ink", &"Battle")
	_fog = veil_fallback_color
	var region_field: RegionField = _region_field()
	var sky: RegionSky = region_field.get_region_sky() if region_field != null else null
	if sky != null:
		_fog = sky.fog_color
	_voice_font = load(VOICE_FONT_PATH) as Font

	_gradient = Gradient.new()
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = _gradient
	gradient_texture.width = 256
	gradient_texture.height = 4
	gradient_texture.fill_from = Vector2(0.0, 0.5)
	gradient_texture.fill_to = Vector2(1.0, 0.5)
	_veil = TextureRect.new()
	_veil.name = "Veil"
	_veil.texture = gradient_texture
	_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field and order the Wanderer off.
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_veil)

	_draw_layer = Control.new()
	_draw_layer.name = "Ledger"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_screen)
	_draw_layer.resized.connect(_relayout)
	add_child(_draw_layer)

	_inspect_layer = Control.new()
	_inspect_layer.name = "Inspect"
	_inspect_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_layer.visible = false
	add_child(_inspect_layer)
	_inspect_veil = ColorRect.new()
	_inspect_veil.name = "InspectVeil"
	_inspect_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspect_veil.gui_input.connect(_on_inspect_gui_input)
	_inspect_veil.draw.connect(_draw_inspect)
	_inspect_layer.add_child(_inspect_veil)
	_apply_veil()

	if _collector != null:
		_collector.ensure_stock()
		_collector.prices_changed.connect(_on_prices_changed)
		for card in _collector.get_stock():
			_cards.append(card)
		if _collector.fixed_card != null:
			_cards.append(_collector.fixed_card if _collector.is_fixed_available() else null)
	_build_views()
	_build_lines()
	_relayout()
	_start_camera()

func _exit_tree() -> void:
	if _collector != null and is_instance_valid(_collector) and _collector.prices_changed.is_connected(_on_prices_changed):
		_collector.prices_changed.disconnect(_on_prices_changed)
	if _picker != null and is_instance_valid(_picker):
		_picker.close()

func _process(delta: float) -> void:
	if _purchase_left > 0.0:
		_purchase_left -= delta
		if _purchase_left <= 0.0:
			_refresh()
	# The voice follows the body while the camera eases.
	var anchor: Vector2 = _body_anchor()
	if anchor.distance_to(_voice_anchor) > 0.5:
		_voice_anchor = anchor
		_refresh()

func _region_field() -> RegionField:
	if _collector == null:
		return null
	return _collector.get_node_or_null(_collector.region_field_path) as RegionField

# --- Stock ---

func _fixed_slot() -> int:
	if _collector == null or _collector.fixed_card == null:
		return -1
	return _cards.size() - 1

func _price_at(slot: int) -> int:
	if _collector == null or slot < 0 or slot >= _cards.size() or _cards[slot] == null:
		return 0
	if slot == _fixed_slot():
		return _collector.fixed_price
	return _collector.price_of(_cards[slot])

func _affordable(slot: int) -> bool:
	return slot >= 0 and slot < _cards.size() and _cards[slot] != null and RunState.gold >= _price_at(slot)

# The goods still on offer, then the removal until it is used. A good the
# run already holds (its weapon, its worn piece, its keepsake) isn't
# listed.
func _build_lines() -> void:
	_lines.clear()
	if _collector == null:
		return
	var goods: Array[CollectorGood] = _collector.get_goods()
	for index in goods.size():
		var good: CollectorGood = goods[index]
		if good == null:
			continue
		var kind: int = _kind_of(good)
		if _held(good, kind):
			continue
		_lines.append({"kind": kind, "good_index": index, "good": good})
	if not _collector.is_removal_used():
		_lines.append({"kind": Kind.REMOVAL, "good_index": -1, "good": null})

func _kind_of(good: CollectorGood) -> int:
	if good.get_weapon() != null:
		return Kind.WEAPON
	return Kind.WORN if good.get_trinket().slot == TrinketData.Slot.WORN else Kind.KEEPSAKE

func _held(good: CollectorGood, kind: int) -> bool:
	match kind:
		Kind.WEAPON:
			return good.get_weapon() == RunState.weapon
		Kind.WORN:
			return good.get_trinket() == RunState.worn
	return good.get_trinket() == RunState.keepsake

# The removal can be chosen while it is unused, can be paid for and the
# deck holds a card.
func _removal_open() -> bool:
	return _collector != null and not _collector.is_removal_used() and RunState.gold >= _collector.removal_price and not RunState.deck.is_empty()

func _line_price(line: Dictionary) -> int:
	if int(line["kind"]) == Kind.REMOVAL:
		return _collector.removal_price if _collector != null else 0
	return (line["good"] as CollectorGood).price

func _line_affordable(line: Dictionary) -> bool:
	if int(line["kind"]) == Kind.REMOVAL:
		return _removal_open()
	return RunState.gold >= _line_price(line)

func _line_name(line: Dictionary) -> String:
	var good: CollectorGood = line["good"]
	match int(line["kind"]):
		Kind.REMOVAL:
			return removal_name
		Kind.WEAPON:
			return good.get_weapon().display_name
	return good.get_trinket().display_name

func _line_art(line: Dictionary) -> Texture2D:
	var good: CollectorGood = line["good"]
	if good == null:
		return null
	if good.get_weapon() != null:
		return good.get_weapon().art
	return good.get_trinket().art

# The type line: the kind, then at most one clause - MAX HP a → b when
# taking it changes max HP, else REPLACES <name> when its slot is filled.
# The plate keeps the full detail.
func type_line_at(line_index: int) -> String:
	if line_index < 0 or line_index >= _lines.size():
		return ""
	var line: Dictionary = _lines[line_index]
	var good: CollectorGood = line["good"]
	var kind: int = int(line["kind"])
	if kind == Kind.REMOVAL:
		return removal_type_text
	var text: String = weapon_kind_text
	var replaced_name: String = ""
	match kind:
		Kind.WEAPON:
			replaced_name = RunState.weapon.display_name if RunState.weapon != null else ""
		Kind.WORN:
			text = worn_kind_text
			var after: int = _max_hp_after(good.get_trinket())
			if after != RunState.player_max_hp:
				return text + type_separator + (max_hp_format % [RunState.player_max_hp, after])
			replaced_name = RunState.worn.display_name if RunState.worn != null else ""
		Kind.KEEPSAKE:
			text = keepsake_kind_text
			replaced_name = RunState.keepsake.display_name if RunState.keepsake != null else ""
	if not replaced_name.is_empty():
		return text + type_separator + (replaces_format % replaced_name).to_upper()
	return text

# Max HP once `piece` is worn - RunState.equip_worn()'s arithmetic.
func _max_hp_after(piece: TrinketData) -> int:
	var worn_bonus: int = maxi(RunState.worn.max_hp_bonus, 0) if RunState.worn != null else 0
	return RunState.player_max_hp - worn_bonus + maxi(piece.max_hp_bonus, 0)

# How many copies of `card` the deck holds now, a tempered one counted as
# the card - by name, its "+" set aside.
func deck_copies_of(card: CardData) -> int:
	if card == null:
		return 0
	var base: String = card.card_name.trim_suffix("+")
	var count: int = 0
	for held: CardData in RunState.deck:
		if held != null and held.card_name.trim_suffix("+") == base:
			count += 1
	return count

func _build_views() -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("CollectorScreen: could not load %s; no cards shown." % CARD_VIEW_SCENE_PATH)
		return
	for slot in _cards.size():
		var card: CardData = _cards[slot]
		if card == null:
			_views.append(null)
			continue
		var view := scene.instantiate() as CardView
		# Still in the row: focus is the hairline, never a hover's growth.
		view.hover_enabled = false
		_draw_layer.add_child(view)
		view.pivot_offset = Vector2.ZERO
		view.set_card_data(card)
		view.clicked.connect(_on_card_clicked.bind(slot))
		view.mouse_entered.connect(_on_card_mouse_entered.bind(slot))
		view.mouse_exited.connect(_on_card_mouse_exited.bind(slot))
		_views.append(view)
	# The stock arriving: each card's name sheens once (a Common's doesn't).
	for view: CardView in _views:
		if view != null:
			view.play_name_sheen()

func _card_size() -> Vector2:
	for view in _views:
		if view != null and is_instance_valid(view):
			return view.card_size
	return Vector2(200.0, 280.0)

# --- Layout ---

func _relayout() -> void:
	if _draw_layer == null or not is_node_ready():
		return
	var window: Vector2 = _draw_layer.size
	_fit = maxf(window.y / maxf(reference_height, 1.0), 0.01)
	var span_at_one: float = _row_span(_card_size().x * card_scale, _cards.size())
	_row_fit = _fit
	if span_at_one > 0.0:
		_row_fit = minf(_fit, _column_width() / span_at_one)
	_label_px = _px_int(label_size_px)
	_gold_px = _px_int(gold_size_px)
	_price_px = _px_int(price_size_px)
	_have_px = _px_int(have_size_px)
	_item_px = _px_int(item_size_px)
	_type_px = _px_int(type_size_px)
	_voice_px = _px_int(voice_size_px)
	_numeral_font = InkType.numeral_font()
	_label_font = InkType.tracked(InkType.text_bold_font(), _label_px, label_tracking_em)
	_have_font = InkType.tracked(InkType.text_bold_font(), _have_px, label_tracking_em)
	_type_font = InkType.tracked(InkType.text_bold_font(), _type_px, label_tracking_em)
	var face_scale: float = card_scale * _row_fit
	for slot in _views.size():
		var view: CardView = _views[slot]
		if view == null or not is_instance_valid(view):
			continue
		var rect: Rect2 = _slot_rect(slot)
		view.position = rect.position
		view.set_rest_offset(rect.position.y)
		view.set_base_scale(face_scale)
	_refresh()
	_relayout_inspect()

func _px(value: float) -> float:
	return value * _fit

func _px_int(value: int) -> int:
	return maxi(roundi(float(value) * _fit), 1)

func _column_left() -> float:
	return roundf(_draw_layer.size.x * column_left_fraction)

func _column_right() -> float:
	return roundf(_draw_layer.size.x * (1.0 - column_right_margin_fraction))

func _column_width() -> float:
	return maxf(_column_right() - _column_left(), 1.0)

func _row_span(card_width: float, count: int) -> float:
	if count <= 0:
		return 0.0
	var gaps: float = float(count - 1) * card_width * card_gap_fraction
	var fixed: float = card_width * fixed_gap_fraction if _fixed_slot() >= 0 else 0.0
	return float(count) * card_width + gaps + fixed

# The CARDS group shows when anything was stocked - and keeps its place
# once all of it is bought, so nothing below it moves.
func _has_cards() -> bool:
	return not _cards.is_empty()

func _cards_heading_baseline() -> float:
	return roundf(_px(first_heading_px))

func _cards_top() -> float:
	return roundf(_cards_heading_baseline() + _px(heading_rule_gap_px) + _px(heading_content_gap_px))

# A slot's face on screen - where its card stands, bought or not.
func _slot_rect(slot: int) -> Rect2:
	var card: Vector2 = _card_size() * card_scale * _row_fit
	var left: float = _column_left() + float(slot) * card.x * (1.0 + card_gap_fraction)
	if slot == _fixed_slot():
		left += card.x * fixed_gap_fraction
	return Rect2(roundf(left), _cards_top(), card.x, card.y)

func _have_baseline(slot: int) -> float:
	return roundf(_slot_rect(slot).end.y + _px(have_gap_px) + float(_have_px))

func _price_baseline(slot: int) -> float:
	return roundf(_have_baseline(slot) + _px(price_gap_px) + float(_price_px))

func _equipment_heading_baseline() -> float:
	if not _has_cards():
		return _cards_heading_baseline()
	return roundf(_price_baseline(0) + _px(group_gap_px))

func _lines_top() -> float:
	return roundf(_equipment_heading_baseline() + _px(heading_rule_gap_px))

# A line's row, the hairline's room to its left included.
func _line_rect(line_index: int) -> Rect2:
	var height: float = _px(line_height_px)
	var left: float = _column_left() - _px(hairline_gap_px + hairline_length_px)
	return Rect2(left, _lines_top() + height * float(line_index), _column_right() - left, height)

func _leave_baseline() -> float:
	return roundf(_draw_layer.size.y - _px(leave_bottom_px))

func _leave_left() -> float:
	return _column_right() - InkType.width(_label_font, leave_text, _label_px)

func _leave_rect() -> Rect2:
	var left: float = _leave_left() - _px(hairline_gap_px + hairline_length_px)
	return Rect2(left, _leave_baseline() - float(_label_px) * 1.2, _column_right() - left, float(_label_px) * 1.6)

# --- Draw ---

func _refresh() -> void:
	if _draw_layer != null:
		_draw_layer.queue_redraw()

func _with_alpha(alpha: float) -> Color:
	var color: Color = _ink
	color.a *= alpha
	return color

func _apply_veil() -> void:
	if _gradient == null:
		return
	var left: Color = _fog
	left.a = veil_left_alpha
	var right: Color = _fog
	right.a = veil_right_alpha
	var start: float = clampf(veil_ramp_start_fraction, 0.0, 1.0)
	var end: float = clampf(maxf(veil_ramp_end_fraction, start + 0.001), 0.0, 1.0)
	_gradient.offsets = PackedFloat32Array([0.0, start, end, 1.0])
	_gradient.colors = PackedColorArray([left, left, right, right])
	if _inspect_veil != null:
		var deep: Color = _fog
		deep.a = inspect_veil_alpha
		_inspect_veil.color = deep

func _text(canvas: CanvasItem, font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	return InkType.draw_run(canvas, font, text, origin, size_px, color)

# The focus hairline, left of `label_left`, centred on `mid_y`.
func _hairline(canvas: CanvasItem, label_left: float, mid_y: float) -> void:
	var length: float = _px(hairline_length_px)
	canvas.draw_rect(Rect2(label_left - _px(hairline_gap_px) - length, roundf(mid_y - hairline_thickness_px * 0.5), length, hairline_thickness_px), _ink)

func _heading(label: String, baseline: float) -> void:
	_text(_draw_layer, _label_font, label, Vector2(_column_left(), baseline), _label_px, _ink)
	var rule_y: float = roundf(baseline + _px(heading_rule_gap_px))
	_draw_layer.draw_rect(Rect2(_column_left(), rule_y, _column_width(), rule_thickness_px), _with_alpha(rule_alpha))

func _draw_screen() -> void:
	if _closing or _label_font == null:
		return
	_draw_voice()
	_draw_gold()
	if _has_cards():
		_heading(cards_heading_text, _cards_heading_baseline())
		_draw_cards()
	if not _lines.is_empty():
		_heading(equipment_heading_text, _equipment_heading_baseline())
		for index in _lines.size():
			_draw_line(index)
	var leave_focused: bool = _focus == _leave_index()
	_text(_draw_layer, _label_font, leave_text, Vector2(_leave_left(), _leave_baseline()), _label_px, _ink if leave_focused else _with_alpha(unfocused_alpha))
	if leave_focused:
		_hairline(_draw_layer, _leave_left(), _leave_baseline() - float(_label_px) * 0.35)

func _draw_gold() -> void:
	var amount: String = str(RunState.gold)
	var baseline: float = roundf(_px(top_margin_px))
	var amount_left: float = _column_right() - InkType.width(_numeral_font, amount, _gold_px)
	_text(_draw_layer, _numeral_font, amount, Vector2(amount_left, baseline), _gold_px, _ink)
	var caps_width: float = InkType.width(_label_font, gold_text, _label_px)
	_text(_draw_layer, _label_font, gold_text, Vector2(roundf(amount_left - _px(gold_gap_px) - caps_width), baseline), _label_px, _with_alpha(unfocused_alpha))

func _draw_cards() -> void:
	for slot in _cards.size():
		var card: CardData = _cards[slot]
		if card == null:
			continue
		var rect: Rect2 = _slot_rect(slot)
		var have: int = deck_copies_of(card)
		if have > 0:
			var have_text: String = have_format % have
			var have_x: float = roundf(rect.get_center().x - InkType.width(_have_font, have_text, _have_px) / 2.0)
			_text(_draw_layer, _have_font, have_text, Vector2(have_x, _have_baseline(slot)), _have_px, _with_alpha(unfocused_alpha))
		var price: String = str(_price_at(slot))
		var x: float = roundf(rect.get_center().x - InkType.width(_numeral_font, price, _price_px) / 2.0)
		_text(_draw_layer, _numeral_font, price, Vector2(x, _price_baseline(slot)), _price_px, _ink if _affordable(slot) else _with_alpha(inert_alpha))
		if _focus == slot:
			_hairline(_draw_layer, rect.position.x, rect.get_center().y)

func _draw_line(index: int) -> void:
	var line: Dictionary = _lines[index]
	var rect: Rect2 = _line_rect(index)
	var left: float = _column_left()
	var focused: bool = _focus == _line_base() + index
	var affordable: bool = _line_affordable(line)
	var name_color: Color = _ink if focused else _with_alpha(unfocused_alpha)
	var icon: float = _px(icon_size_px)
	var text_left: float = left + icon + _px(icon_gap_px)
	var mid: float = rect.position.y + rect.size.y * 0.5
	var art: Texture2D = _line_art(line)
	if art != null:
		var art_size: Vector2 = art.get_size()
		var width: float = icon * (art_size.x / maxf(art_size.y, 1.0))
		_draw_layer.draw_texture_rect(art, Rect2(roundf(left + (icon - width) * 0.5), roundf(mid - icon * 0.5), width, icon), false, Color(1.0, 1.0, 1.0, 1.0 if focused else art_unfocused_alpha))
	# The name and its type line as one block, centred on the row.
	var block: float = float(_item_px) + _px(type_gap_px) + float(_type_px)
	var name_baseline: float = roundf(mid - block * 0.5 + float(_item_px) * 0.8)
	var type_baseline: float = roundf(name_baseline + _px(type_gap_px) + float(_type_px))
	_text(_draw_layer, _numeral_font, _line_name(line), Vector2(text_left, name_baseline), _item_px, name_color)
	_text(_draw_layer, _type_font, type_line_at(index), Vector2(text_left, type_baseline), _type_px, _with_alpha(unfocused_alpha))
	var choose_left: float = _column_right() - InkType.width(_label_font, choose_text, _label_px)
	var choose_color: Color = name_color
	if int(line["kind"]) == Kind.REMOVAL and not affordable:
		choose_color = _with_alpha(inert_alpha)
	_text(_draw_layer, _label_font, choose_text, Vector2(choose_left, roundf(mid + float(_label_px) * 0.35)), _label_px, choose_color)
	var price: String = str(_line_price(line))
	var price_left: float = choose_left - _px(price_column_gap_px) - InkType.width(_numeral_font, price, _price_px)
	_text(_draw_layer, _numeral_font, price, Vector2(roundf(price_left), roundf(mid + float(_price_px) * 0.35)), _price_px, _ink if affordable else _with_alpha(inert_alpha))
	_draw_layer.draw_rect(Rect2(left, roundf(rect.end.y - rule_thickness_px), _column_width(), rule_thickness_px), _with_alpha(line_rule_alpha))
	if focused:
		_hairline(_draw_layer, left, mid)

# The world voice by the collector: the open line and the greyer second -
# or, a purchase just made, the purchase line alone - centred over its
# body's box on screen, kept clear of the screen's edge and the column.
func _draw_voice() -> void:
	if _voice_font == null:
		return
	var lines: Array[String] = []
	if _purchase_left > 0.0:
		lines.append(purchase_line)
	else:
		lines.append_array([open_line, second_line])
	var pitch: float = float(_voice_px) + _px(voice_line_gap_px)
	var anchor: Vector2 = _body_anchor()
	var margin: float = _px(voice_margin_px)
	for index in lines.size():
		var text: String = lines[index]
		var width: float = InkType.width(_voice_font, text, _voice_px)
		var x: float = clampf(anchor.x - width * 0.5, margin, maxf(_column_left() - margin - width, margin))
		var baseline: float = roundf(anchor.y - pitch * float(lines.size() - 1 - index))
		var color: Color = _ink if index == 0 else _with_alpha(second_line_alpha)
		_text(_draw_layer, _voice_font, text, Vector2(roundf(x), baseline), _voice_px, color)

# Where the voice's last line sits: over the middle of the body's box on
# screen, voice_clearance_px above its top - live, so it rides the
# camera's ease - or, with no body in view, a fifth of the way in at
# mid-height.
func _body_anchor() -> Vector2:
	if _draw_layer == null:
		return Vector2.ZERO
	var camera: Camera3D = get_viewport().get_camera_3d()
	var rect := Rect2()
	if _collector != null and is_instance_valid(_collector) and camera != null:
		rect = _collector.get_screen_rect(camera, 0.0)
	if rect.size == Vector2.ZERO:
		return Vector2(_draw_layer.size.x * 0.2, _draw_layer.size.y * 0.4)
	return Vector2(rect.get_center().x, rect.position.y - _px(voice_clearance_px))

# --- Camera ---

func _start_camera() -> void:
	_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	_camera_rest_offset = _camera.h_offset
	_ease_camera(_wanted_camera_offset())

# The h_offset that stands the body at camera_target_fraction of the
# width: its screen distance from there, in metres at its depth, within
# camera_offset_max_m of where the camera rests.
func _wanted_camera_offset() -> float:
	if _camera == null or not is_instance_valid(_camera) or _collector == null or not is_instance_valid(_collector):
		return _camera_rest_offset
	var view: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = _collector.get_screen_rect(_camera, 0.0)
	var depth: float = -(_camera.global_transform.affine_inverse() * _collector.global_position).z
	if rect.size == Vector2.ZERO or depth <= 0.1 or view.x <= 0.0:
		return _camera_rest_offset
	var visible_width: float = 2.0 * depth * tan(deg_to_rad(_camera.fov) * 0.5)
	if _camera.keep_aspect == Camera3D.KEEP_HEIGHT:
		visible_width *= view.x / maxf(view.y, 1.0)
	var shift: float = (rect.get_center().x - view.x * camera_target_fraction) * visible_width / view.x
	var wanted: float = _camera.h_offset + shift - _camera_rest_offset
	return _camera_rest_offset + clampf(wanted, -camera_offset_max_m, camera_offset_max_m)

# A tween of the tree's own, so it runs while the field is frozen and the
# ease home outlives this screen.
func _ease_camera(to_offset: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = get_tree().create_tween()
	_camera_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_camera_tween.tween_property(_camera, "h_offset", to_offset, maxf(camera_ease_seconds, 0.01))

# --- Focus ---

func _line_base() -> int:
	return _cards.size()

func _leave_index() -> int:
	return _cards.size() + _lines.size()

func _focusable(index: int) -> bool:
	if index >= 0 and index < _cards.size():
		return _cards[index] != null
	return index >= _line_base() and index <= _leave_index()

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	_focus = index
	_refresh()

# The next card from `from` stepping `step` along the row, wrapping; -1
# when the row is empty.
func _row_step(from: int, step: int) -> int:
	var count: int = _cards.size()
	if count == 0:
		return -1
	var start: int = from if from >= 0 else (-1 if step > 0 else count)
	for i in count:
		var index: int = posmod(start + step * (i + 1), count)
		if _focusable(index):
			return index
	return -1

func _on_card_mouse_entered(slot: int) -> void:
	if _input_open():
		_set_focus(slot)

func _on_card_mouse_exited(slot: int) -> void:
	if _input_open() and _focus == slot:
		_set_focus(-1)

func _input_open() -> bool:
	return not _closing and _inspect_slot < 0 and not _offer_open() and not _picker_open()

func _offer_open() -> bool:
	return _offer != null and is_instance_valid(_offer)

func _picker_open() -> bool:
	return _picker != null and is_instance_valid(_picker)

func _hit(position: Vector2) -> int:
	for index in _lines.size():
		if _line_rect(index).has_point(position):
			return _line_base() + index
	if _leave_rect().has_point(position):
		return _leave_index()
	return -1

func _on_gui_input(event: InputEvent) -> void:
	if not _input_open():
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
		close()
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _hit(button.position)
		if index >= 0:
			_activate(index)
		_draw_layer.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if _inspect_slot >= 0:
		_inspect_input(event)
		return
	if not _input_open():
		return
	var on_row: bool = _focus >= 0 and _focus < _cards.size()
	var on_lines: bool = _focus >= _line_base() and _focus < _leave_index()
	if event.is_action_pressed("ui_right"):
		if on_row or _focus < 0:
			_set_focus(_row_step(_focus if on_row else -1, 1))
	elif event.is_action_pressed("ui_left"):
		if on_row or _focus < 0:
			_set_focus(_row_step(_focus if on_row else -1, -1))
	elif event.is_action_pressed("ui_down"):
		if _focus < 0:
			var first: int = _row_step(-1, 1)
			_set_focus(first if first >= 0 else _line_base())
		elif on_row:
			_set_focus(_line_base())
		elif on_lines:
			_set_focus(_focus + 1)
	elif event.is_action_pressed("ui_up"):
		if _focus > _line_base():
			_set_focus(_focus - 1)
		elif _focus == _line_base():
			var first: int = _row_step(-1, 1)
			if first >= 0:
				_set_focus(first)
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_focus)
	elif event.is_action_pressed("ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()

# --- Acting ---

func _on_card_clicked(_card_data: CardData, slot: int) -> void:
	if _input_open():
		_activate(slot)

func _activate(index: int) -> void:
	if not _input_open():
		return
	if index == _leave_index():
		close()
	elif index >= 0 and index < _cards.size():
		_open_card(index)
	elif index >= _line_base() and index < _leave_index():
		var line: Dictionary = _lines[index - _line_base()]
		if int(line["kind"]) == Kind.REMOVAL:
			_open_picker()
		else:
			_open_offer(line)

# A card looked at, at inspect_card_scale over the deepened veil, with
# TAKE FOR <price> and BACK under it. TAKE is grey and inert while the
# price can't be paid.
func _open_card(slot: int) -> void:
	if _cards[slot] == null:
		return
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		return
	_inspect_slot = slot
	_inspect_focus = -1
	_inspect_view = scene.instantiate() as CardView
	_inspect_view.hover_enabled = false
	_inspect_layer.add_child(_inspect_view)
	_inspect_view.pivot_offset = Vector2.ZERO
	_inspect_view.set_card_data(_cards[slot])
	# Looked at closely: its keywords define themselves on hover.
	_inspect_view.set_keyword_inspect(true)
	_inspect_layer.visible = true
	_relayout_inspect()
	_inspect_view.play_name_sheen()

func _close_card() -> void:
	if _inspect_view != null and is_instance_valid(_inspect_view):
		_inspect_view.queue_free()
	_inspect_view = null
	_inspect_slot = -1
	_inspect_focus = -1
	_inspect_layer.visible = false
	_refresh()

func _inspect_card_rect() -> Rect2:
	var size: Vector2 = _card_size() * inspect_card_scale * _fit
	var centre_x: float = (_column_left() + _column_right()) * 0.5
	var top: float = _draw_layer.size.y * inspect_centre_fraction - size.y * 0.5
	return Rect2(roundf(centre_x - size.x * 0.5), roundf(top), size.x, size.y)

func _relayout_inspect() -> void:
	if _inspect_view == null or not is_instance_valid(_inspect_view) or _draw_layer == null:
		return
	var rect: Rect2 = _inspect_card_rect()
	_inspect_view.position = rect.position
	_inspect_view.set_rest_offset(rect.position.y)
	_inspect_view.set_base_scale(inspect_card_scale * _fit)
	_refresh_inspect()

func _refresh_inspect() -> void:
	if _inspect_veil != null:
		_inspect_veil.queue_redraw()

# TAKE FOR <price> for slot `slot`.
func take_text_at(slot: int) -> String:
	return take_format % _price_at(slot)

# TAKE FOR (0) and BACK (1) under the looked-at card: text, left edge,
# baseline and width, centred on the card.
func _inspect_line(index: int) -> Dictionary:
	var card: Rect2 = _inspect_card_rect()
	var text: String = take_text_at(_inspect_slot) if index == 0 else back_text
	var width: float = InkType.width(_label_font, text, _label_px)
	var pitch: float = float(_label_px) * 1.3 + _px(inspect_line_gap_px)
	var baseline: float = roundf(card.end.y + _px(inspect_actions_gap_px) + float(_label_px) + pitch * float(index))
	return {"text": text, "left": roundf(card.get_center().x - width * 0.5), "baseline": baseline, "width": width}

func _inspect_rect(index: int) -> Rect2:
	var line: Dictionary = _inspect_line(index)
	var label_left: float = line["left"]
	var left: float = label_left - _px(hairline_gap_px + hairline_length_px)
	return Rect2(left, float(line["baseline"]) - float(_label_px) * 1.2, label_left + float(line["width"]) - left, float(_label_px) * 1.6)

func _draw_inspect() -> void:
	if _inspect_slot < 0 or _label_font == null:
		return
	for index in 2:
		var line: Dictionary = _inspect_line(index)
		var inert: bool = index == 0 and not _affordable(_inspect_slot)
		var focused: bool = _inspect_focus == index and not inert
		var color: Color = _with_alpha(inert_alpha) if inert else (_ink if focused else _with_alpha(unfocused_alpha))
		var left: float = line["left"]
		var baseline: float = line["baseline"]
		_text(_inspect_veil, _label_font, line["text"], Vector2(left, baseline), _label_px, color)
		if focused:
			_hairline(_inspect_veil, left, baseline - float(_label_px) * 0.35)

func _on_inspect_gui_input(event: InputEvent) -> void:
	if _inspect_slot < 0:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = -1
		for index in 2:
			if _inspect_rect(index).has_point(motion.position):
				under = index
		if under != _inspect_focus:
			_inspect_focus = under
			_refresh_inspect()
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	_inspect_veil.accept_event()
	if button.button_index == MOUSE_BUTTON_LEFT and _inspect_rect(0).has_point(button.position):
		_take_card()
	else:
		_close_card()

func _inspect_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_inspect_focus = 1 if _inspect_focus == 0 else 0
		_refresh_inspect()
	elif event.is_action_pressed("ui_accept"):
		if _inspect_focus == 0:
			_take_card()
		elif _inspect_focus == 1:
			_close_card()
	elif event.is_action_pressed("ui_cancel"):
		_close_card()
	else:
		return
	get_viewport().set_input_as_handled()

# TAKE FOR on the looked-at card: its price spent, the card in the deck,
# its slot empty for good - the row never shifts. Inert while the price
# can't be paid.
func _take_card() -> void:
	var slot: int = _inspect_slot
	if slot < 0 or not _affordable(slot) or _collector == null:
		return
	var card: CardData = _cards[slot]
	var price: int = _price_at(slot)
	var gold_before: int = RunState.gold
	if not RunState.spend_gold(price):
		return
	RunState.add_card(card)
	if slot == _fixed_slot():
		_collector.take_fixed()
	else:
		_collector.take_stock(slot)
	_cards[slot] = null
	RunLogger.event("collector_buy", {
		"item": card.card_name,
		"kind": "card",
		"card": card.card_name,
		"rarity": String(CardData.CardRarity.find_key(card.rarity)).to_lower(),
		"price": price,
		"gold_before": gold_before,
		"gold_after": RunState.gold,
	})
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "CollectorScreen")
	print("CollectorScreen: bought '%s' for %d (gold %d, deck %d)." % [card.card_name, price, RunState.gold, RunState.deck.size()])
	var row_view: CardView = _views[slot]
	_views[slot] = null
	if row_view != null and is_instance_valid(row_view):
		row_view.queue_free()
	if _focus == slot:
		_focus = -1
	# The looked-at card flies to the deck; the screen comes back.
	var flying: CardView = _inspect_view
	_inspect_view = null
	if flying != null and is_instance_valid(flying):
		flying.reparent(_draw_layer)
		var tween: Tween = TakeFeedback.fly_to(self, flying, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
		tween.chain().tween_callback(flying.queue_free)
	_close_card()
	_purchased()

# A good's plate over the screen (ArmorExamine): a worn piece's with its
# Max HP line, a keepsake's, a weapon's - each with REPLACES what it
# would, TAKE FOR <price> (grey and inert while it can't be paid) and
# BACK. Escape, a click off it and BACK close it with nothing taken.
func _open_offer(line: Dictionary) -> void:
	var good: CollectorGood = line["good"]
	if good == null or _offer_open():
		return
	_offer = ArmorExamine.new()
	_offer.name = "GoodOffer"
	match int(line["kind"]):
		Kind.WEAPON:
			_offer.setup_weapon(good.get_weapon(), Rect2(), RunState.weapon, true, false, true)
		Kind.WORN:
			_offer.setup(good.get_trinket(), RunState.worn, true, Rect2(), false, RunState.player_max_hp)
		_:
			_offer.setup(good.get_trinket(), RunState.keepsake, true)
	_offer_line = line
	_offer.closed.connect(_on_offer_closed)
	add_child(_offer)
	# Its own _ready() puts it on layer 100 - this screen's.
	_offer.layer = layer + offer_layer_offset
	var plate: ItemPlate = _offer.get_plate()
	if plate != null:
		plate.take_text = take_format % good.price
		plate.leave_text = back_text
		plate.take_enabled = RunState.gold >= good.price
	_mouse_on = -1

func _on_offer_closed(taken: bool) -> void:
	_offer = null
	var line: Dictionary = _offer_line
	_offer_line = {}
	if taken and not line.is_empty():
		_buy_good(line)
	_refresh()

# A good taken: its price spent and it equipped at once - whatever it
# replaces is gone, the collector keeps it, no refund - and its line off
# the list.
func _buy_good(line: Dictionary) -> void:
	var good: CollectorGood = line["good"]
	if good == null or _collector == null:
		return
	var gold_before: int = RunState.gold
	if not RunState.spend_gold(good.price):
		return
	var item_id: String = ""
	var kind_name: String = "keepsake"
	match int(line["kind"]):
		Kind.WEAPON:
			item_id = String(good.get_weapon().id)
			kind_name = "weapon"
			RunState.equip_weapon(good.get_weapon())
		Kind.WORN:
			item_id = String(good.get_trinket().id)
			kind_name = "worn"
			RunState.equip_worn(good.get_trinket())
		_:
			item_id = String(good.get_trinket().id)
			# Seen and held: no drop offers it again this run.
			RunState.note_keepsake_offered(good.get_trinket())
			RunState.equip_keepsake(good.get_trinket())
	_collector.take_good(int(line["good_index"]))
	RunLogger.event("collector_buy", {
		"item": item_id,
		"kind": kind_name,
		"price": good.price,
		"gold_before": gold_before,
		"gold_after": RunState.gold,
	})
	TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoodTakeAudio", "CollectorScreen")
	print("CollectorScreen: bought '%s' (%s) for %d (gold %d)." % [item_id, kind_name, good.price, RunState.gold])
	_rebuild_lines()
	_purchased()

func _open_picker() -> void:
	if not _removal_open() or _picker_open():
		return
	_picker = DeckPanel.open_picker(get_tree(), RunState.deck, removal_header_text, layer + offer_layer_offset)
	_picker.header_voice = true
	_picker.pick_confirm_format = removal_confirm_format
	_picker.pick_confirm_price = _collector.removal_price
	_picker.pick_detail_format = removal_detail_format
	_picker.card_picked.connect(_on_removal_picked)
	_picker.closed.connect(_on_picker_closed)
	_mouse_on = -1

# The deck's card given: the price spent once, exactly that card gone,
# the removal line off the list.
func _on_removal_picked(card: CardData) -> void:
	if _collector == null or _collector.is_removal_used():
		return
	var price: int = _collector.removal_price
	var gold_before: int = RunState.gold
	if not RunState.spend_gold(price):
		return
	RunState.remove_card(card)
	_collector.use_removal()
	RunLogger.event("collector_removal", {
		"item": card.card_name,
		"kind": "removal",
		"card": card.card_name,
		"price": price,
		"gold_before": gold_before,
		"gold_after": RunState.gold,
	})
	TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "RemovalAudio", "CollectorScreen")
	print("CollectorScreen: gave up '%s' for %d (gold %d, deck %d)." % [card.card_name, price, RunState.gold, RunState.deck.size()])
	_rebuild_lines()
	_purchased()

# Picked or cancelled, the picker is gone: back to the screen.
func _on_picker_closed() -> void:
	_picker = null
	_refresh()

func _rebuild_lines() -> void:
	_build_lines()
	if _focus > _leave_index():
		_focus = _leave_index()
	_mouse_on = -1
	_refresh()

# After any purchase: the purchase line by the collector for a while.
func _purchased() -> void:
	_purchase_left = purchase_line_seconds
	_refresh()

func _on_prices_changed() -> void:
	_rebuild_lines()
	_relayout()

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

# LEAVE, ui_cancel or a right click: the screen goes, the field comes back
# (RegionField._on_collector_screen_closed()) and the camera eases home.
func close() -> void:
	if _closing:
		return
	_closing = true
	_ease_camera(_camera_rest_offset)
	closed.emit()
	queue_free()

# --- For probes ---

# What is in each card slot now (null = bought or empty).
func get_slot_cards() -> Array[CardData]:
	return _cards.duplicate()

func price_at(slot: int) -> int:
	return _price_at(slot)

# The equipment lines as they stand: each {kind, good_index, good}.
func get_lines() -> Array[Dictionary]:
	return _lines.duplicate()

func line_price(list_index: int) -> int:
	return _line_price(_lines[list_index])

# The focus index of line `list_index`, and of LEAVE - for activate().
func line_focus_index(list_index: int) -> int:
	return _line_base() + list_index

func leave_index() -> int:
	return _leave_index()

# Acts on focus index `index` as a click would: a card opens, a line's
# CHOOSE opens, LEAVE closes.
func activate(index: int) -> void:
	_activate(index)

func get_offer() -> ArmorExamine:
	return _offer if _offer_open() else null

func get_picker() -> DeckView:
	return _picker if _picker_open() else null

func is_card_open() -> bool:
	return _inspect_slot >= 0

func is_removal_open() -> bool:
	return _removal_open()

func is_purchase_line_showing() -> bool:
	return _purchase_left > 0.0

# TAKE FOR or BACK on the card looked at.
func take_open_card() -> void:
	_take_card()

func back_out_of_card() -> void:
	_close_card()

func get_camera() -> Camera3D:
	return _camera

func get_camera_rest_offset() -> float:
	return _camera_rest_offset
