extends Control
class_name TollDisplay
# The player's per-combat Toll readout - "what the Sunken Works
# extracts from you," accruing from HP lost from ANY source (see
# battle.gd's own _set_player_hp()). Deliberately NOT a status effect:
# no badge, no StatusBadgeRow.
#
# Same "the caller pushes a number, this owns how a CHANGE looks" split
# VitalsBar/BlockBadge/StatusBadge all already follow - battle.gd calls
# update_toll(), never touches these labels directly.
#
# REWORKED (2026-08-25, resource-cluster pass) from "hidden until first
# accrual, fades in/out" to ALWAYS VISIBLE, dim at 0 - moving into
# player_resource_cluster.tscn (grouped with the energy pips, inside a
# real backing panel) makes Toll a permanent fixture of that panel the
# same way the pips themselves are; a row that pops in and out of a
# panel that's otherwise always fully present read as inconsistent with
# everything else living in it. Zero now looks like card.gd's own
# UNAFFORDABLE_MODULATE dim (see zero_state_modulate below) rather than
# disappearing - "the meter is just at zero," not "there is no meter."

@export var word_font_size: int = 20
@export var value_font_size: int = 44
# value_font_size raised hard (2026-08-25, resource-cluster pass, from
# 22->26->44 across two passes) - Toll is a number the player does
# arithmetic against before playing a Toll-gated card, so it needs to
# read at a glance, deliberately heavier than the pip cluster sitting
# right above it (a pip's own diamond is 32px - see resource_display.
# gd's pip_size) rather than merely matching it. word_font_size raised
# again (16->20, same pass's own follow-up fix) - "TOLL" was on the
# system-voice sans at the time (see word_font's own doc below for why
# that's since changed), but 16 read as incidental scaffolding next to a
# 44px value instead of a clearly legible label in its own right. Kept
# as the starting point for word_font's own Spectral swap - Spectral may
# need a different optical size than the sans did, tune directly.

@export var word_font: Font = preload("res://assets/fonts/Spectral-Light.ttf")
# "TOLL" moved OFF the system-voice sans onto Spectral (2026-08-27,
# world-voice pass) - Toll is the run's central idea, not a generic stat
# readout; every other element in the player cluster (pips, the value
# numeral here) is sans inside a dark frame, so this is the one element
# that should speak with the world's voice instead, carried by typeface
# alone (not color or chrome - value_color/word_color stay monochrome,
# see those exports' own docs). Same direct-preload-the-.ttf convention
# every other Spectral consumer uses (card.gd's name_font, loot_row.gd's
# WEAPON_NAME_FONT, weapon_pickup_window.tscn's baked theme overrides) -
# no wrapped/duplicated Font resource, no project-wide Theme entry.
# LIGHT specifically, not Regular: at 20px uppercase with tracking,
# Spectral's serifs read heavier than the sans they replace at the same
# nominal size - Light gives back the headroom needed to stay quiet
# against the numeral, which is the entire point of the contrast.
# Applied in _ready() below via add_theme_font_override() BEFORE
# _apply_letter_spacing() runs, so the tracking FontVariation wraps
# Spectral, not the sans it replaced.

@export var word_letter_spacing_px: int = 2
# Tracked-out glyph spacing on "TOLL" alone - still a small-caps-adjacent
# treatment (Spectral ships no small-caps cut - only Regular/Light/Bold
# weight files exist in assets/fonts/, no SC variant, no smcp OpenType
# feature - so true uppercase-plus-tracking is the real answer here, not
# a fallback standing in for one), just now applied to Spectral rather
# than the sans it replaced (see word_font's own doc above). Same
# technique weapon_pickup_window.gd's own _setup_letter_spacing() uses
# (a FontVariation wrapping the base font, TextServer.SPACING_GLYPH) -
# that file treats letterspacing as a WORLD-VOICE marker on ITS OWN
# screen specifically (its own header note); here it now doubles as
# both that AND "this reads as a label, not incidental text" at once,
# since word_font's own switch already carries the world-voice signal on
# its own - the two reasons happen to point the same direction now,
# where before (on the sans) only the second one applied.

@export var word_color: Color = Color(0.966, 0.96, 0.951, 1.0) # #6b6255
# Dimmed warm grey - "TOLL" is scaffolding, not the thing being read
# (see this class's own header). Same dimmed tone weapon_pickup_window.
# tscn already uses throughout for de-emphasized text, reused here
# rather than a new one-off value.
@export var value_color: Color = Color(0.941176, 0.909804, 0.85098, 1) # #f0e8da
# Monochrome pair with word_color - the WEIGHT difference (plus, now,
# the SIZE difference) carries the hierarchy, not a second hue. A second
# color reads as its own signal (a coincidental green would read as a
# buff, the opposite of what Toll means).

@export var zero_state_modulate: Color = Color(0.55, 0.55, 0.55, 0.55)
# Applied to this whole Control (word AND value together) when Toll is
# 0 - the same "multiply the whole thing toward grey/faint" shape card.
# gd's set_affordable() already uses for UNAFFORDABLE_MODULATE, reused
# here rather than a one-off partial-dim scheme. Full strength (Color.
# WHITE - a no-op multiply) the instant Toll becomes positive; see
# _apply_zero_state() below.

@export var pulse_scale: float = 1.25
@export var pulse_duration_sec: float = 0.12
# The "Toll just changed" reaction - a quick scale bump on the NUMBER
# alone (not the whole row), tying the accrual to whatever hit caused
# it. Reuses pip.gd's own spend-pulse vocabulary (create_tween(), a
# squash/pop via `scale`, no new animation system) rather than
# inventing a second one. Short and un-eased-in on purpose ("this fires
# often" - see this feature's own brief): every Toll change fires it,
# including small, frequent accruals mid-fight.

@export var tick_duration_sec: float = 0.4
# How long the DIGITS take to count from the old value to the new one -
# separate from pulse_duration_sec above (the number's own scale kick),
# which is deliberately much shorter and plays independently alongside
# this.

@export var value_column_width_px: float = 90.0
# Fixed width for value_label - measured against "999" at value_font_
# size in its bold variant (77px - see this feature's own commit) plus
# a real margin, so 3 digits never need the column to widen. Left-
# aligned within it now (see _layout_row() below) - digits extend
# RIGHTWARD as the value grows, but the column's own reported WIDTH
# never changes, which is what makes "reserve the width, don't resize
# the container" true for free: the CLUSTER backing panel (player_
# resource_cluster.gd) reads this node's size once, and that size never
# changes as Toll's value does.
@export var word_value_gap_px: float = 1.0
# Horizontal gap between "TOLL" and the number (2026-08-26, horizontal-
# layout experiment) - this row previously stacked the value below the
# word (2026-08-25 fix) because side-by-side read as a debug readout at
# the word/value size difference; reverting to side-by-side here is a
# deliberate re-test of that call, not an oversight. If the horizontal
# arrangement is kept, this comment and the stacked-layout history above
# should be reconciled; if it's rejected again, revert to the stacked
# version this replaced.
@export var row_padding_px: float = 0.0
# Extra headroom added on top of each label's own MEASURED font metrics
# (see _layout_row() below) when sizing its row - not a guess this time.
# This is directly what fixed the value being clipped by the cluster's
# own bottom edge: the previous row_height_px (a flat 54px guess) was
# never actually checked against the value font's real line height,
# which turned out to be 61px at value_font_size 44 - a hard cut with no
# margin, guaranteed to clip eventually. Deriving each row's height from
# Font.get_height() directly means this stays correct if value_font_size
# or word_font_size ever changes again, with no future re-tuning needed.

@export var baseline_offset_px: float = 0.0
# Manual nudge on top of the COMPUTED shared baseline (2026-08-26,
# baseline-alignment pass - see _layout_row() below). The baseline itself
# comes from real Font.get_ascent()/get_descent() metrics, not a guess;
# this exists only for a final, small optical correction if the computed
# baseline doesn't quite read right once seen live, not as a substitute
# for the real computation. Positive moves the shared baseline DOWN.
# Zero by default - the computed baseline is the real answer until
# proven otherwise.

const OUTLINE_WIDTH_OVERRIDE := 6
# Thicker than OverlayStyle's own shared default (4) - see its own
# apply_to_label() note on width_override existing for exactly this: a
# spot with no other legibility help (the HP bar's own numerals sit on
# a solid color bar for free; Toll has no backing of its own - the
# cluster's backing panel sits behind the whole row, not a per-glyph
# treatment) needs to go thicker than the shared default.

@export var value_bold_strength: float = 0.5
# Only the NUMBER gets bolded, not "TOLL" - matches this row's own
# hierarchy (weight, not color, is what marks the value as the thing
# being read - see value_color's own note). Same value and same fake-
# bold technique (FontVariation.variation_embolden, no separate bold
# font asset) vitals_bar.gd's own value_bold_strength already uses for
# the HP number - see its _apply_bold().

@onready var word_label: Label = $TollWordLabel
@onready var value_label: Label = $TollValueLabel

var _displayed_value: int = 0
var _tick_tween: Tween
var _pulse_tween: Tween

func _ready() -> void:
	word_label.text = "TOLL"
	word_label.add_theme_font_override("font", word_font)
	word_label.add_theme_font_size_override("font_size", word_font_size)
	word_label.add_theme_color_override("font_color", word_color)
	word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	word_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_apply_letter_spacing(word_label, word_letter_spacing_px)
	OverlayStyle.apply_to_label(word_label, false, OUTLINE_WIDTH_OVERRIDE)

	value_label.text = "0"
	value_label.add_theme_font_size_override("font_size", value_font_size)
	value_label.add_theme_color_override("font_color", value_color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	OverlayStyle.apply_to_label(value_label, false, OUTLINE_WIDTH_OVERRIDE)
	_apply_bold(value_label, value_bold_strength)

	_layout_row()
	_apply_zero_state(0)

# Fake-bold via FontVariation.variation_embolden - no separate bold font
# asset to manage. Same technique as vitals_bar.gd's own _apply_bold()
# (originally block_badge.gd's).
func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)

# Tracked-out glyph spacing - see word_letter_spacing_px's own doc for
# why this label specifically gets it. Same FontVariation-wrapping
# technique as _apply_bold() above (a different variation knob, same
# "wrap the base font, override the theme font" shape).
func _apply_letter_spacing(label: Label, spacing_px: int) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.set_spacing(TextServer.SPACING_GLYPH, spacing_px)
	label.add_theme_font_override("font", variation)

# "TOLL" beside the value, word left/value right, both sitting on a
# SHARED BASELINE (2026-08-26, baseline-alignment pass) - previously
# each label's whole line box was centered within the row height, which
# doesn't line up the actual glyph baselines once the two fonts differ
# in size (their ascent:descent ratios aren't the same), leaving the
# word looking like it floats mid-height against the numeral. Baseline
# is computed from each font's own REAL Font.get_ascent()/get_descent()
# (not Font.get_height(), which only gives the combined total - ascent
# and descent are needed separately to place a shared baseline, not just
# a shared box) - the font read is whatever's CURRENTLY applied to each
# label (word_label's letter-spacing variation, value_label's bold
# variation), same as get_height() was already doing, so this can't
# drift out of sync with what's actually rendering. Both labels are
# VERTICAL_ALIGNMENT_TOP now (set in _ready()) so each one's own ascent
# starts exactly at its rect's top - that top is then positioned at
# row_ascent - own_ascent, which is what actually places both labels'
# baselines at the same row_ascent line regardless of font size.
# row_padding_px (see that export's own doc) is added once to the row's
# total height, not per label - it was never a per-font metric, just
# shared breathing room. value_label keeps its own fixed-width column
# (value_column_width_px) regardless of digit count; pivot_offset
# centers it on itself so the change-pulse (see _pulse() below) scales
# symmetrically instead of visibly drifting as it grows and shrinks.
func _layout_row() -> void:
	var word_font: Font = word_label.get_theme_font("font")
	var value_font: Font = value_label.get_theme_font("font")
	var word_ascent: float = word_font.get_ascent(word_font_size)
	var word_descent: float = word_font.get_descent(word_font_size)
	var value_ascent: float = value_font.get_ascent(value_font_size)
	var value_descent: float = value_font.get_descent(value_font_size)
	var row_ascent: float = maxf(word_ascent, value_ascent) + baseline_offset_px
	var row_descent: float = maxf(word_descent, value_descent)
	var row_height: float = row_ascent + row_descent + row_padding_px

	word_label.reset_size()
	word_label.position = Vector2(0.0, row_ascent - word_ascent)
	word_label.size.y = word_ascent + word_descent

	value_label.position = Vector2(word_label.size.x + word_value_gap_px, row_ascent - value_ascent)
	value_label.size = Vector2(value_column_width_px, value_ascent + value_descent)
	value_label.pivot_offset = value_label.size / 2.0

	custom_minimum_size = Vector2(value_label.position.x + value_column_width_px, row_height)
	size = custom_minimum_size

# The one entry point for every change - battle.gd calls this with the
# running total whenever Toll changes at all, accrual (_set_player_hp())
# or spend (TOLL_BLOCK/TOLL_RETALIATE/TOLL_DAMAGE) alike, always with
# Toll's own true current value (never negative - callers already
# guarantee that). A spend landing exactly on 0 needs no separate call:
# this ticks the number down to 0 and returns to the zero-state dim
# (_apply_zero_state()) on its own, the same as if Toll had simply never
# accrued this fight - there's no more fade-to-hidden distinction to
# maintain a second entry point for (see this class's own header).
func update_toll(value: int) -> void:
	if value == _displayed_value:
		return
	_tick_to(value)
	_apply_zero_state(value)
	_pulse()

# card.gd's set_affordable()-style whole-control modulate, not a per-
# label color swap - see zero_state_modulate's own doc for why.
func _apply_zero_state(value: int) -> void:
	modulate = Color.WHITE if value > 0 else zero_state_modulate

func _tick_to(value: int) -> void:
	if _tick_tween:
		_tick_tween.kill()
	var from_value := _displayed_value
	_displayed_value = value
	_tick_tween = create_tween()
	_tick_tween.tween_method(_set_displayed_value, float(from_value), float(value), tick_duration_sec)

func _set_displayed_value(value: float) -> void:
	value_label.text = str(int(value))

# The "Toll just changed" reaction - see pulse_scale/pulse_duration_sec's
# own doc. A plain squash-free pop (scale 1 -> pulse_scale -> 1), the
# simplest member of pip.gd's own pulse vocabulary (that one also fades
# a color in the same tween; this one has no second color state to fade
# between, only the dim/full modulate swap above, which is instant by
# design) - plays independently of _tick_tween above, which is why this
# is its own separate Tween rather than another step chained onto it.
func _pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	value_label.scale = Vector2.ONE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(value_label, "scale", Vector2.ONE * pulse_scale, pulse_duration_sec * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(value_label, "scale", Vector2.ONE, pulse_duration_sec * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
