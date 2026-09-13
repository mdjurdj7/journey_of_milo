extends Panel
class_name CardView

signal clicked(card_data: CardData)
# Fired whenever this card visually lifts out of the hand for any reason -
# hover OR armed (lift_and_hold()) - and again once it settles back down.
# HandContainer listens for these to straighten the card's own fan
# rotation to 0 and raise it above its neighbors while lifted, then
# restore both on lowered - this script only knows about its own
# position.y lift (see _tween_to()); it has no idea it's sitting in a fan
# at all, let alone what angle/z_index to return to.
signal lifted
signal lowered

@export var card_size: Vector2 = Vector2(247.0, 345.0)

@export_group("Card Layout")
@export var card_outer_margin: float = 12.0
@export var name_zone_height: float = 40.0
@export var name_font_size_px: int = 22
@export var badge_diameter: float = 40.0
@export var badge_margin: float = 8.0
# Fraction of card_size.y, not a fixed pixel height - the art region
# scales with the card instead of leaving a growing/shrinking gap above
# the description band as card_size changes (hand vs. DeckView's own
# scaled-down grid).
@export_range(0.1, 0.9) var art_zone_height_fraction: float = 0.45
# How far the art fill sits inset from its own band's edges on every
# side, leaving the card's base face color as a frame around it within
# the band (not touching the separator lines directly).
@export var art_inset_margin: float = 8.0
@export var separator_width_px: float = 1.0
@export var description_font_size_px: int = 18
@export var name_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")

@export_group("Type Colors")
# Art region fill and (unless edge_color_override_enabled below is on)
# the card's own outer border color - muted, not the vivid hues a more
# saturated world might use. STANCE has no entry yet (see _color_for_
# type()'s own doc) - add one here and a matching branch there once a
# STANCE card actually exists.
@export var art_color_attack: Color = Color(0.42, 0.28, 0.24, 1.0)
@export var art_color_skill: Color = Color(0.28, 0.36, 0.42, 1.0)
@export var card_edge_width_px: float = 2.0
@export_range(0.0, 1.0) var card_edge_alpha: float = 0.5

# Fixed dark-plate/light-numeral badge, regardless of the on-pale/on-dark
# world - a cost token reads as its own small fixed object sitting on the
# card, not part of the face that inverts with it (unlike panel_color/
# text_color below, which do come from the theme's current value set).
@export var badge_bg_color: Color = Color(0.08, 0.08, 0.08, 1.0)
@export var badge_fg_color: Color = Color(0.95, 0.94, 0.9, 1.0)

@export_group("Hover")
# Off for DeckView's browsing grid (set right after instantiate(), same
# pre-add_child() timing HandContainer already uses for card_size) -
# GridContainer re-asserts each child's position on its own schedule, not
# every frame, so a hover tween nudging position.y there would fight it
# and can visually shove a card up into the row above. Hand row use
# (HandContainer/CardView's own default) is unaffected.
@export var hover_enabled: bool = true
# Measured from rest (see _rest_offset_y below), not from 0 - with
# HandContainer's own default hand_rest_visible_height (230, card_size.y
# 345 -> a 115px rest offset), this needs to clear that 115 for hover to
# actually read as "fully into view," not just "a little less hidden."
@export var hover_lift: float = 130.0
@export var hover_duration_sec: float = 0.12

@export_group("Edge Override")
# Every card gets a border by default - see card_edge_width_px/
# card_edge_alpha above, colored from card_type once card_data is set
# (_apply_type_style()). This is an escape hatch for a caller that wants
# a DIFFERENT, fixed edge instead (DeckView's own alternative "1px, one
# step lighter than the face" treatment - see its own use_card_edge
# export): set right after instantiate(), same pre-add_child() timing as
# hover_enabled above.
@export var edge_color_override_enabled: bool = false
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var edge_width_px: float = 1.0

@onready var name_label: Label = $NameLabel
@onready var header_separator: ColorRect = $HeaderSeparator
@onready var badge: Panel = $Badge
@onready var cost_label: Label = $Badge/CostLabel
@onready var art_rect: ColorRect = $ArtRect
@onready var art_separator: ColorRect = $ArtSeparator
@onready var description_label: Label = $DescriptionLabel

var card_data: CardData
var _armed: bool = false
var _rest_offset_y: float = 0.0
# How far down from this card's own local origin "at rest" actually sits -
# pushed down by HandContainer.hand_rest_visible_height so only part of
# the card pokes up past the screen's bottom edge. hover_lift below is
# measured FROM this baseline, not from 0 - see set_rest_offset().

# The outer Panel's own stylebox, kept so set_card_data()/
# _apply_type_style() can update its border color/width once card_type
# is known - _apply_style() (theme colors only) runs at _ready(), before
# any CardData exists, so the border can't be finalized there.
var _card_style: StyleBoxFlat

func _ready() -> void:
	size = card_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()
	_apply_layout()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func set_card_data(data: CardData) -> void:
	card_data = data
	name_label.text = data.card_name
	cost_label.text = str(data.cost)
	description_label.text = data.description
	_apply_type_style()
	_position_name_label()

# Called once by HandContainer right after this card enters the row - sets
# where "at rest" actually is and snaps there immediately (not tweened;
# this is initial placement, not a hover transition). Safe to call before
# or after set_card_data().
func set_rest_offset(offset_y: float) -> void:
	_rest_offset_y = offset_y
	if not _armed:
		position.y = _rest_offset_y

# Held while awaiting a target for this card (see BattleController.
# request_play()) - hover in/out is ignored while armed, since the card is
# already deliberately lifted and shouldn't drop just because the mouse
# passes over it.
func lift_and_hold() -> void:
	_armed = true
	_tween_to(_rest_offset_y - hover_lift)
	lifted.emit()

func release() -> void:
	_armed = false
	_tween_to(_rest_offset_y)
	lowered.emit()

func _on_mouse_entered() -> void:
	if hover_enabled and not _armed:
		_tween_to(_rest_offset_y - hover_lift)
		lifted.emit()

func _on_mouse_exited() -> void:
	if hover_enabled and not _armed:
		_tween_to(_rest_offset_y)
		lowered.emit()

func _tween_to(target_y: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:y", target_y, hover_duration_sec)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(card_data)

func _apply_style() -> void:
	var panel_color: Color = get_theme_color("panel_color", "CardFace")
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var text_color: Color = get_theme_color("text_color", "CardFace")

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = panel_color
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.shadow_size = 0
	add_theme_stylebox_override("panel", card_style)
	_card_style = card_style

	name_label.add_theme_color_override("font_color", text_color)
	name_label.add_theme_font_size_override("font_size", name_font_size_px)
	if name_font != null:
		name_label.add_theme_font_override("font", name_font)

	header_separator.color = panel_light_color
	art_separator.color = panel_light_color
	# Fallback fill before any CardData exists - _apply_type_style()
	# overrides this with the real card_type color the instant
	# set_card_data() runs, which every real caller does immediately.
	art_rect.color = panel_light_color

	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = badge_bg_color
	var badge_radius: int = int(badge_diameter / 2.0)
	badge_style.corner_radius_top_left = badge_radius
	badge_style.corner_radius_top_right = badge_radius
	badge_style.corner_radius_bottom_right = badge_radius
	badge_style.corner_radius_bottom_left = badge_radius
	badge_style.shadow_size = 0
	badge.add_theme_stylebox_override("panel", badge_style)

	cost_label.add_theme_color_override("font_color", badge_fg_color)
	# Synthetic bold via FontVariation.variation_embolden, not a second
	# font asset - this project ships exactly one font file (Spectral-
	# SemiBold, used only for name_label); cost_label otherwise renders
	# with whatever default font Control theming provides, and embolden
	# works on that directly.
	var bold_font := FontVariation.new()
	bold_font.base_font = cost_label.get_theme_font("font")
	bold_font.variation_embolden = 1.2
	cost_label.add_theme_font_override("font", bold_font)

	description_label.add_theme_color_override("font_color", text_color)
	description_label.add_theme_font_size_override("font_size", description_font_size_px)

# card_type-dependent styling (art fill + outer border) - split out from
# _apply_style() because card_type lives on CardData, which _ready()
# (when _apply_style() runs) hasn't received yet. Re-run every
# set_card_data() call, not just the first, so a CardView slot that gets
# reused for a different card (none do today, but this way one could)
# would show the right type color rather than a stale one.
func _apply_type_style() -> void:
	if card_data == null or _card_style == null:
		return

	var type_color: Color = _color_for_type(card_data.card_type)
	art_rect.color = type_color

	var border_color: Color = edge_color
	var border_width_px: float = edge_width_px
	if not edge_color_override_enabled:
		border_color = type_color
		border_color.a = card_edge_alpha
		border_width_px = card_edge_width_px

	var border_width: int = int(border_width_px)
	_card_style.border_width_left = border_width
	_card_style.border_width_top = border_width
	_card_style.border_width_right = border_width
	_card_style.border_width_bottom = border_width
	_card_style.border_color = border_color

# STANCE has no case yet - it isn't a real CardType value in this project
# today (see CardData.CardType's own doc). Add art_color_stance and a
# branch here once it is; the wildcard keeps every existing card safe in
# the meantime rather than needing every call site updated in lockstep.
func _color_for_type(card_type: CardData.CardType) -> Color:
	match card_type:
		CardData.CardType.SKILL:
			return art_color_skill
		_:
			return art_color_attack

# Measures the actual name text against the badge's footprint (top-left
# corner, see badge.position/size in _apply_layout()) and shifts the label
# right by exactly the overlap when dead-centering would collide with it -
# name_label.size stays the full band width either way, only position.x
# moves, so an unshifted name stays truly centered on the whole band.
func _position_name_label() -> void:
	var font: Font = name_label.get_theme_font("font")
	var text_size: Vector2 = font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_font_size_px)
	var text_left: float = (card_size.x - text_size.x) / 2.0
	var badge_right: float = badge.position.x + badge.size.x
	var overlap: float = badge_right - text_left
	name_label.position.x = maxf(overlap, 0.0)

func _apply_layout() -> void:
	# Dead-centered across the full band width, ignoring the badge -
	# _position_name_label() (called from set_card_data(), once the real
	# name text is known) nudges it right only if that centering would
	# actually collide with the badge's footprint.
	name_label.position = Vector2.ZERO
	name_label.size = Vector2(card_size.x, name_zone_height)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Cost badge overlaps the header band's own top-left corner rather
	# than sitting fully inside it - badge_margin (8) is deliberately
	# smaller than card_outer_margin (12), the same relationship
	# name_label's own inset already uses, so the badge pokes slightly
	# past where the header band's content would otherwise start.
	badge.position = Vector2(badge_margin, badge_margin)
	badge.size = Vector2(badge_diameter, badge_diameter)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	cost_label.position = Vector2.ZERO
	cost_label.size = Vector2(badge_diameter, badge_diameter)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Three stacked bands - header (name_zone_height), art (a fraction of
	# card_size.y), description (whatever's left) - each separated by a
	# thin line spanning the card's full width. name_zone_height is fixed
	# pixels (it only ever has to fit one line of the name font); the art
	# band scales with the card instead, and description absorbs whatever
	# remains rather than needing its own explicit height.
	var art_band_top: float = name_zone_height
	var art_band_height: float = card_size.y * art_zone_height_fraction
	var description_top: float = art_band_top + art_band_height

	header_separator.position = Vector2(0.0, art_band_top)
	header_separator.size = Vector2(card_size.x, separator_width_px)
	header_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	art_rect.position = Vector2(art_inset_margin, art_band_top + art_inset_margin)
	art_rect.size = Vector2(card_size.x - art_inset_margin * 2.0, art_band_height - art_inset_margin * 2.0)
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	art_separator.position = Vector2(0.0, description_top)
	art_separator.size = Vector2(card_size.x, separator_width_px)
	art_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE

	description_label.position = Vector2(card_outer_margin, description_top + card_outer_margin)
	description_label.size = Vector2(card_size.x - card_outer_margin * 2.0, card_size.y - description_top - card_outer_margin * 2.0)
	description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
