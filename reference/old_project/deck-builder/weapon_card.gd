extends Control
class_name WeaponCard
# A weapon's own detail presentation - structurally similar to Card (see
# card.gd's own header note: outer frame, a name zone, an art zone,
# stacked in a VBoxContainer whose stretch ratios reserve each zone a
# fixed proportion regardless of content) but deliberately distinct
# enough to never read as "a card you could play": a dark metal-plate
# palette instead of Card's parchment tone (see weapon_card.tscn), no
# cost badge (weapons aren't played), sharper corners, and two SEPARATE
# text zones below the art instead of one shared description -
# mechanical effect (generated, prominent) and lore (hand-written,
# visually de-emphasized - see _setup_lore_font() below) never compete
# for the same line or the same emphasis.
#
# Read-only (no click signal - nothing here is "playable"), but CAN
# hover like a Card if a caller wants that: mouse_filter = IGNORE is
# baked into every node here (see weapon_card.tscn) as the default, so
# an instance sitting on top of whatever's actually driving it (a
# hovered LootRow, an open swap overlay) never steals the mouse from
# it, and simply never receives mouse_entered/exited - inert, exactly
# as before hover support existed. A caller that wants THIS instance to
# feel as interactive as a Card overrides the root's mouse_filter to
# STOP instead (see deck_viewer.tscn's own instance override) - hover_
# offset/hover_scale below then animate Visual exactly the way Card's
# own hover does (see card.gd's _play_hover_tween()), opt-in per
# instance rather than a second component.
#
# One instance, reused wherever a weapon needs showing (the loot-row
# hover preview, the equip/swap comparison, the deck viewer's equipped-
# weapon readout - see reward_screen.gd/deck_viewer.gd) via
# set_weapon_data(), the same "one instance, re-fed" pattern shop_
# window.gd's own card preview already established, rather than a
# bespoke layout per screen - this is what makes "one consistent
# presentation for equipment" literally true, not just a design goal.

var weapon_data: WeaponData

# --- Layout (DESIGN values, i.e. at scale factor 1.0) ---
#
# Same "everything a Container can't work out on its own lives in an
# @export, _apply_layout() is the only place that reads it" shape as
# card.gd's own Card Layout group - tune these from the Inspector on
# weapon_card.tscn (or on a specific instance, like deck_viewer.tscn's
# smaller readout - see its own design_size override) without touching
# this script.
@export_group("Weapon Card Layout")
@export var design_size: Vector2 = Vector2(300, 480)
@export var outer_margin_px: float = 10.0
@export var zone_separation_px: float = 8.0
@export var zone_content_margin_px: float = 8.0
# Relative weights, NOT pixels - how Zones' VBoxContainer splits the
# available height between the four bands (see card.gd's own identical
# note on its three). The art zone dominates on purpose - "full art"
# is the brief, not a thumbnail squeezed between two paragraphs.
@export var name_zone_stretch: float = 0.55
@export var art_zone_stretch: float = 2.2
@export var effect_zone_stretch: float = 0.85
@export var lore_zone_stretch: float = 0.95

@export_group("Weapon Card Fonts")
@export var name_font_size_px: int = 24
@export var effect_font_size_px: int = 17
@export var lore_font_size_px: int = 14

@export_group("Text Emphasis")
@export var effect_color: Color = Color(0.7, 0.85, 1, 1)
# Same accent blue this project's other weapon UI already settled on
# (reward_screen.gd's swap comparison used this before it was folded
# into this shared component) - one color vocabulary for "this is a
# mechanical effect, act on it" wherever one shows up.
@export var lore_color: Color = Color(0.62, 0.62, 0.68, 1)
# Deliberately muted/desaturated relative to effect_color - lore is
# flavor, not something the player needs to act on (see this class's
# own header note and _setup_lore_font() below).
@export var lore_italic_skew: float = 0.22
# Synthetic italic - a shear applied to a FontVariation wrapping
# whatever font is already active, rather than requiring a dedicated
# italic font asset neither this project nor Godot's default theme
# ships. Godot doesn't auto-synthesize italics for a font with no
# italic style of its own, so this is what actually makes lore text
# slant, not just a smaller/duller copy of the same upright text. If it
# visually leans the WRONG way once you see it in the editor, just flip
# this value's sign here in the Inspector - no code change needed.

# --- Hover (opt-in - see this class's own header note) ---
#
# Deliberately smaller than Card's own default rise (hover_offset =
# Vector2(0, -50), see card.gd) - Card's hand sits mostly below the
# screen's bottom edge and a hand card needs to travel far to read as
# "picked out"; a WeaponCard shown here is already a single, fully
# visible, centered item, so a big pop would read as gaudy rather than
# responsive. Still @export, still per-instance - a future usage that
# wants Card's own magnitude can just set it.
@export_group("Hover")
@export var hover_offset: Vector2 = Vector2(0, -16)
@export var hover_scale: Vector2 = Vector2(1.04, 1.04)
@export var hover_duration: float = 0.1

@onready var visual: Panel = $Visual
@onready var frame: MarginContainer = $Visual/Frame
@onready var zones: VBoxContainer = $Visual/Frame/Zones
@onready var name_banner: PanelContainer = $Visual/Frame/Zones/NameBanner
@onready var name_label: Label = $Visual/Frame/Zones/NameBanner/NameLabel
@onready var art_slot: PanelContainer = $Visual/Frame/Zones/ArtSlot
@onready var art_texture: TextureRect = $Visual/Frame/Zones/ArtSlot/ArtTexture
@onready var effect_label: Label = $Visual/Frame/Zones/EffectLabel
@onready var lore_label: Label = $Visual/Frame/Zones/LoreLabel

var _scale_factor: float = 1.0

# Visual/NameBanner/ArtSlot each carry their own StyleBoxFlat straight
# out of weapon_card.tscn - shared resources until duplicated here ONCE
# into per-instance copies, same reasoning as card.gd's own _own_zone_
# styles(): otherwise recoloring one instance's rarity border would
# recolor every other instance sharing that same underlying resource.
var _visual_style: StyleBoxFlat
var _name_banner_style: StyleBoxFlat
var _art_slot_style: StyleBoxFlat
var _lore_italic_font: FontVariation

# Same "kill and restart, don't stack" pattern as Card's own _hover_
# tween (see card.gd) - only ever runs at all if this instance's
# mouse_filter was overridden to actually receive mouse_entered/exited
# in the first place.
var _hover_tween: Tween

func _ready() -> void:
	_own_zone_styles()
	_setup_text_emphasis()
	_apply_layout()
	# CENTERED, not Card's own COVERED (see card.gd's art_texture note) -
	# the brief asks for the weapon's FULL art, not a cropped fill the
	# way trading-card art gets cropped to its slot. Same choice loot_
	# row.gd's own weapon icon already made; kept consistent here.
	art_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	_play_hover_tween(hover_offset, hover_scale)

func _on_mouse_exited() -> void:
	_play_hover_tween(Vector2.ZERO, Vector2.ONE)

func _play_hover_tween(target_position: Vector2, target_scale: Vector2) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_parallel(true)
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(visual, "position", target_position, hover_duration)
	_hover_tween.tween_property(visual, "scale", target_scale, hover_duration)

func _own_zone_styles() -> void:
	_visual_style = visual.get_theme_stylebox("panel").duplicate()
	_name_banner_style = name_banner.get_theme_stylebox("panel").duplicate()
	_art_slot_style = art_slot.get_theme_stylebox("panel").duplicate()
	visual.add_theme_stylebox_override("panel", _visual_style)
	name_banner.add_theme_stylebox_override("panel", _name_banner_style)
	art_slot.add_theme_stylebox_override("panel", _art_slot_style)

func _setup_text_emphasis() -> void:
	_lore_italic_font = FontVariation.new()
	_lore_italic_font.base_font = lore_label.get_theme_default_font()
	# Shear on the Y axis: for Godot's Y-down screen convention, a
	# glyph's top sits at NEGATIVE local y - shifting it toward
	# POSITIVE x needs a NEGATIVE y_axis.x coefficient (transformed_x =
	# x + y_axis.x * y). That's what actually leans the top of each
	# letter to the right, the standard italic direction.
	_lore_italic_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-lore_italic_skew, 1), Vector2.ZERO)
	lore_label.add_theme_font_override("font", _lore_italic_font)
	lore_label.add_theme_color_override("font_color", lore_color)
	effect_label.add_theme_color_override("font_color", effect_color)

# Rescales the whole card face to `factor` x design_size (1.0 = the
# design values above) - call once, right after instancing (or leave
# untouched to render at design_size directly, e.g. a per-instance
# design_size override with no scale call at all - see deck_viewer.
# tscn's smaller readout instance).
func set_scale_factor(factor: float) -> void:
	_scale_factor = factor
	_apply_layout()

# The one place every exported layout value actually lands on a node -
# both _ready() and set_scale_factor() funnel through here, so editing
# an @export in the Inspector and calling set_scale_factor() always
# agree on what the card should look like.
func _apply_layout() -> void:
	var f := _scale_factor
	custom_minimum_size = design_size * f
	visual.pivot_offset = design_size * f / 2.0

	var margin := roundi(outer_margin_px * f)
	frame.add_theme_constant_override("margin_left", margin)
	frame.add_theme_constant_override("margin_top", margin)
	frame.add_theme_constant_override("margin_right", margin)
	frame.add_theme_constant_override("margin_bottom", margin)

	zones.add_theme_constant_override("separation", roundi(zone_separation_px * f))
	name_banner.size_flags_stretch_ratio = name_zone_stretch
	art_slot.size_flags_stretch_ratio = art_zone_stretch
	effect_label.size_flags_stretch_ratio = effect_zone_stretch
	lore_label.size_flags_stretch_ratio = lore_zone_stretch

	for style in [_name_banner_style, _art_slot_style]:
		style.content_margin_left = zone_content_margin_px * f
		style.content_margin_top = zone_content_margin_px * f
		style.content_margin_right = zone_content_margin_px * f
		style.content_margin_bottom = zone_content_margin_px * f

	name_label.add_theme_font_size_override("font_size", roundi(name_font_size_px * f))
	effect_label.add_theme_font_size_override("font_size", roundi(effect_font_size_px * f))
	lore_label.add_theme_font_size_override("font_size", roundi(lore_font_size_px * f))

# The public entry point - anyone displaying a weapon (a hovered loot
# row, the swap overlay, the deck viewer) calls this instead of
# touching the labels directly, same shape as Card.set_card_data().
func set_weapon_data(data: WeaponData) -> void:
	weapon_data = data
	_update_display()

func _update_display() -> void:
	if weapon_data == null:
		return
	name_label.text = weapon_data.weapon_name
	effect_label.text = weapon_data.modifier.describe() if weapon_data.modifier != null else ""
	effect_label.visible = effect_label.text != ""
	lore_label.text = weapon_data.description
	art_texture.texture = weapon_data.icon_texture
	art_texture.visible = weapon_data.icon_texture != null
	_update_rarity_border()

# Reuses Card's own RARITY_BORDER_COLORS directly (see card.gd) rather
# than a second copy - one rarity, one color, no matter where it shows
# up, the same reasoning weapon_data.gd's own rarity field note and
# reward_screen.gd already established for this before it moved here.
func _update_rarity_border() -> void:
	_visual_style.border_color = Card.RARITY_BORDER_COLORS.get(weapon_data.rarity, Card.RARITY_BORDER_COLORS[CardData.Rarity.COMMON])
