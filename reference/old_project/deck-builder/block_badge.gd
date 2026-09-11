extends Control
class_name BlockBadge
# A small SQUARE badge: the block amount displayed as a bold number,
# no icon (see this file's own 2026-08-27 icon-removal note below). Used
# by VitalsBar (both the player's and every Enemy's HP bar), inline in
# the value row to the LEFT of the HP number - entirely hidden at 0
# rather than showing a "Block: 0" line, same "don't show a null state"
# instinct that already governs when IntentDisplay's flavor line shows
# (see intent_display.gd).
#
# MOVED off the bar itself (2026-08-27, value-row pass) - it used to
# overlay the bar's own left end, overlapping the border and clipping the
# HP number beneath it. VitalsBar now reserves a fixed slot for this in
# the value row instead (see vitals_bar.gd's own block_badge_gap_px) -
# this scene no longer decides WHERE it sits, only what it looks like.
#
# SQUARE, not round (same pass) - circles are already spoken for by the
# energy pips (pip.gd); this needed its own distinct silhouette in the
# same system-voice family as the bar itself. Colors now source from
# HudPalette/vitals_bar.gd's own bar_border_color rather than a one-off
# hardcoded blue - see configure() below - specifically INVERTED from the
# bar (bone fill, dark frame/numeral) so it reads as the same material
# family as the bar, not a copy of it.
#
# Shield icon REMOVED (2026-08-27, icon-removal pass) - at the badge's
# then-34px size, the icon crowded out the number, which is the only
# element actually carrying magnitude (position + framing already read
# as "block," the number is the only part that has to be read at a
# glance). intent_icon_defend.tscn is untouched - this only stops
# instancing a copy of it here, the real DEFEND enemy intent icon is
# unaffected.

@export var vertical_overhang_px: float = 4.0
# How far the badge extends past the bar's own top AND bottom edges (see
# configure() below, which is what actually knows bar_height_px) -
# "a small deliberate overhang," per this pass's own brief, so the badge
# reads as a plate laid on top of the bar rather than a same-height
# element wedged flush against it. Applied on BOTH edges, so the badge's
# own height is bar_height_px + 2 * this value - still a square (width
# matches), just no longer an independently-chosen size unrelated to the
# bar it sits on.

@export var badge_border_width_px: int = 3
# Bumped from a baked 2px (2026-08-27, fill-edge-tracking pass) to match
# vitals_bar.gd's own bar_border_width_px (3) - the badge reads as a
# plate belonging to the same frame family as the bar it sits on, not a
# separately-weighted element. Applied to the duplicated badge stylebox
# in _ready() below, the same "duplicate before mutating" pattern every
# other per-instance stylebox property here already uses.

@export var value_font_size: int = 18
@export var value_bold_strength: float = 1.0
# Fake-bold via FontVariation.variation_embolden (see _apply_bold()) -
# no separate bold font asset needed. Matches vitals_bar.gd's own HP
# number treatment, so the two numeric readouts read consistently.

@export var badge_content_padding_px: float = 2.0
# Breathing room between the widest two-digit number's own measured
# extent and the INSIDE of the frame (see _content_based_size() below) -
# 2026-08-27, content-aware-sizing pass. Small on purpose: this is
# margin on top of an already-real measurement, not a second fudge
# factor standing in for one - the badge_border_width_px it's added
# alongside already accounts for the frame itself.

@export var badge_fill_color: Color = Color8(185, 184, 179)
# OWN color now (2026-09-07, badge-legibility pass), NOT HudPalette.FILL
# - this file's own header above describes the badge fill as deliberately
# INVERTED from the bar ("bone fill, dark frame/numeral... reads as the
# same material family as the bar, not a copy of it"), which only held
# while HudPalette.FILL was itself pale. Two passes since (the dark-fill-
# contrast pass and its follow-up) turned FILL dark for the BAR's own
# reasons, and this badge silently inherited that - background and
# number (HudPalette.TROUGH, still dark, untouched) collapsed to near-
# zero contrast on top of a dark bar. This restores the original pale-
# plate-on-a-dark-bar read without depending on FILL staying pale ever
# again. ~0.72 standard luma, R-B ~6 - pale, barely warm, dark TROUGH
# number reads clearly on it regardless of what the bar underneath is
# doing. NOT extracted into HudPalette (absorb_badge.gd copies this same
# literal rather than sharing a reference) - matches this project's own
# "duplicated, not shared" convention for this exact pair of files (see
# absorb_badge.gd's own header).

# Outline/legibility treatment lives in OverlayStyle (see overlay_style.
# gd) - the number needs the same shared contrast treatment every other
# overlay readout uses, not its own independently-tuned copy.

@onready var badge_panel: Panel = $BadgePanel
@onready var value_label: Label = $ValueLabel

var _badge_style: StyleBoxFlat
var _corner_radius_px: int = 0
var _border_color: Color = HudPalette.TROUGH
# Sensible fallbacks before configure() below ever runs (square/dark,
# not the old hardcoded blue) - configure() is the REAL source of truth
# in practice, called once by vitals_bar.gd right after this node's own
# _ready(), but a badge that somehow never gets configured should still
# degrade to something in-family rather than an arbitrary leftover color.
var badge_size_px: float = 34.0
# Fallback square size before configure() below provides the real,
# bar_height_px-derived value - matches the badge's own old fixed size,
# not a value that matters once a real bar configures this for real.
# Public (not prefixed) because vitals_bar.gd reads this back to
# vertically center the badge against the bar - see its own doc.

func _ready() -> void:
	# Font setup MUST happen before any sizing below - _content_based_
	# size() measures value_label's own CURRENT font (bold variation
	# included), so measuring against it before the override is applied
	# would silently measure the wrong (unbolded, wrong-size) font.
	value_label.add_theme_font_size_override("font_size", value_font_size)
	value_label.add_theme_color_override("font_color", HudPalette.TROUGH)
	OverlayStyle.apply_to_label(value_label)
	_apply_bold(value_label, value_bold_strength)

	_apply_size(maxf(badge_size_px, _content_based_size()))

	# Same "duplicate the shared StyleBoxFlat before mutating it" pattern
	# as Card's rarity border - without this, tuning one badge's colors
	# would recolor every other badge sharing this scene's resource.
	_badge_style = badge_panel.get_theme_stylebox("panel").duplicate()
	_badge_style.bg_color = badge_fill_color
	_badge_style.border_color = _border_color
	_badge_style.border_width_left = badge_border_width_px
	_badge_style.border_width_top = badge_border_width_px
	_badge_style.border_width_right = badge_border_width_px
	_badge_style.border_width_bottom = badge_border_width_px
	_apply_corner_radius(_badge_style, _corner_radius_px)
	badge_panel.add_theme_stylebox_override("panel", _badge_style)

	visible = false

# The one setup call vitals_bar.gd makes right after this node's own
# _ready() (see its own _apply_bar_layout()) - corner_radius/border_color
# track the bar's own bar_corner_radius_px/bar_border_color directly (one
# shared source of truth, not a second independently-tuned copy - see
# each export's own doc for why), and size is the LARGER of two
# independent constraints (see _content_based_size() below) - block_
# badge.gd has no way to know the bar's own height on its own, which is
# what this parameter is for.
#
# CONFIRMED BROKEN (2026-08-27, content-aware-sizing pass) at the bar's
# own REAL bar_height_px (15.0, baked into enemy.tscn/player_battle_
# visual.tscn - vitals_bar.gd's own 42.0 default is not used anywhere in
# the real game and should never be the only thing a change is verified
# against): bar_height_px + 2*vertical_overhang_px alone gave 23px, with
# a 17px interior after the frame - two-digit bold text measured 22x26,
# negative margin on BOTH axes. Content size is now a real, independent
# floor under the bar-derived one, not a hardcoded guess.
func configure(corner_radius_px: int, border_color: Color, bar_height_px: float) -> void:
	_corner_radius_px = corner_radius_px
	_border_color = border_color
	var height_based_size := bar_height_px + vertical_overhang_px * 2.0
	_apply_size(maxf(height_based_size, _content_based_size()))
	if _badge_style == null:
		return
	_badge_style.border_color = _border_color
	_apply_corner_radius(_badge_style, _corner_radius_px)

# The badge's OTHER size floor: however big the widest two-digit string
# actually renders at, in value_label's own CURRENT font (bold variation
# included - this must run after _ready()'s own font setup, never
# before), plus the frame (badge_border_width_px, on both sides) plus a
# small breathing margin (badge_content_padding_px, also both sides).
# Measures EVERY two-digit string (10 through 99), not one assumed to be
# widest - digit glyph widths aren't guaranteed uniform in every font,
# and this shouldn't need revisiting if the font ever changes. Width and
# height are each maximized independently, then the LARGER of those two
# becomes the single square content extent - a badge sized to fit the
# widest STRING's width but not its own height (or vice versa) would
# still clip on whichever axis lost.
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

# The public entry point - hides the whole badge at 0 (see header
# comment above), otherwise shows the number.
func update(amount: int) -> void:
	visible = amount > 0
	value_label.text = str(amount)

# custom_minimum_size alone only matters to a Container parent - this
# node's actual parent (VitalsBar) is a plain Control, which won't resize
# us on its own, so the rect itself needs setting directly too (size, not
# just the reported minimum) or a tuned size would silently keep
# rendering at whatever was baked into block_badge.tscn. Shared by
# _ready()'s own fallback and configure()'s real, bar-derived value so
# neither path duplicates this pair of writes.
func _apply_size(size_px: float) -> void:
	badge_size_px = size_px
	custom_minimum_size = Vector2(size_px, size_px)
	size = Vector2(size_px, size_px)

# Applied to badge_panel's own stylebox - see configure()'s own doc for
# why this tracks the bar's bar_corner_radius_px rather than a hardcoded
# literal.
func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius

# Wraps whatever font the label already resolves (the project default,
# since nothing here assigns a specific font) in a FontVariation that
# fakes bold via glyph embolden - no separate bold font asset to manage.
func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)
