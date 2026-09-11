extends CanvasLayer
class_name WeaponPickupWindow
# The weapon pickup window (2026-08-24 quiet/grounded rework) - a
# standalone component, duplicated out of reward_screen.tscn's own
# inline WeaponRewardOverlay rather than edited in place, so reward_
# screen.gd's shared gold/card/rare-drop/Continue logic is never
# touched by this pass. Self-contained: owns its own pause/unpause (see
# open_reward()/_close() below), the same "one instance, call a method,
# listen to a signal" shape DeckViewer.open_deck()/MapScreen.open_map_
# for_travel() already establish - the caller (reward_screen.gd) never
# reaches into this window's own nodes.
#
# CanvasLayer root, its own Backdrop ColorRect (2026-09-01, standard-modal
# conversion) - the same CanvasLayer + flat-Backdrop + pause shape DeckViewer
# and ShopWindow already use, replacing the old Control root and its radial
# GradientTexture2D dim. layer = 8, matching ShopWindow, above the field's
# own UI (layer 1) and below DeckViewer/MapScreen (layer 10).
#
# name_label/flavor_label use Spectral (Spectral-Light/Spectral-Regular,
# res://assets/fonts/) as per-node theme_override_fonts in weapon_pickup_
# window.tscn - scoped to this one scene, not a project-wide Theme entry,
# per this rework's own instruction. Every other label here stays on the
# project's default sans.

signal resolved(equipped: bool)

const LOCATION_GLYPH_SPACING := 2

@export_group("Backdrop")
@export_range(0.0, 1.0, 0.01) var backdrop_alpha: float = 0.52
# Lowered from the pre-panel 0.72 (2026-09-01, panel-followup pass) - the
# content panel now carries readability on its own, so the backdrop no
# longer needs to hide the field to make the reward legible; the room
# behind it should read as paused-but-present, not absent. RGB, size,
# anchoring, and mouse_filter are untouched - see _apply_backdrop_alpha()
# below, alpha only.

@export_group("Content Panel")
@export var panel_fill_color: Color = Color(0.13, 0.13, 0.16, 1)
# Matches MapScreen's own Panel bg_color (see map_screen.tscn's own
# StyleBoxFlat_panel) - same family read, not reinvented. Exposed for live
# tuning; border width/color and corner radius stay hardcoded to that same
# StyleBox's values in weapon_pickup_window.tscn's own StyleBoxFlat_content_
# panel, since this pass's brief only calls out fill colour and padding as
# needing knobs.
@export var panel_padding: float = 40.0
# Uniform inset on all four sides between the panel's own edge and
# ContentColumn - see _apply_panel_style() below.
@export var rule_separator_color: Color = Color(0.419608, 0.384314, 0.333333, 1)
# RuleSeparator (2026-09-01, panel-followup pass) - a DELIBERATE divider
# between RuleLabel and FlavorLabel, not a leftover from the pre-panel
# vignette layout: its old color, Color(0.172549, 0.156863, 0.137255, 1),
# is a consistent ~41% darkening of THIS SAME warm-brown hue (compare
# LocationLabel/RuleLabel's own font_color immediately above), not an
# arbitrary value - a quietly-styled rule matching this file's own "quiet/
# grounded" palette, just too dark to read against panel_fill_color's
# similarly dark, cooler tone. Raised one step here to match that same
# LocationLabel/RuleLabel tier exactly (reusing an established value
# already in this file, not inventing a new one) rather than staying a
# separate, now-invisible darker shade of it.

@onready var backdrop: ColorRect = $Backdrop
# Public, same "direct-read consumer" pattern as ShopWindow's own backdrop -
# field_room.gd reads backdrop.color.a directly (see its own additional_
# wanderer_dim doc) to keep the Wanderer's own EXTRA dim proportional to
# whatever this shared wash is currently tuned to.
@onready var content_panel: PanelContainer = $ContentScroll/ContentCenter/Panel
# Sits behind ContentColumn (2026-09-01, solid-surface pass) so the reward
# content reads on its own dark card instead of directly over the dimmed
# field - PanelContainer wraps ContentColumn and sizes itself to that
# column's own natural size plus panel_padding, the same "container sizes
# to its single child plus margins" mechanism MapScreen's own Panel
# doesn't need (MapScreen's Panel is a fixed size instead) but this window
# does, since ContentColumn's height varies with comparison-row visibility
# and flavor text length.
@onready var location_label: Label = $ContentScroll/ContentCenter/Panel/ContentColumn/LocationLabel
@onready var single_art: TextureRect = $ContentScroll/ContentCenter/Panel/ContentColumn/SingleArt
@onready var comparison_row: HBoxContainer = $ContentScroll/ContentCenter/Panel/ContentColumn/ComparisonRow
@onready var equipped_art: TextureRect = $ContentScroll/ContentCenter/Panel/ContentColumn/ComparisonRow/EquippedColumn/EquippedArt
@onready var offered_art_in_row: TextureRect = $ContentScroll/ContentCenter/Panel/ContentColumn/ComparisonRow/OfferedColumn/OfferedArt
@onready var name_label: Label = $ContentScroll/ContentCenter/Panel/ContentColumn/NameLabel
@onready var flavor_label: Label = $ContentScroll/ContentCenter/Panel/ContentColumn/FlavorLabel
@onready var rule_label: Label = $ContentScroll/ContentCenter/Panel/ContentColumn/RuleLabel
@onready var rule_separator: HSeparator = $ContentScroll/ContentCenter/Panel/ContentColumn/RuleSeparator
@onready var take_button: Button = $ContentScroll/ContentCenter/Panel/ContentColumn/ButtonRow/TakeButton
@onready var leave_button: Button = $ContentScroll/ContentCenter/Panel/ContentColumn/ButtonRow/LeaveButton

# Godot Labels have no letter-spacing property of their own - a
# FontVariation wrapping the label's own base font, with set_spacing(),
# is what actually produces the tracked-out look (same technique weapon_
# card.gd's own _lore_italic_font already uses for its synthetic italic,
# just spacing instead of a shear). LocationLabel ONLY now (2026-08-26
# register fix) - RuleLabel used to share this exact treatment, which was
# the bug: letterspacing is a WORLD-VOICE marker on this screen (see
# LocationLabel's own "found in the sunken works"), and RuleLabel is a
# rules statement, not lore - it needs to read as system-voice instead,
# same register card_text_styles.gd's own rules text already uses
# elsewhere, not a second copy of LocationLabel's look.
var _location_font: FontVariation

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_letter_spacing()
	_apply_panel_style()
	_apply_rule_separator_style()
	_apply_backdrop_alpha()
	take_button.pressed.connect(_on_take_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

# Alpha only - RGB, size, anchoring, and mouse_filter stay exactly as
# weapon_pickup_window.tscn authors them on Backdrop itself. See
# backdrop_alpha's own doc for why this got lowered.
func _apply_backdrop_alpha() -> void:
	backdrop.color.a = backdrop_alpha

# Mutates the same StyleBoxLine instance weapon_pickup_window.tscn already
# assigns to rule_separator (theme_override_styles/separator), the same
# "read the export, apply it once at _ready()" pattern _apply_panel_style()
# uses. See rule_separator_color's own doc for why this needed a knob.
func _apply_rule_separator_style() -> void:
	var style: StyleBoxLine = rule_separator.get_theme_stylebox("separator")
	style.color = rule_separator_color

# Mutates the same StyleBoxFlat instance weapon_pickup_window.tscn already
# assigns to content_panel (theme_override_styles/panel) rather than
# building a new one - same "read the export, apply it once at _ready()"
# pattern base_world_dim_opacity used to follow via _build_dim_gradient()
# before this window became a standard modal. Border width/color/corner
# radius are left exactly as authored in the .tscn (matching MapScreen's
# own StyleBoxFlat_panel) - only fill colour and padding are knobs here.
func _apply_panel_style() -> void:
	var style: StyleBoxFlat = content_panel.get_theme_stylebox("panel")
	style.bg_color = panel_fill_color
	style.content_margin_left = panel_padding
	style.content_margin_top = panel_padding
	style.content_margin_right = panel_padding
	style.content_margin_bottom = panel_padding

func _setup_letter_spacing() -> void:
	_location_font = FontVariation.new()
	_location_font.base_font = location_label.get_theme_default_font()
	_location_font.set_spacing(TextServer.SPACING_GLYPH, LOCATION_GLYPH_SPACING)
	location_label.add_theme_font_override("font", _location_font)

# The one public entry point - reward_screen.gd calls this with the
# weapon being offered and whatever's currently equipped (null if the
# slot is empty), and reacts to the `resolved` signal once the player
# picks Take it/Leave it. Everything about HOW this looks lives entirely
# in here and in weapon_pickup_window.tscn - reward_screen.gd never sees
# any of this window's own child nodes.
func open_reward(offered: WeaponData, currently_equipped: WeaponData) -> void:
	# RunState.current_biome is a real BiomeData resource (see biome_
	# data.gd), not a hardcoded string - "The Sunken Works" today, but
	# this line never needs to change when a second biome exists.
	location_label.text = "found in %s" % RunState.current_biome.biome_name.to_lower()

	if currently_equipped == null:
		single_art.texture = offered.icon_texture
		single_art.visible = true
		comparison_row.visible = false
	else:
		single_art.visible = false
		comparison_row.visible = true
		equipped_art.texture = currently_equipped.icon_texture
		offered_art_in_row.texture = offered.icon_texture

	name_label.text = offered.weapon_name
	flavor_label.text = offered.description

	var rule_text: String = offered.modifier.describe() if offered.modifier != null else ""
	# Shown exactly as describe() authors it (2026-08-26 register fix) -
	# every branch of WeaponModifier.describe() already returns proper
	# sentence case ("HP costs also deal damage to the enemy") on its
	# own; the old .to_lower() here was purely a leftover from RuleLabel
	# once sharing LocationLabel's world-voice look, not something the
	# text itself ever needed.
	rule_label.text = rule_text
	rule_label.visible = rule_text != ""

	visible = true
	get_tree().paused = true

func _on_take_pressed() -> void:
	_close(true)

func _on_leave_pressed() -> void:
	_close(false)

func _close(equipped: bool) -> void:
	visible = false
	get_tree().paused = false
	resolved.emit(equipped)
