extends Control
class_name VitalsBar
# A combatant's HP readout: a ProgressBar with the "current/max" number
# embedded directly in the bar (no separate label above or below), plus
# a BlockBadge (see block_badge.gd) overlaid at the bar's left end when
# block is nonzero. Shared by the player (battle's UI, and the field
# HUD with the badge hidden - there's no such thing as block outside a
# fight) AND every Enemy (see enemy.gd/enemy.tscn) - "one asset, not
# two," the same reasoning DESIGN.md's enemy silhouette note already
# applies to shapes, extended to this. Same "the caller owns the actual
# numbers, this script only displays what it's told" split Enemy's
# other displays already follow - callers push values in via
# update_hp()/update_block(), or (for a caller that just wants "whatever
# RunState currently says" with no per-change bookkeeping of its own -
# see field_room.gd) refresh_from_run_state() pulls straight from the
# one place player HP actually lives. Either way, this script owns how
# a CHANGE looks: a short tween instead of an instant snap, and a color
# shift once HP drops below a threshold.

@export var show_block: bool = true
# Block only exists mid-battle (see battle.gd's local `player_block` -
# RunState has no notion of it, it resets to 0 every fight). The field
# HUD sets this false so a resting player's bar can never show a badge
# for a resource that isn't in play out there, even defensively.

@export var show_rally_pool: bool = false
# The Wanderer's Rally passive (see battle.gd's rally_pool doc) is
# player-only and battle-only - no enemy has it, and the field HUD's
# own VitalsBar instance isn't mid-fight either. False by default (this
# same script is Enemy's own visual too - see this file's own header),
# flipped true only by whichever instance is actually the player's
# battle vitals bar (player_battle_visual.tscn). Gates RallyOverlay's
# visibility once, in _ready() below, and every update_rally_pool()/
# drain_rally_pool()/reset_rally_pool() call as a defensive no-op on
# top of that - an enemy's bar (or the field HUD's) can never end up
# rendering an always-empty segment, because nothing here ever makes
# RallyOverlay visible for it in the first place.

@export var bar_height_px: float = 42.0

@export var fill_color: Color = HudPalette.FILL
# The bar's own normal-state fill (2026-09-07, player/enemy-split pass) -
# NEW per-instance @export, replacing a hardcoded HudPalette.FILL read at
# both call sites below (_ready()'s initial paint, _update_low_hp_state()'s
# "no longer low" branch). Defaults to HudPalette.FILL so every instance
# that doesn't override this (every Enemy, the field HUD's own bar) keeps
# reading the shared palette value exactly as before - this export only
# exists so ONE instance can differ. Same mechanism show_rally_pool above
# already uses to be true on exactly one VitalsBar instance (player_
# battle_visual.tscn's own scene override) and false everywhere else -
# battle.gd's own "player and enemy share this component" design didn't
# need touching, just one more property that scene is free to override.
# player_battle_visual.tscn overrides this to a dark desaturated red;
# every enemy and the field HUD stay on the HudPalette.FILL default.
# Block/Absorb badges (block_badge.gd/absorb_badge.gd) read HudPalette.
# FILL directly, NOT this export - they stay on the shared neutral value
# regardless of which VitalsBar they're attached to, which is exactly
# why they don't turn red on the player's own bar.

@export var low_hp_threshold: float = 0.3
# Below this fraction of max HP, the bar switches to low_hp_color and
# (if enabled) pulses - "immediately obvious at a glance that you're in
# danger."

@export var low_hp_color: Color = Color8(255, 55, 55)
# REVERSED (2026-09-07, low-HP-value-separation pass) from (0.55, 0.05,
# 0.05, 1) - that value was tuned darker-than-fill back when the resting
# fill was a pale off-white (HudPalette.FILL's old #E6D4BA, see this
# export's own prior doc); the fill has since gone dark on both sides
# (player's own fill_color and the shared HudPalette.FILL default - see
# both their own docs), so a low-HP color ALSO darker than the resting
# fill collapsed to near-zero value separation (0.24 luma against the
# player fill's 0.2195, a 0.02 gap) - the state was signaling by
# saturation alone, which reads weakly in peripheral vision. This value
# goes the other way: LIGHTER than any resting fill instead of darker,
# so low HP means the bar visibly brightens, not just reddens.
#
# H=0 (pure red, G=B - same hue family as before, unchanged) at V=1.0
# (maxed - required to reach the luma target below at all; see the math
# this forces). Target was ~0.45 standard luma at max saturation: solving
# luma = V*(0.299 + 0.701*(1-S)) for S at V=1, luma=0.45 gives S=0.7843
# (down from the old 0.9091 - V=1 is the ceiling, so hitting a fixed
# luma at max V is what sets S, not a free choice). Still "high"
# saturation (~78%), just not the absolute max anymore - the trade this
# pass takes deliberately: real value separation over marginally more
# saturation. Measured: (255, 55, 55), standard luma 0.450, R-B = 200.
@export var value_font_size: int = 20
# Was 27 (2026-08-26 fix) - wide enough that "100/100"-scale text
# already overflowed a three-enemy or debris-spawned bar's own width
# (bar_width_px scaled down by battle.gd's three_enemy_scale_factor/
# DEBRIS_SPAWN_CLUSTER_WIDTH_SCALE - see enemy.gd's own bar_width_px
# doc), making the bar read as a backing plate for oversized text
# rather than a gauge the fill dominates. 20 was verified headlessly
# (measuring this exact FontVariation, embolden included, via Font.
# get_string_size()) to fit even a hypothetical "100/100" - already
# wider than any current enemy's real max_hp - inside 88px, the
# narrowest bar this game can actually produce today (a debris-spawned
# newcomer's own scaled-down cluster).

@export var low_hp_pulse_enabled: bool = true
@export var low_hp_pulse_alpha_dip: float = 0.35
@export var low_hp_pulse_period_sec: float = 0.9

@export var tween_duration_sec: float = 0.25
# ~0.25s per spec - long enough that a hit visibly drains rather than
# snapping, short enough to still feel responsive to the card/intent that
# caused it.

@export var rally_pool_saturation_scale: float = 0.7
# How much of the HP fill color's saturation RallyOverlay keeps (see
# _desaturate()) - derived from whichever fill color is currently active
# (HudPalette.FILL or low_hp_color, tracked automatically in _apply_bar_
# color()), not a plain alpha fade. Per this feature's own brief: alpha
# alone would read as a rendering artifact (a translucent glitch over
# the background), not an intentional "this HP is recoverable" state.
#
# NOT sufficient on its own against either fill color (2026-08-27,
# HudPalette pass) - desaturating while holding Value fixed makes a
# color LIGHTER (the non-dominant channels rise toward the unchanged
# max), not darker. See rally_value_scale below, applied alongside this
# in _apply_bar_color(), for the fix.
#
# RAISED from 0.35 (2026-08-27, Rally-warmth pass) - at 0.35, against
# HudPalette.FILL specifically (already low-saturation, a warm off-white
# whose own S is only ~0.13), stripping saturation further left almost
# nothing of the fill's hue behind: the result read as neutral grey, a
# different SUBSTANCE from the fill rather than the same one dimmed. 0.7
# keeps the derived saturation much closer to each fill's own (S'=0.092
# against FILL, S'=0.636 against low_hp_color) - both results now keep a
# real, visible hue tied to whichever fill is active, closing the
# "grey seam" complaint this pass exists to fix.

@export var rally_value_scale: float = 0.5
# Scales HSV Value down, applied AFTER _desaturate() above, within the
# same _apply_bar_color() call - see that function's own doc for why
# BOTH steps are required together. Retuned to 0.5 alongside rally_pool_
# saturation_scale's own raise above (2026-08-27, Rally-warmth pass) -
# the two values are coupled: raising saturation retention alone (without
# revisiting this) would have left Rally too CLOSE to the fill itself
# (a higher-saturation result is also a brighter one at a fixed Value),
# so this needed its own re-check, not just a carry-over from the
# previous 0.45.
#
# 0.5 was solved against the TIGHTER of the two bands, not eyeballed
# directly: at low HP, low_hp_color's own luminance (0.200) sits only
# 0.088 above TROUGH's (0.111) - a much narrower gap than the normal-HP
# band (FILL at 0.858, a 0.746-wide gap) - so low HP is the binding
# constraint on how much daylight Rally
# can actually get on both sides at once. 0.5 lands Rally's derived
# luminance at ~0.152 there, roughly centered (0.047 below low_hp_color,
# 0.041 above TROUGH) rather than skewed toward either edge. The normal-
# HP band is wide enough that the same 0.5 leaves generous clearance
# there too (derived luminance ~0.434, versus FILL's 0.858 and TROUGH's
# 0.111). Retune both this and rally_pool_saturation_scale TOGETHER if
# either fill color changes - they were solved as a pair, not
# independently.

@export var rally_expire_drain_duration_sec: float = 0.6
# Deliberately longer than tween_duration_sec - unlike a recovery
# (synced to the ordinary HP tween, so it reads as "reclaimed") or a
# fill (synced the same way, so it reads as "this is what I just
# lost"), THIS is the one animation whose whole job is to be noticed:
# it's what teaches a player the Rally window exists and expires. Per
# spec: "noticeable but quick," not a slow fade that blends into
# ambient motion.

@export var block_badge_edge_offset_px: float = 0.0
# Horizontal nudge on top of the badge's own fill-edge anchor (see
# _process() below) - block is temporary HP that sits in front of real
# HP and depletes first, so the badge's RIGHT edge tracks hp_bar's own
# fill/trough boundary directly rather than a fixed offset from the
# bar's edge (2026-08-27, fill-edge-tracking pass - REPLACES the old
# block_badge_overlap_px, a static "sits on the bar's left end"
# position that had nothing to do with what block actually represents).
# 0.0 means the badge's right edge sits exactly AT the fill edge; a
# nonzero value shifts that anchor point left/right for fine-tuning by
# eye, without changing the underlying tracking math.

@export var absorb_badge_gap_px: float = 4.0
# The gap between block_badge's own right edge and absorb_badge's left
# edge, when both are visible (2026-09-05, Forbearance pass) - see
# _process()'s own extended fill-edge tracking below. When block is 0
# and hidden, absorb takes block's own anchored slot directly instead
# (no gap to apply) - the two badges never both claim the same slot.

@export var hp_label_offset_y: float = 4.0
# Vertical gap between the bar's BOTTOM edge and ValueLabel below it
# (2026-08-27, HP-label reposition pass - replacing the old centered-
# over-the-bar placement). Defaults to status_row_gap_px's own value
# (the closest existing "bar-bottom to next-row-below" precedent in this
# same component - see that export's own doc) rather than anything
# TOLL-related: TOLL no longer positions itself off this bar at all (it
# moved into PlayerResourceCluster - see player_battle_visual.gd), so
# there's no TOLL-relative gap to actually match here. A separate export
# from status_row_gap_px on purpose - the two rows below the bar (this
# label, then StatusBadgeRow) may want different breathing room once
# both are seen live, and tying them together would prevent that.

@export var status_row_gap_px: float = 4.0
# Vertical gap between ValueLabel's own BOTTOM edge and StatusBadgeRow
# below it (see status_badge.gd) - 2026-08-27 rework, moved from inline-right-of-
# the-bar (which read as competing with Block/Toll for the same visual
# weight) to its own compact row underneath instead, left-aligned with
# the bar's own left edge.
#
# Went back and forth on this the same day: growing vitals_bar.size.y to
# cover the row (so PlayerBattleVisual's TollDisplay/Enemy's FlavorLabel,
# which both position off bar_top_px + vitals_bar.size.y, shift down to
# make room) was reverted once because it moved Toll further than
# wanted - but that meant squeezing the row into whatever tiny gap
# already existed (Enemy's FlavorLabel only leaves 8px), which forced
# badges down to an illegible 7px. Given that trade-off explicitly, the
# row keeps its own space after all: vitals_bar.size.y grows again (see
# _ready() below), Toll/FlavorLabel shift down by status_row_gap_px +
# status_badge_row_height_px to make room, and the badges get to be
# actually readable again.
@export var status_badge_row_height_px: float = 18.0
# The row's own reserved height - StatusBadge instances center within it
# (see status_badge.gd's own size_flags_vertical note), so this only
# needs to be at least as tall as StatusBadge.badge_diameter_px. Not read
# live from a StatusBadge instance (unlike block_badge's own size, read
# live off the always-present @onready block_badge directly - see
# _process() below) because
# nothing here is always-present to read - StatusBadgeRow's own children
# are created on demand by update_statuses(), so this is tuned by eye to
# match status_badge.gd's own badge_diameter_px instead, not derived
# from it.

# --- Legibility (DECIDED - see chat: HP bar/block badge polish pass) ---
#
# A ProgressBar's fill draws opaque across its own current width, which
# covers most (at high HP, effectively all) of the background stylebox's
# own border underneath it - in practice the bar read as a flat colored
# rectangle rather than a bordered object. BarBorder (see vitals_bar.
# tscn) is a separate, border-only overlay drawn on TOP of both
# background and fill, so the edge stays visible regardless of the
# current HP fraction.
@export var bar_trough_alpha: float = 0.85
# The trough's own alpha - a LOCAL override on this instance's own
# duplicated trough stylebox (see the "duplicate before mutating" note
# where trough_style is built), NOT a change to HudPalette.TROUGH's own
# alpha: TROUGH is also read by map_screen.gd, which documents ALWAYS
# full alpha as a hard requirement there ("never transparent, so the
# map's connection lines never show through a dimmed node") - dropping
# TROUGH's own alpha would have silently broken that. This gets the same
# "low-alpha dark" read for the trough alone by only ever touching this
# per-instance copy, still sourced live from TROUGH's own RGB (see
# trough_style's own build below) so a retune of TROUGH's color still
# reaches here automatically - only the opacity is instance-local.
# RAISED from 0.5 (2026-09-07, dark-fill-contrast pass) - once the fill
# itself went dark (see fill_color's own doc), a half-transparent trough
# let the empty portion of the bar read as bare ground showing through
# rather than as the bar's own container. 0.85 keeps SOME translucency
# (still visibly a trough, not a fourth opaque plate stacked on the
# scene) while reading as a contained object at any fill fraction.
@export var bar_border_color: Color = HudPalette.TROUGH
# A LIVE read now (2026-09-05, HUD palette-alignment pass) - REPLACES a
# hardcoded Color(0.117647, 0.109804, 0.101961) literal that was only
# ever a copy-pasted snapshot of HudPalette.TROUGH's own value (2026-08-27,
# border-weight pass), not an actual reference to it - retuning TROUGH
# would have silently left this default behind, still "near-black" but no
# longer the SAME near-black. Behavior-identical: HudPalette.TROUGH's
# exported value is exactly this same number today, so nothing on screen
# changes: every non-compact instance (every enemy bar, the battle
# player bar) still renders byte-identical to before this pass. Still a
# real per-instance @export, not a direct-read-at-point-of-use the way
# FILL/TROUGH themselves are (see hud_palette.gd's own convention doc) -
# the border specifically needs to lighten per-context against some
# backdrops (the field HUD's own compact override to HudPalette.
# SYSTEM_TEXT, see run_hud.gd's own override_border() call, is exactly
# that case), which is what an @export default (rather than a hardcoded
# read at the call site) still exists to allow.
@export var bar_border_width_px: int = 3
# Raised from 2 (2026-08-27, border-weight pass) - at full HP the fill
# covers the bar's ENTIRE width, so BarBorder's own outline is the ONLY
# thing defining the bar's edge against the backdrop (see this pass's
# own brief: bone fill on pale ground read as a faint outline at the old
# weight). Capped at 3, not pushed further, by hp_label_offset_y's own
# 4px gap below the bar (see _apply_border_geometry() below for why this
# value also controls how far BarBorder now extends past the bar's own
# bounds) - leaves a 1px margin rather than running the two flush.

@export var bar_corner_radius_px: int = 0
# Squares off the bar entirely (2026-08-27, border-weight pass) -
# RallyOverlay's own stylebox already has no corner radius set (defaults
# to 0), so this doesn't newly introduce a mismatch there, it was already
# square. Applied to the fill/trough/border styleboxes (see
# _apply_corner_radius() below, called on all three in _ready()) rather
# than baked into vitals_bar.tscn's own three StyleBoxFlat sub-resources
# by hand - reversible by retuning this one export.

@export var value_bold_strength: float = 0.5
# Fake-bold via FontVariation.variation_embolden (see block_badge.gd's
# own _apply_bold(), the same technique). Pulled back from 1.0 (Battle
# vitals typography pass) - HP is persistent, lower-frequency context
# next to intent's per-turn, higher-urgency number (see intent_display.
# gd's own value_bold_strength, now the stronger of the two at that same
# 1.0 reference) - still legibly bold, just not competing with intent for
# visual weight. Shared by both the player's HP bar and every enemy's
# (this is the one VitalsBar script both instance), so the hierarchy
# holds on both sides of the battle screen automatically.

const STATUS_BADGE_SCENE := preload("res://status_badge.tscn")

@onready var hp_bar: ProgressBar = $HPBar
@onready var bar_border: Panel = $BarBorder
@onready var value_label: Label = $ValueLabel
@onready var block_badge: BlockBadge = $BlockBadge
@onready var absorb_badge: AbsorbBadge = $AbsorbBadge
@onready var status_badge_row: HBoxContainer = $StatusBadgeRow
@onready var rally_overlay: Panel = $RallyOverlay

var _fill_style: StyleBoxFlat
var _rally_style: StyleBoxFlat
var _hp_tween: Tween
var _rally_tween: Tween
var _pulse_tween: Tween
var _is_low_hp: bool = false
var _has_shown_hp: bool = false
# False until the first update_hp() call - that first call (a fresh
# battle showing whatever HP carried over from the run) should SNAP into
# place, not visibly tween up from an empty/default bar. Every call after
# that tweens normally.

func _ready() -> void:
	# Any overlay that pauses the tree while sitting over a bar this
	# script owns (the field HUD's own HP bar behind ShopWindow/
	# DeckViewer/MapScreen, or a battle HP bar behind battle's own in-
	# fight DeckViewer) would otherwise leave update_hp()'s _hp_tween/
	# _start_pulse()'s _pulse_tween frozen mid-animation - the printed
	# number in update_hp() is set synchronously and would still read
	# correctly, but the BAR ITSELF would visibly stall at its old fill
	# level until the overlay closes, reading as "nothing happened" even
	# though it did. ALWAYS is the same fix ShopWindow/DeckViewer already
	# use to stay interactive under their own pause (see shop_window.gd's
	# own _ready()) - a tween bound to a node only pauses if that node's
	# OWN effective process mode does, regardless of how many paused
	# ancestors sit above it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Same "duplicate the shared StyleBoxFlat before mutating it" pattern
	# as Card's rarity border (see card.gd's _update_rarity_border()) -
	# without this, recoloring one bar for a low-HP warning would recolor
	# every OTHER Control sharing this scene's fill resource too.
	_fill_style = hp_bar.get_theme_stylebox("fill").duplicate()
	_apply_corner_radius(_fill_style, bar_corner_radius_px)
	hp_bar.add_theme_stylebox_override("fill", _fill_style)
	_rally_style = rally_overlay.get_theme_stylebox("panel").duplicate()
	rally_overlay.add_theme_stylebox_override("panel", _rally_style)
	_apply_bar_color(fill_color)

	# Same "duplicate before mutating" pattern as the fill stylebox above
	# (2026-08-27, HudPalette pass) - HPBar's own "background" stylebox
	# (the trough) had no code path touching it before this; a straight
	# theme override to HudPalette.TROUGH is all it needs, since unlike
	# fill/low-HP it never changes at runtime. RGB still reads TROUGH
	# live; only alpha is overridden per-instance (see bar_trough_alpha's
	# own doc for why that split, not a TROUGH.a change, is required).
	var trough_style: StyleBoxFlat = hp_bar.get_theme_stylebox("background").duplicate()
	trough_style.bg_color = Color(HudPalette.TROUGH.r, HudPalette.TROUGH.g, HudPalette.TROUGH.b, bar_trough_alpha)
	_apply_corner_radius(trough_style, bar_corner_radius_px)
	# Zeroed (2026-08-27, single-border pass) - this stylebox's own baked
	# border (a cool grey, unrelated to BarBorder's dark stroke) predates
	# BarBorder entirely: BarBorder was built specifically to REPLACE it
	# (see this file's own "Legibility" section above - the background
	# stylebox's border is "otherwise hidden under the fill," which is
	# exactly why a separate always-visible overlay was needed), but this
	# one was never actually zeroed when that happened. Only ever visible
	# in the unfilled portion of the bar - at anything under 100% HP it
	# read as a second, grey inner frame around the trough/Rally area,
	# distinct from BarBorder's own frame around the whole component.
	# hp_fill/rally_fill carry no border of their own (never set, default
	# 0) - confirmed, not touched here.
	trough_style.border_width_left = 0
	trough_style.border_width_top = 0
	trough_style.border_width_right = 0
	trough_style.border_width_bottom = 0
	hp_bar.add_theme_stylebox_override("background", trough_style)

	_apply_border_style()

	hp_bar.offset_bottom = bar_height_px

	# RallyOverlay sits on TOP of HPBar (see this scene's own node order)
	# so its desaturated fill draws over HPBar's idle background instead
	# of being hidden underneath it, but BELOW BarBorder so the bar's
	# outer border edge still reads on top of it - same "separate overlay
	# so the border survives regardless of fill state" reasoning
	# BarBorder's own doc above already established for HPBar's fill.
	# anchor_left/anchor_right (not offsets) are what update_rally_pool()/
	# drain_rally_pool()/reset_rally_pool() below actually animate, since
	# they encode the segment's boundaries as FRACTIONS of this bar's own
	# width - same responsive-to-any-bar_width_px shape anchor_right=1.0
	# already gives HPBar/BarBorder, just with the left edge free to move
	# too. Starts collapsed (both anchors at 0.0, left edge) - the first
	# real update_rally_pool() call (from _start_battle() via battle.gd's
	# _update_player_panel(), same "no visible pop-in tween" territory
	# _has_shown_hp guards for the HP bar itself) positions it for real.
	rally_overlay.anchor_left = 0.0
	rally_overlay.anchor_right = 0.0
	rally_overlay.offset_left = 0.0
	rally_overlay.offset_right = 0.0
	rally_overlay.offset_top = 0.0
	rally_overlay.offset_bottom = bar_height_px
	rally_overlay.visible = show_rally_pool
	value_label.add_theme_font_size_override("font_size", value_font_size)
	OverlayStyle.apply_to_label(value_label)
	_apply_bold(value_label, value_bold_strength)

	# Below the bar, left-aligned with its own left edge (2026-08-27,
	# HP-label reposition pass - replacing the old centered-over-the-bar
	# placement). horizontal_alignment is LEFT now (see vitals_bar.tscn's
	# own baked property) - the label's anchor_left=0/anchor_right=1.0
	# span is untouched from before, so left-aligning the TEXT within
	# that same span is all "left edge at the bar's left edge" needs, no
	# anchor changes required. Height is MEASURED via Font.get_height()
	# at value_font_size, read AFTER the bold FontVariation override just
	# above is already applied (same technique toll_display.gd's own
	# _layout_row() uses, and for the same reason - guessing this number
	# is exactly the bug class that clipped Toll's own value label once
	# already, per that function's own doc).
	var hp_label_font: Font = value_label.get_theme_font("font")
	var hp_label_height: float = hp_label_font.get_height(value_font_size)
	value_label.offset_top = bar_height_px + hp_label_offset_y
	value_label.offset_bottom = value_label.offset_top + hp_label_height

	# configure() sizes the badge off THIS bar's own bar_height_px (see
	# block_badge.gd's own doc - it has no way to know that on its own)
	# before anything below reads the resulting badge_size_px back.
	block_badge.configure(bar_corner_radius_px, bar_border_color, bar_height_px)
	# absorb_badge.gd's own configure() takes no corner_radius_px - it
	# always renders as a circle, independent of the bar's own corner
	# radius setting (see that file's own doc for why).
	absorb_badge.configure(bar_border_color, bar_height_px)

	# Vertically centered on the bar - see block_badge.gd for its own
	# size/color tuning. Horizontal position is NOT set here - it tracks
	# the HP fill's leading edge every frame instead (see _process()
	# below), since block is temporary HP that moves as the fill does,
	# not a fixed decoration. badge_size_px includes vertical_overhang_px
	# on both edges already (see block_badge.gd's own doc), so this keeps
	# that overhang exactly as before - only the X axis changed.
	block_badge.position.y = (bar_height_px - block_badge.badge_size_px) / 2.0
	absorb_badge.position.y = (bar_height_px - absorb_badge.badge_size_px) / 2.0

	if not show_block:
		block_badge.visible = false

	# This node's own total footprint is the bar PLUS ValueLabel PLUS
	# StatusBadgeRow, stacked (see status_row_gap_px's own note for the
	# earlier back-and-forth that established "grow this rather than
	# squeeze rows into whatever gap already existed"). Enemy's
	# FlavorLabel positions itself off THIS value (bar_top_px + vitals_
	# bar.size.y + its own gap), so growing it here is what pushes it
	# down to make room - that file needs no change of its own for that
	# to happen.
	#
	# absorb_badge does NOT extend this formula (2026-09-05, Forbearance
	# pass, confirmed rather than assumed) - like block_badge, it's
	# vertically centered WITHIN bar_height_px (see its own position.y
	# assignment above), not stacked below the bar the way ValueLabel/
	# StatusBadgeRow are. Neither badge has ever contributed to this
	# height calculation, and adding a second one alongside the first
	# doesn't change that.
	var total_height := value_label.offset_bottom + status_row_gap_px + status_badge_row_height_px
	custom_minimum_size = Vector2(custom_minimum_size.x, total_height)
	# custom_minimum_size alone only matters to a Container parent (same
	# gotcha as block_badge.gd's own _ready()) - this node's actual
	# parent is a plain Control in every context that uses it (battle's
	# UI, the field HUD, Enemy), so the rect's real height needs setting
	# directly too. Width is left alone here on purpose - it's owned by
	# whoever instances this (a caller's own offsets, or Enemy's
	# _apply_layout() setting size.x once this returns), not by this
	# component itself.
	size.y = total_height

	# Below the value row now (2026-08-27, HP-label reposition pass - was
	# directly below the bar before ValueLabel moved into this same
	# stack), left-aligned with its own left edge (2026-08-27,
	# replacing the old inline-right-of-the-bar placement) - anchored to
	# the LEFT (0.0) rather than the right, offset_left = 0 puts its own
	# left edge exactly at the bar's, and it still grows rightward
	# (grow_horizontal, unchanged) as update_statuses() adds badges.
	status_badge_row.anchor_left = 0.0
	status_badge_row.anchor_right = 0.0
	status_badge_row.offset_left = 0.0
	status_badge_row.offset_right = 0.0
	status_badge_row.offset_top = value_label.offset_bottom + status_row_gap_px
	status_badge_row.offset_bottom = status_badge_row.offset_top + status_badge_row_height_px

# Builds BarBorder's stylebox + geometry from bar_border_color/bar_
# border_width_px's CURRENT values - split out of _ready() (2026-08-27,
# field-HUD quieting pass) purely so override_border() below can re-run
# the exact same logic later, not a behavior change on its own (_ready()
# still calls this once, same as before the split).
func _apply_border_style() -> void:
	var border_style: StyleBoxFlat = bar_border.get_theme_stylebox("panel").duplicate()
	border_style.border_color = bar_border_color
	border_style.border_width_left = bar_border_width_px
	border_style.border_width_top = bar_border_width_px
	border_style.border_width_right = bar_border_width_px
	border_style.border_width_bottom = bar_border_width_px
	_apply_corner_radius(border_style, bar_corner_radius_px)
	bar_border.add_theme_stylebox_override("panel", border_style)

	# BarBorder's rect extends bar_border_width_px PAST HPBar's own bounds
	# on all four sides (2026-08-27, border-weight pass) rather than
	# sharing HPBar's exact rect (border stroke eating inward into
	# whatever HPBar was showing underneath). The stroke width above is
	# set to this SAME bar_border_width_px, so it occupies exactly this
	# outward margin: the stroke's OUTER edge lands at BarBorder's
	# (expanded) rect edge, its INNER edge lands exactly at HPBar's
	# original, unchanged edge - the fill/trough's own visible area is
	# untouched by this. anchor_right stays 1.0 (baked in vitals_bar.tscn)
	# so this remains responsive to whatever bar_width_px the owner sets.
	bar_border.offset_left = -bar_border_width_px
	bar_border.offset_top = -bar_border_width_px
	bar_border.offset_right = bar_border_width_px
	bar_border.offset_bottom = bar_height_px + bar_border_width_px

# The per-context override path bar_border_color/bar_border_width_px's
# own doc already anticipated ("the border specifically needs to lighten
# per-context against some backdrops, which is a per-instance override,
# not a palette-wide change") but couldn't actually reach on its own:
# both exports are only ever READ once, inside _ready() above, which (as
# a child) has already run by the time any PARENT's own _ready() gets a
# chance to touch this instance - setting the bare export from outside
# after that point would silently do nothing, since nothing re-reads it.
# This re-applies them live instead (2026-08-27, field-HUD quieting pass
# - see run_hud.gd's own compact-mode doc, its one caller today).
#
# Purely additive: sets the two exports, then calls the exact same
# _apply_border_style() _ready() already calls once - no default value
# changed, no behavior changed for any instance that never calls this
# (every combat bar, Enemy's own, included), so those render byte-
# identical to before this existed.
func override_border(color: Color, width_px: int) -> void:
	bar_border_color = color
	bar_border_width_px = width_px
	_apply_border_style()

# The per-instance row-height override path (2026-08-29, charge-badge
# legibility pass) - same "only ever read once, in _ready(), so a plain
# export assignment from outside does nothing after the fact" problem
# override_border() above already solved for bar_border_color/bar_
# border_width_px, same fix shape: re-run the handful of _ready() lines
# that actually depend on status_badge_row_height_px (see that field's
# own doc), not the WHOLE of _ready() again. Purely additive - no default
# changed, no behavior changed for any instance that never calls this
# (every enemy besides a Charge-boss, and the player's own bar, all
# included), so those render byte-identical to before this existed.
#
# Called once, at spawn (see enemy.gd's own EnemyData.status_badge_row_
# height_override_px read), NOT toggled on/off as a charge window opens
# and closes - a STATIC per-boss reservation, not a dynamic one. Leaving
# the row this tall even outside a charge window (empty space under the
# HP bar with no badges in it) was the deliberate simpler choice over
# reflowing this live: nothing else is positioned relative to THIS row's
# bottom edge for an enemy (see enemy.gd's own vitals_bar.size.y read,
# which only sizes Enemy's own outer footprint - unlike the player's
# equivalent cluster, no sibling element like TollDisplay depends on this
# exact edge for an enemy), so reflowing on every phase transition would
# only trade a moment of layout jank for zero actual benefit.
func override_status_badge_row_height(height_px: float) -> void:
	status_badge_row_height_px = height_px
	var total_height := value_label.offset_bottom + status_row_gap_px + status_badge_row_height_px
	custom_minimum_size = Vector2(custom_minimum_size.x, total_height)
	size.y = total_height
	status_badge_row.offset_bottom = status_badge_row.offset_top + status_badge_row_height_px

# --- Compact value style (vitals-strip pass, 2026-08-27; moved outside
# the bar, 2026-09-05) ---
#
# Originally moved ValueLabel INSIDE the bar - left-aligned, vertically
# centered, small - instead of its own row beneath it, for a caller that
# wants a much shorter bar with the number embedded directly in it
# (run_hud.gd's compact mode, its one caller today). REVISED (2026-09-05,
# explicit ask): the label now sits OUTSIDE the bar, immediately to its
# right, instead of inside it - left_inset_px is now the gap from the
# bar's own right edge to the label's left edge, not an inset from the
# bar's own left edge. Purely additive and opt-in, same shape as
# override_border() right above: does nothing unless called, so every
# other instance (every combat bar, Enemy's own) renders byte-identical
# to before this existed.
var _compact_mode: bool = false
var _compact_over_fill_color: Color = Color(1, 1, 1, 1)
var _compact_over_trough_color: Color = Color(1, 1, 1, 1)
# Both default to the same (arbitrary, never-read-unless-compact) white -
# real values only ever come from apply_compact_value_style() below.

# bar_height_px is, like bar_border_color before it, only ever READ once
# inside _ready() above - already run, as a child, before any parent's
# _ready() could touch it. This re-applies it live (rebuilding HPBar/
# BarBorder's geometry via _apply_border_style(), which already reads
# bar_height_px fresh).
#
# over_fill_color/over_trough_color and _update_compact_value_color()'s
# own per-frame check (see _process() below) are UNCHANGED by the 2026-
# 09-05 move - still real, still called - but now that the label sits
# fully outside the bar's own width, hp_bar's fill can never reach far
# enough to cover it (fill_right_edge is capped at hp_bar.size.x, always
# less than the label's own now-external position), so in practice the
# label settles on over_trough_color permanently once outside. Left as-is
# rather than simplified away - this function's own caller (run_hud.gd)
# still passes both colors, and a future caller of the OLD inside-the-bar
# behavior would need this working exactly as it always did.
#
# ValueLabel needs no z_index/reparenting to draw above HPBar/RallyOverlay/
# BarBorder - it's already the later sibling among them in vitals_bar.tscn
# (see this scene's own node order), so it already draws on top.
const COMPACT_VALUE_LABEL_WIDTH_PX := 80.0
# The label's own box width once positioned outside the bar (anchor_left/
# right both pinned to 1.0, the bar's own right edge, turns offset_left/
# offset_right into a plain pixel span starting left_inset_px past that
# edge) - a generous default span rather than measured text width, since
# Label doesn't clip its own text to its rect by default (clip_text is
# false, unset here); this only needs to be positive, not exact. Used as
# width_px's own default below - a caller can override it, but nothing
# needs to today (run_hud.gd, the one real caller, passes its own export
# through instead - see compact_value_width_px's own doc).
func apply_compact_value_style(height_px: float, font_size_px: int, left_inset_px: float, over_fill_color: Color, over_trough_color: Color, vertical_offset_px: float = 0.0, width_px: float = COMPACT_VALUE_LABEL_WIDTH_PX) -> void:
	bar_height_px = height_px
	hp_bar.offset_bottom = bar_height_px
	_apply_border_style()

	value_label.add_theme_font_size_override("font_size", font_size_px)
	value_label.anchor_left = 1.0
	value_label.anchor_right = 1.0
	value_label.anchor_top = 0.0
	value_label.anchor_bottom = 1.0
	value_label.offset_left = left_inset_px
	value_label.offset_right = left_inset_px + width_px
	# vertical_offset_px (2026-09-05, tunable-knobs pass) - shifts the
	# WHOLE anchored box up (negative) or down (positive) without changing
	# its height or which edge vertical_alignment anchors text to below;
	# 0.0 (the default, and every OTHER VitalsBar instance's own implicit
	# value - nothing else ever calls this function) reproduces the exact
	# box this used to hardcode (offset_top/_bottom both 0.0).
	value_label.offset_top = vertical_offset_px
	value_label.offset_bottom = vertical_offset_px
	# BOTTOM, not CENTER (2026-09-05, explicit ask) - at a 12px font in an
	# 11px-tall bar, the label's own text is taller than its box, so it
	# overflows regardless of alignment; CENTER split that overflow evenly
	# above and below (reading as sitting a few px too low, its own bottom
	# edge past the bar's), BOTTOM anchors the text's bottom edge exactly
	# to the box's own bottom (the bar's bottom) and lets the overflow
	# happen upward only - the same rect, just which edge it grows from.
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	_compact_over_fill_color = over_fill_color
	_compact_over_trough_color = over_trough_color
	_compact_mode = true
	_update_compact_value_color()

	# No stacked value-label row or status row below the bar any more (see
	# this function's own header) - this node's total footprint IS the
	# bar, full stop, unlike _ready()'s own total_height formula (bar +
	# value row + status row) every non-compact instance still uses.
	custom_minimum_size.y = bar_height_px
	size.y = bar_height_px

# Checked every frame (see _process() below) rather than only on update_
# hp() - hp_bar.value tweens smoothly toward its target (see that
# function's own _hp_tween), so the fill's edge moves continuously; a
# check only at the START of a change would use the TARGET fraction
# immediately, reading slightly ahead of the bar's own still-mid-tween
# visual for tween_duration_sec (0.25s) - matching the same "read the
# live value every frame" shape _process()'s own block-badge tracking
# below already established, not a new pattern.
func _update_compact_value_color() -> void:
	var fill_fraction: float = clampf(hp_bar.value / maxf(hp_bar.max_value, 1.0), 0.0, 1.0)
	var fill_right_edge: float = fill_fraction * hp_bar.size.x
	var font: Font = value_label.get_theme_font("font")
	var font_size: int = value_label.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(value_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var label_right_edge: float = value_label.offset_left + text_width
	# >= , not >: the fill has to reach (not just approach) the label's
	# own right edge before it's safe to assume the WHOLE label sits on
	# fill - the "fill edge lands mid-text" case this pass's own
	# verification calls out by name is exactly the gap between these two
	# thresholds, and it resolves toward the trough-safe color, not the
	# fill-safe one, on purpose (see this function's own header - a
	# partially-covered label is closer to "sitting on the trough" than
	# "sitting on the fill" for legibility purposes).
	var fully_covered_by_fill := fill_right_edge >= label_right_edge
	value_label.add_theme_color_override("font_color", _compact_over_fill_color if fully_covered_by_fill else _compact_over_trough_color)

# Tracks the badge's RIGHT edge to hp_bar's own fill/trough boundary
# every frame (2026-08-27, fill-edge-tracking pass) - block sits in
# front of real HP and depletes first, so the plate's position should
# say that directly: it rides the leading edge of the fill, not a fixed
# spot on the bar. Gated on block_badge.visible so this does no work at
# all while hidden (the common case - block is 0 most of the time).
#
# Reads hp_bar.value fresh every frame rather than caching it, which is
# what makes this track SMOOTHLY through an in-flight HP tween
# (update_hp()'s own _hp_tween animates that exact property) with no
# separate sync needed - both the fill's own rendered width and this
# badge's position are reading the same live number every frame, so
# they can never drift apart or lag one frame behind each other.
func _process(_delta: float) -> void:
	if block_badge.visible or absorb_badge.visible:
		var fill_fraction: float = clampf(hp_bar.value / maxf(hp_bar.max_value, 1.0), 0.0, 1.0)
		var fill_x: float = fill_fraction * hp_bar.size.x
		var target_right: float = fill_x + block_badge_edge_offset_px
		# Anchored by the RIGHT edge (target_right - badge_size_px), not
		# the left, so the plate sits OVER the fill (block is in front of
		# HP), never straddling fill and trough. Clamped to 0 (hp_bar's
		# own local left edge, i.e. the frame's inner left edge -
		# BarBorder's own transparent center lands exactly there, see the
		# border-weight pass's own doc) for the very-low-HP case, where
		# the fill is too narrow for the badge to fit entirely to its
		# left. No matching clamp on the right: at full HP the fill's own
		# width already contains the badge (badge_size_px is well under
		# hp_bar.size.x for every bar width this game produces), so it's
		# never needed there.
		var slot_x: float = maxf(target_right - block_badge.badge_size_px, 0.0)
		# Extended (2026-09-05, Forbearance pass), not generalized into a
		# loop over N badges - exactly two, explicitly handled: block
		# always claims the fill-edge slot when visible, with absorb
		# sitting immediately to its right (its own width plus absorb_
		# badge_gap_px further along). When block is 0 and hidden, absorb
		# takes the fill-edge slot directly instead - the two badges never
		# both reach for the same spot, and there's no third badge today
		# to justify a more general mechanism.
		if block_badge.visible:
			block_badge.position.x = slot_x
			absorb_badge.position.x = slot_x + block_badge.badge_size_px + absorb_badge_gap_px
		else:
			absorb_badge.position.x = slot_x
	if _compact_mode:
		_update_compact_value_color()

# Convenience for a caller that just wants an always-accurate HP bar
# without tracking player_block itself or re-deriving RunState.player_hp/
# player_max_hp on its own - pulls straight from RunState and forwards to
# update_hp(). Field rooms have no per-turn moment that would call
# update_hp() the way battle does after every card/attack, so
# field_room.gd calls this once, in _ready(), to make sure a freshly
# loaded room immediately reflects whatever HP was carried over from the
# last fight. Safe to call anytime, from anywhere - RunState is the one
# place player HP actually lives, so this can never be stale by
# construction.
func refresh_from_run_state() -> void:
	update_hp(RunState.player_hp, RunState.player_max_hp)

# Battle calls this whenever a combatant's HP changes (damage, and
# healing - the tween direction doesn't care which way the value
# moved). The NUMBER always reads correctly immediately; only the bar's
# fill animates toward it.
func update_hp(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	value_label.text = "%d/%d" % [current, max_hp]

	if not _has_shown_hp:
		_has_shown_hp = true
		hp_bar.value = current
	else:
		if _hp_tween:
			_hp_tween.kill()
		_hp_tween = create_tween()
		_hp_tween.tween_property(hp_bar, "value", current, tween_duration_sec)

	_update_low_hp_state(current, max_hp)

# Battle calls this whenever block changes (gained from a card/Defend
# intent, or eaten by incoming damage) - show_block=false (the field
# HUD) makes this a no-op, since the badge stays permanently hidden
# there regardless of what's passed in.
func update_block(amount: int) -> void:
	if show_block:
		block_badge.update(amount)

# Absorb's own counterpart to update_block() above (2026-09-05,
# Forbearance pass) - same "visible = amount > 0, set the label text"
# shape (see AbsorbBadge.update()), deliberately WITHOUT an equivalent show_block-
# style gate: battle.gd is the only thing that ever calls this (the field
# HUD's own VitalsBar instance is never touched by battle.gd at all, only
# by field_room.gd's refresh_from_run_state()/RunHUD, neither of which
# reads or grants absorb), so absorb_badge already stays hidden there for
# free - it starts visible=false in AbsorbBadge._ready() and nothing ever
# calls update_absorb() to change that outside a real battle.
func update_absorb(amount: int) -> void:
	absorb_badge.update(amount)

# Battle calls this whenever a combatant's active-status list changes
# (applied, ticked/expired) - a badge per ActiveStatus (see status_
# badge.gd), same "the caller owns the numbers, this displays them"
# split every other VitalsBar readout follows. A full rebuild rather than
# diffing/reusing existing badges: the counts involved are tiny (a
# handful of statuses at most), so the simplicity of "clear and rebuild"
# comfortably beats the bookkeeping a diff would need for no real
# performance win at this scale.
#
# Capped at MAX_STATUS_BADGES - TRUNCATES, not wraps: anything past the
# cap is simply not shown (no "+N more" indicator either, in this
# commit). Wrapping was the alternative; truncating won instead because
# StatusBadgeRow sits in a fixed horizontal strip under the HP bar - a
# wrap would need its own row-height/vertical-layout logic that pushes
# whatever's below it (or overlaps it), where a plain cap is a one-line
# guard with no layout risk. No real status exists yet to ever hit this
# limit in practice (see status_effect_data.gd's own header) - this is
# a defined ceiling for when one does, not a fix for an observed problem.
const MAX_STATUS_BADGES := 6

# Filtered BEFORE the MAX_STATUS_BADGES slice, not after (2026-08-28,
# Selfeater badge-suppression pass) - a persistent stance (see
# StatusEffectData.is_persistent_stance's own doc) never gets a badge at
# all, so it should never occupy one of the limited slots a real timed
# status could otherwise use either. The ONE choke point every caller
# (battle.gd, enemy.gd, player_battle_visual.gd) already shares - this
# suppression needed touching in exactly one place, not once per call
# site, which is the whole reason it lives here rather than in each of
# them.
func update_statuses(statuses: Array[ActiveStatus]) -> void:
	for child in status_badge_row.get_children():
		child.queue_free()
	var badge_worthy: Array[ActiveStatus] = statuses.filter(func(active): return not active.data.is_persistent_stance)
	for active in badge_worthy.slice(0, MAX_STATUS_BADGES):
		var badge: StatusBadge = STATUS_BADGE_SCENE.instantiate()
		# BEFORE add_child() - see StatusBadge.set_diameter_override()'s
		# own doc for why this has to land before that badge's _ready()
		# runs. 0.0 (every status except boss_01_charging_indicator.tres)
		# skips this entirely, same "zero means unaffected" shape the
		# rest of this function's own is_persistent_stance filter above
		# already uses.
		if active.data.badge_diameter_override_px > 0.0:
			badge.set_diameter_override(active.data.badge_diameter_override_px)
		status_badge_row.add_child(badge)
		badge.set_status(active)

# --- Rally overlay (the Wanderer's rally_pool - see battle.gd's own
# doc for what the pool actually IS) ---
#
# RallyOverlay's left/right anchors together encode the segment
# [current, min(current + pool, max_hp)] as fractions of the bar's own
# width - "begins where current HP ends, extends by the pool, never
# past max" falls straight out of that clamp, no separate bounds-
# checking needed anywhere else. `current` is a required parameter
# here (unlike update_block(), which only ever needs the one number)
# specifically so this never has to guess at hp_bar.value mid-tween -
# battle.gd already knows RunState.player_hp at every call site, and
# passing it explicitly is what lets a recovery's HP-gain and pool-
# shrink animate in perfect lockstep: both tweens are told their real
# target fraction up front and Tween.tween_property() always animates
# FROM the property's current value, so as long as this and
# update_hp() are called with the SAME duration for the SAME event (see
# battle.gd's own call sites), the two edges move together by
# construction - no shared clock or manual per-frame sync required.
func update_rally_pool(current: int, pool: int) -> void:
	if not show_rally_pool:
		return
	_tween_rally_overlay(current, pool, tween_duration_sec)

# Called when the pool expires unspent (battle.gd's _on_end_turn_
# button_pressed(), right before it zeroes rally_pool for real) - same
# anchor math as update_rally_pool(current, 0), just stretched to rally_
# expire_drain_duration_sec instead of the ordinary tween_duration_sec,
# so the drain reads as its own deliberate moment instead of blending
# into a normal hit/heal tween (see that duration's own doc for why).
func drain_rally_pool(current: int) -> void:
	if not show_rally_pool:
		return
	_tween_rally_overlay(current, 0, rally_expire_drain_duration_sec)

# Called on battle end (battle.gd's _close_out_battle()) - snaps
# RallyOverlay closed instantly, no tween, per spec ("the bar is going
# away anyway"). Collapses to a zero-width segment sitting at wherever
# HPBar's fill currently is rather than reading current/pool fresh,
# since neither matters once the fight's over - this only has to not
# leave a stale wide segment visible if the bar (or scene) lingers a
# frame during teardown.
func reset_rally_pool() -> void:
	if not show_rally_pool:
		return
	if _rally_tween:
		_rally_tween.kill()
	var fraction: float = hp_bar.value / max(hp_bar.max_value, 1.0)
	rally_overlay.anchor_left = fraction
	rally_overlay.anchor_right = fraction

func _tween_rally_overlay(current: int, pool: int, duration: float) -> void:
	var max_hp: float = max(hp_bar.max_value, 1.0)
	var left_fraction: float = clampf(current / max_hp, 0.0, 1.0)
	var right_fraction: float = clampf((current + pool) / max_hp, 0.0, 1.0)
	if _rally_tween:
		_rally_tween.kill()
	_rally_tween = create_tween()
	_rally_tween.set_parallel(true)
	_rally_tween.tween_property(rally_overlay, "anchor_left", left_fraction, duration)
	_rally_tween.tween_property(rally_overlay, "anchor_right", right_fraction, duration)

func _update_low_hp_state(current: int, max_hp: int) -> void:
	var fraction := float(current) / float(max(max_hp, 1))
	var now_low := fraction <= low_hp_threshold and current > 0
	if now_low == _is_low_hp:
		return
	_is_low_hp = now_low
	if now_low:
		_apply_bar_color(low_hp_color)
		if low_hp_pulse_enabled:
			_start_pulse()
	else:
		_apply_bar_color(fill_color)
		_stop_pulse()

func _apply_bar_color(color: Color) -> void:
	_fill_style.bg_color = color
	# Rally's own color is DERIVED from whichever fill is currently
	# active, not fixed to a palette constant (2026-08-27, HudPalette
	# pass - a fixed HudPalette.RALLY entry was tried and rejected for
	# exactly this reason: "recoverable HP" only means something
	# relative to the ACTUAL current fill, and a fixed color is only
	# ever safe against ONE fill state, not both normal_color's old
	# role - now HudPalette.FILL - and low_hp_color). Kept in sync here
	# (not set once in _ready()) so a low-HP threshold crossing carries
	# the rally segment along with it automatically, recomputed both
	# directions.
	#
	# BOTH _desaturate() AND rally_value_scale are required together,
	# neither alone - desaturating a saturated color while holding Value
	# fixed makes it LIGHTER (the non-dominant channels rise toward the
	# unchanged max), the opposite of "dimmed HP." rally_value_scale
	# (see its own doc) darkens the already-desaturated result afterward.
	# Do not drop either step without re-verifying against BOTH
	# HudPalette.FILL and low_hp_color - shipping desaturation alone
	# already produced a Rally slice lighter than the fill once.
	var desaturated := _desaturate(color, rally_pool_saturation_scale)
	_rally_style.bg_color = Color.from_hsv(desaturated.h, desaturated.s, desaturated.v * rally_value_scale, desaturated.a)

# Scales a color's SATURATION (HSV) toward gray, alpha untouched -
# deliberately not modulate:a/a plain alpha blend, which would read as
# a translucency/rendering glitch rather than an intentional muted
# state (per this feature's own brief). Color's h/s/v are computed
# read-only properties in Godot (backed by the same rgb this color
# already stores), so this is just "rebuild from HSV with s scaled."
func _desaturate(color: Color, saturation_scale: float) -> Color:
	return Color.from_hsv(color.h, color.s * saturation_scale, color.v, color.a)

func _start_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.set_loops() # 0 = infinite - runs until _stop_pulse() kills it.
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(hp_bar, "modulate:a", 1.0 - low_hp_pulse_alpha_dip, low_hp_pulse_period_sec)
	_pulse_tween.tween_property(hp_bar, "modulate:a", 1.0, low_hp_pulse_period_sec)

func _stop_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
		_pulse_tween = null
	hp_bar.modulate.a = 1.0

# Wraps whatever font the label already resolves (the project default,
# since nothing here assigns a specific font) in a FontVariation that
# fakes bold via glyph embolden - no separate bold font asset to manage.
# Same technique as block_badge.gd's own _apply_bold().
func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)

# Applied to fill/trough/border (see bar_corner_radius_px's own doc) -
# all four corners set together since a StyleBoxFlat has no single
# "radius" property, only four independent corner values.
func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
