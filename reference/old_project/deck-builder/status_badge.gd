extends Control
class_name StatusBadge
# One active status, shown as a small circular badge - a flat-colored
# circle (StatusEffectData.icon_color, the placeholder "icon" until real
# status art/direction exists) with the magnitude overlaid as a number.
# Same visual language as BlockBadge (see block_badge.gd) - reused
# deliberately rather than a new pattern invented from scratch, per the
# brief. Noticeably smaller than BlockBadge's own default diameter
# (53px) - see vitals_bar.tscn's StatusBadgeRow, moved (2026-08-27) to
# its own compact row below the HP bar rather than inline beside it -
# several of these can be active on one combatant at once, unlike block
# (always exactly one number) or Toll (its own dedicated readout), so
# this is deliberately the smallest, most secondary indicator in the
# cluster, not competing with either for visual weight. Briefly shrunk to
# 7px the same day, when vitals_bar.gd's status row was squeezed into
# whatever tiny gap already existed before TollDisplay/FlavorLabel rather
# than getting its own space - the number was genuinely illegible at
# that size. Settled back at 18px once the row went back to pushing
# Toll/FlavorLabel down to make room for it instead (see vitals_bar.gd's
# status_row_gap_px note) - still small, still readable.
@export var badge_diameter_px: float = 18.0
@export var badge_border_color: Color = Color(0.4, 0.42, 0.48, 1)
@export var value_font_size: int = 11
@export var value_color: Color = Color(1, 1, 1, 1)
@export var value_bold_strength: float = 1.0
# Same fake-bold-via-embolden treatment as BlockBadge/VitalsBar's own
# numbers, for consistency across every vitals-cluster readout.

@onready var badge_panel: Panel = $BadgePanel
@onready var value_label: Label = $ValueLabel

var _badge_style: StyleBoxFlat
# Stashed in _ready() so set_status() can recolor bg_color later without
# re-duplicating the shared stylebox (and losing the border/corner setup
# already applied to this instance's own copy).

var _active: ActiveStatus = null
# Stashed by set_status() below - see that call site's own doc for why
# _make_custom_tooltip() needs this rather than just its for_text param.
# null until set_status() first runs (every real badge, immediately after
# instantiation - see that function's own header); a hover can't reach
# _make_custom_tooltip() before then, so this is never read null in
# practice, but every read below still guards it defensively anyway.

var _outline_width_override: int = -1
# -1 (every badge by default) means "use OverlayStyle's own shared
# outline width" - same "-1 means unset, fall through to the shared
# default" convention OverlayStyle.apply_to_label()'s own width_override
# param already uses. set_diameter_override() below is the only thing
# that ever changes this, proportionally to the enlarged diameter, so a
# bigger badge's outline doesn't end up looking proportionally THINNER
# than the standard badge's own (already-tuned-for-18px) outline.

func _ready() -> void:
	# custom_minimum_size alone only matters to a Container parent -
	# VitalsBar's StatusBadgeRow IS one (an HBoxContainer), but setting
	# size directly too costs nothing and matches BlockBadge's own
	# defensive habit, in case a future context reuses this outside a
	# Container.
	custom_minimum_size = Vector2(badge_diameter_px, badge_diameter_px)
	size = Vector2(badge_diameter_px, badge_diameter_px)
	# Centered vertically within StatusBadgeRow's full bar-height row
	# rather than stretched to fill it - see vitals_bar.tscn's Status
	# BadgeRow for the row itself.
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# PASS, not the scene's baked-in IGNORE (2026-08-29, charge-badge
	# tooltip pass) - StatusEffectData.tooltip_text (see its own doc,
	# applied below in set_status()) needs THIS control to actually
	# receive hover events for Godot's own tooltip_text mechanism to fire
	# at all. PASS rather than STOP so a badge sitting inside Enemy's much
	# larger hover_area doesn't swallow that area's own hover-driven
	# flavor-text visibility (see enemy.gd's _on_hover_area_mouse_entered/
	# exited) - both can react to the same hover moment, this badge's own
	# tooltip layering on top of whatever hover_area already does, not
	# replacing it. Harmless for every badge without tooltip_text set -
	# Godot never shows a tooltip popup for an empty string regardless of
	# mouse_filter, so this is a no-op change for every status besides the
	# one that sets it.
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Same "duplicate the shared StyleBoxFlat before mutating it" pattern
	# every other badge/card in this project uses - without this, one
	# status's color would recolor every OTHER StatusBadge sharing this
	# scene's baked-in resource.
	var badge_style: StyleBoxFlat = badge_panel.get_theme_stylebox("panel").duplicate()
	badge_style.border_color = badge_border_color
	var radius := roundi(badge_diameter_px / 2.0)
	badge_style.corner_radius_top_left = radius
	badge_style.corner_radius_top_right = radius
	badge_style.corner_radius_bottom_right = radius
	badge_style.corner_radius_bottom_left = radius
	badge_panel.add_theme_stylebox_override("panel", badge_style)
	_badge_style = badge_style

	value_label.add_theme_font_size_override("font_size", value_font_size)
	value_label.add_theme_color_override("font_color", value_color)
	OverlayStyle.apply_to_label(value_label, false, _outline_width_override)
	_apply_bold(value_label, value_bold_strength)

# Per-instance size override (2026-08-29, charge-badge legibility pass) -
# MUST be called BEFORE this instance is added to the tree (see vitals_
# bar.gd's own override_border() doc for why: badge_diameter_px/value_
# font_size/the outline width are only ever READ once, in _ready() above,
# so setting them any later would silently do nothing). VitalsBar.update_
# statuses() is the one caller, gated on StatusEffectData.badge_diameter_
# override_px (see that field's own doc) - every badge without an
# override never has this called, so every status besides Leviathan's
# charge indicator renders byte-identical to before this existed.
#
# Font size and outline width both scale PROPORTIONALLY from this one
# diameter, off the CURRENT badge_diameter_px/OverlayStyle.outline_width
# as the baseline ratio, rather than needing their own separate override
# fields - one number in, three things it visually controls together, so
# a future bigger badge can't have its numeral/outline drift out of
# proportion by only remembering to set one of the three.
func set_diameter_override(diameter_px: float) -> void:
	var scale := diameter_px / badge_diameter_px
	badge_diameter_px = diameter_px
	value_font_size = roundi(value_font_size * scale)
	_outline_width_override = roundi(OverlayStyle.outline_width * scale)

# The public entry point - one ActiveStatus in, badge fully configured.
# VitalsBar.update_statuses() rebuilds a fresh StatusBadge per active
# status every time anything changes, so this is only ever called once
# per instance, right after instantiating - see its own comment for why
# a full rebuild (rather than diffing/reusing existing badges) is fine
# for the small counts this ever deals with.
func set_status(active: ActiveStatus) -> void:
	_badge_style.bg_color = active.data.icon_color
	# See StatusEffectData.badge_border_color_override's own doc - alpha 0
	# is the every-other-status case, badge_border_color (set in _ready())
	# stays untouched.
	if active.data.badge_border_color_override.a > 0.0:
		_badge_style.border_color = active.data.badge_border_color_override
	# See StatusEffectData.badge_label_override's own doc - "" is the
	# every-other-status case, str(magnitude) exactly as before.
	value_label.text = active.data.badge_label_override if active.data.badge_label_override != "" else str(active.magnitude)
	# See StatusEffectData.badge_glyph_color_override's own doc - alpha 0
	# is the every-other-status case, value_color (set once in _ready())
	# stays untouched.
	if active.data.badge_glyph_color_override.a > 0.0:
		value_label.add_theme_color_override("font_color", active.data.badge_glyph_color_override)
	# See StatusEffectData.tooltip_text's own doc - "" is the every-other-
	# status case and shows nothing, Godot's own tooltip machinery already
	# handles that with no extra guard needed here.
	tooltip_text = active.data.tooltip_text
	# Stashed (2026-09-07, tooltip-duration pass) so _make_custom_tooltip()
	# below can append a live duration line - Godot's own _make_custom_
	# tooltip(for_text) virtual only ever hands back whatever this Control's
	# OWN tooltip_text string already is (set just above), never the
	# ActiveStatus itself, so there's no other way for that method to reach
	# turns_remaining. Rebuilt fresh every set_status() call, same "as
	# fresh as the badge itself" freshness every other per-instance field
	# here already has (update_statuses() rebuilds every badge from
	# scratch on any change - see that function's own doc).
	_active = active

func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)

# --- Tooltip (2026-08-29, tooltip-styling pass; RE-REGISTERED 2026-09-07,
# status-tooltip pass) ---
#
# Godot's default tooltip (an unstyled OS-chrome panel) was, before the
# 2026-08-29 pass, the only unstyled UI surface in the game - confirmed
# by checking the whole project for a Theme resource, a gui/theme/custom
# project setting, or a TooltipPanel/TooltipLabel theme-type override:
# none exist anywhere. Fixed here via Control._make_custom_tooltip()
# below, a per-Control virtual Godot calls INSTEAD of building its own
# default panel whenever it returns non-null - deliberately NOT a
# project-wide Theme override (the only other way to restyle the built-in
# tooltip), which would restyle every OTHER tooltip in the game too.
# Scoped to exactly this one Control: nothing anywhere else in the
# project is touched by this.
#
# Built entirely in code, no separate .tscn - same "small one-off UI, no
# reuse case for a scene file" call enemy.gd's own _play_chain_burst()
# already makes for its hit-burst circle.
#
# RE-REGISTERED (2026-09-07, status-tooltip pass) from world-voice
# (Spectral font, warm parchment panel, warm ink text - copied from
# card.gd's own frame treatment) to SYSTEM-voice. The 2026-08-29 pass
# only ever had ONE real caller - the Leviathan charge indicator's own
# flavor line ("Attempting to free itself from its chains."), a piece of
# in-world narration, which is why it was built world-voice in the first
# place (that pass's own brief called for "consistent with card frames").
# This pass makes tooltip_text a real, populated field on every ordinary
# player-facing status (Braced/Overextended/Retaliation Primed/Poison -
# see this pass's own report), and THEIR text is mechanical rules
# description, not narration - system-voice, the same register the HP
# numbers/card rules text already use. Re-registering this ONE shared
# method changes the Leviathan tooltip's own STYLING too (font/colors),
# since both uses go through the same Control method - its WORDING is
# untouched (this pass's own brief: leave the two boss statuses' strings
# alone), only how it's painted, and that's an intentional, reported
# side effect of the register genuinely being wrong for the new,
# dominant use case now.
const TOOLTIP_FONT_SIZE := 16
const TOOLTIP_BORDER_WIDTH := 2
const TOOLTIP_CORNER_RADIUS := 8
const TOOLTIP_CONTENT_MARGIN_PX := 10.0
# Border width/corner radius/margin unchanged from the 2026-08-29 pass -
# these describe panel PROPORTIONS, not register, so they didn't need to
# move with the color/font re-registration above.

const TOOLTIP_BG_COLOR := Color(0.88, 0.89, 0.91, 1)
const TOOLTIP_BORDER_COLOR := Color(0.68, 0.7, 0.74, 1)
# A plain pale neutral, cool rather than warm (no card-parchment
# undertone) - "dark text on a pale panel," per this pass's own brief,
# just with the family swapped from card-frame warmth to a plain system
# neutral. Local consts, not a new HudPalette entry - HudPalette has no
# pale-panel token today (its own palette leans dark/muted throughout,
# by design - see hud_palette.gd's own header), and inventing one for a
# single caller isn't warranted; TOOLTIP_TEXT_COLOR below DOES read an
# existing HudPalette token directly, since the exact right one already
# exists there.
#
# No font override at all now (was Spectral-Regular.ttf) - "the muted
# sans used by HP numbers," per this pass's own brief, means the PROJECT
# DEFAULT font: vitals_bar.gd's own value_label never assigns a font
# either (see its own _apply_bold() doc: "wraps whatever font the label
# already resolves"), only size/bold - so matching it means leaving
# font alone here too, not preloading a specific system-sans file that
# doesn't exist in this project.
func _make_custom_tooltip(for_text: String) -> Object:
	var label := Label.new()
	label.text = _tooltip_body(for_text)
	label.add_theme_font_size_override("font_size", TOOLTIP_FONT_SIZE)
	# HudPalette.SYSTEM_TEXT, read directly (2026-09-07) - "the muted-but-
	# legible floor for system-voice text" per that entry's own doc,
	# already the established token for exactly this register (card.gd's
	# own rules text reads it the same direct way). Not a local copy -
	# same "direct-read consumer, no local @export mirroring" convention
	# every other HudPalette consumer in this project already follows.
	label.add_theme_color_override("font_color", HudPalette.SYSTEM_TEXT)

	var style := StyleBoxFlat.new()
	style.bg_color = TOOLTIP_BG_COLOR
	style.border_color = TOOLTIP_BORDER_COLOR
	style.set_border_width_all(TOOLTIP_BORDER_WIDTH)
	style.set_corner_radius_all(TOOLTIP_CORNER_RADIUS)
	style.content_margin_left = TOOLTIP_CONTENT_MARGIN_PX
	style.content_margin_right = TOOLTIP_CONTENT_MARGIN_PX
	style.content_margin_top = TOOLTIP_CONTENT_MARGIN_PX
	style.content_margin_bottom = TOOLTIP_CONTENT_MARGIN_PX

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(label)
	return panel

# The description (for_text - whatever this Control's own tooltip_text
# currently is, same string set_status() set) plus a duration line below
# it (2026-09-07, status-tooltip pass) - "the same line or the line
# below," per this pass's own brief; below reads cleaner at this small a
# panel width than cramming both onto one line. Skips the duration line
# entirely if _active is somehow unset (defensive only - see that var's
# own doc for why this shouldn't be reachable in practice).
func _tooltip_body(for_text: String) -> String:
	if _active == null:
		return for_text
	return "%s\n%s" % [for_text, _format_duration(_active.turns_remaining)]

# Never prints a raw sentinel (2026-09-07, status-tooltip pass, this
# pass's own brief) - DURATION_UNTIL_REMOVED/DURATION_UNTIL_TRIGGERED
# (see StatusEffectData's own doc on both) are named sentinels, not real
# counts, so they get their own fixed sentences instead of str()'d
# straight into the label. Singular "1 turn" vs. plural "N turns" -
# everything else in this project's own numeric UI (card costs, HP,
# block) is a plain int with no pluralization rule, but a duration is
# read as a SENTENCE here ("2 turns" is a phrase, not a bare readout the
# way a cost badge's "3" is), so it gets the grammar a sentence needs.
func _format_duration(turns_remaining: int) -> String:
	match turns_remaining:
		StatusEffectData.DURATION_UNTIL_REMOVED:
			return "Until removed."
		StatusEffectData.DURATION_UNTIL_TRIGGERED:
			return "Until triggered."
		1:
			return "1 turn"
		_:
			return "%d turns" % turns_remaining
