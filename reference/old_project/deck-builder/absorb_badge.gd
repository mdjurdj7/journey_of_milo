extends Control
class_name AbsorbBadge
# Absorb's own square-footprint-but-round-shape badge (2026-09-05, Shore
# Up pass) - a near-verbatim DUPLICATE of block_badge.gd (same project
# convention every other paired UI element here already follows: a
# proven shape copied, not extracted into something shared - see field_
# heap.gd's own header for the fullest statement of that convention).
# Two deliberate differences from BlockBadge, both explicit in this
# feature's own brief:
#   1. ALWAYS a circle/bubble, never square - unlike BlockBadge, whose
#      own corner radius tracks the bar's bar_corner_radius_px (0 today,
#      "squares off the bar entirely" - see vitals_bar.gd's own doc), this
#      badge computes its own corner radius from HALF its current size on
#      every resize (see _apply_corner_radius_for_current_size() below),
#      completely independent of whatever the bar's own corner radius is
#      set to. Absorb should read as a distinct SHAPE from block at a
#      glance, not just a different color in the same square frame.
#   2. A paler sibling of Block's own badge color, not a new hue - fill
#      color is badge_fill_color.lightened(badge_fill_lighten_amount)
#      (2026-09-07, badge-legibility pass - was HudPalette.FILL.
#      lightened(0.3); see badge_fill_color's own doc below for why that
#      broke and stopped being FILL-derived). Absorb reads as "in
#      block's own material family, just lighter," per this feature's
#      own brief - deliberately NOT a new hue, and deliberately NOT red
#      (the bar already carries HP's red and Rally's own desaturated
#      band).
#
# Everything else - the square Control + Panel + duplicated StyleBoxFlat
# approach, content-aware sizing, visibility-at-zero, border color/width
# tracking the bar's own bar_border_color - is identical in shape to
# BlockBadge; see that file's own doc for the fuller reasoning behind
# each of those, not repeated here.

@export var vertical_overhang_px: float = 4.0
@export var badge_border_width_px: int = 3
@export var value_font_size: int = 18
@export var value_bold_strength: float = 1.0
@export var badge_content_padding_px: float = 2.0

@export var badge_fill_color: Color = Color8(185, 184, 179)
# OWN color now (2026-09-07, badge-legibility pass), NOT HudPalette.FILL
# - same literal as block_badge.gd's own badge_fill_color, independently
# declared rather than shared (this file's own header already states the
# "proven shape copied, not extracted into something shared" convention
# these two files follow generally; same reasoning applies to this
# value). HudPalette.FILL going dark (two passes: dark-fill-contrast and
# its follow-up) collapsed this badge's own fill/number contrast the
# same way it did Block's - see that file's own doc for the fuller
# story. ~0.72 standard luma, R-B ~6 before lightening below.
@export var badge_fill_lighten_amount: float = 0.3
# Unchanged value, now a named export instead of an inline 0.3 literal -
# still "Absorb reads as in block's own material family, just lighter"
# (this file's own header, point 2), just applied to badge_fill_color
# instead of HudPalette.FILL. Resulting bg: ~0.80 luma, R-B ~4 - a real
# but small value step up from Block's own 0.72/6, the "small value
# difference" this pass's own brief asks for on top of the pre-existing
# shape difference (circle vs. square).

@onready var badge_panel: Panel = $BadgePanel
@onready var value_label: Label = $ValueLabel

var _badge_style: StyleBoxFlat
var _border_color: Color = HudPalette.TROUGH
var badge_size_px: float = 34.0
# Public (not prefixed), same reason as BlockBadge's own - vitals_bar.gd
# reads this back to vertically center/position the badge against the
# bar.

func _ready() -> void:
	value_label.add_theme_font_size_override("font_size", value_font_size)
	value_label.add_theme_color_override("font_color", HudPalette.TROUGH)
	OverlayStyle.apply_to_label(value_label)
	_apply_bold(value_label, value_bold_strength)

	_apply_size(maxf(badge_size_px, _content_based_size()))

	_badge_style = badge_panel.get_theme_stylebox("panel").duplicate()
	_badge_style.bg_color = badge_fill_color.lightened(badge_fill_lighten_amount)
	_badge_style.border_color = _border_color
	_badge_style.border_width_left = badge_border_width_px
	_badge_style.border_width_top = badge_border_width_px
	_badge_style.border_width_right = badge_border_width_px
	_badge_style.border_width_bottom = badge_border_width_px
	_apply_corner_radius_for_current_size()
	badge_panel.add_theme_stylebox_override("panel", _badge_style)

	visible = false

# The one setup call vitals_bar.gd makes right after this node's own
# _ready() - same timing reasoning BlockBadge's own configure() doc
# already gives (border_color is only ever read once inside _ready()
# above, which has already run by the time a parent could touch it).
# NO corner_radius_px parameter, unlike BlockBadge's own configure() -
# this badge's own corner radius is never driven by the bar's, see this
# file's own header for why.
func configure(border_color: Color, bar_height_px: float) -> void:
	_border_color = border_color
	var height_based_size := bar_height_px + vertical_overhang_px * 2.0
	_apply_size(maxf(height_based_size, _content_based_size()))
	if _badge_style == null:
		return
	_badge_style.border_color = _border_color
	_apply_corner_radius_for_current_size()

# Same two-digit-string measurement BlockBadge's own _content_based_
# size() uses, verbatim - see that function's own doc for the full
# reasoning (measures every 10..99 string in the CURRENT font, since
# digit glyph widths aren't guaranteed uniform).
func _content_based_size() -> float:
	var font: Font = value_label.get_theme_font("font")
	var max_width := 0.0
	var max_height := 0.0
	for amount in range(10, 100):
		var text_size: Vector2 = font.get_string_size(str(amount), HORIZONTAL_ALIGNMENT_CENTER, -1, value_font_size)
		max_width = maxf(max_width, text_size.x)
		max_height = maxf(max_height, text_size.y)
	var content_extent := maxf(max_width, max_height)
	return content_extent + 2.0 * badge_border_width_px + 2.0 * badge_content_padding_px

# The public entry point - hides the whole badge at 0, otherwise shows
# the number. Identical to BlockBadge.update().
func update(amount: int) -> void:
	visible = amount > 0
	value_label.text = str(amount)

func _apply_size(size_px: float) -> void:
	badge_size_px = size_px
	custom_minimum_size = Vector2(size_px, size_px)
	size = Vector2(size_px, size_px)

# Always exactly half the CURRENT badge_size_px - a perfect circle at
# any size this badge ever resizes to, recomputed every time _apply_size()
# runs rather than set once, so a later resize (configure()'s own bar-
# height-derived size, which can differ from _ready()'s content-based
# fallback) never leaves a stale, no-longer-half radius behind.
func _apply_corner_radius_for_current_size() -> void:
	if _badge_style == null:
		return
	var radius := roundi(badge_size_px / 2.0)
	_badge_style.corner_radius_top_left = radius
	_badge_style.corner_radius_top_right = radius
	_badge_style.corner_radius_bottom_right = radius
	_badge_style.corner_radius_bottom_left = radius

# Wraps whatever font the label already resolves in a FontVariation that
# fakes bold via glyph embolden - identical technique to BlockBadge's own
# _apply_bold().
func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)
