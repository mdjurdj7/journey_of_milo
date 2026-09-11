extends Control
class_name ResourceDisplay
# Displays whatever resource gates playing cards - energy today, but per
# DESIGN.md's Pillar 1 (a character's resource system is part of its
# identity: classic energy, rage/momentum, cooldown/rhythm...), a future
# character's Battle equivalent won't spend a flat per-turn energy pool
# at all. THIS is the seam that's supposed to absorb that: battle.gd (or
# whatever a future resource-system's owner is) only ever calls
# `update(current, max_value)` - one call, regardless of what kind of
# resource it is - same "Battle owns the numbers, this only displays
# them" split VitalsBar/Enemy already follow. Which VISUAL shape that
# turns into is decided entirely inside this file, by `mode`.
#
# enum Mode is the whole seam. Only PIP is implemented - a discrete
# per-charge resource (classic energy) reads naturally as filled/empty
# symbols. BAR (an accumulating meter - rage/momentum) and NUMERIC (a
# resource with no natural discrete unit, or too many units to render as
# pips - cooldown/rhythm timers, big numbers) are real enum values
# already wired into update()'s dispatch, but their branches currently
# just fall back to a plain numeric readout with a one-time console
# warning rather than a real bar/gauge - "structured so they can be
# added later without touching battle code" means adding a real BAR mode
# later is entirely a change to THIS file (implement _update_bar_mode(),
# route Mode.BAR to it instead of the fallback) - no caller anywhere else
# needs to know or care that happened.
#
# PIP mode's own "graceful scaling": beyond pip_max_threshold, it stops
# trying to draw that many individual pips (they'd either overflow the
# UI or shrink unreadably) and falls back to the SAME plain-numeric
# rendering the unimplemented modes use - a future energy-boosting effect
# pushing max energy past what pips can comfortably show doesn't need
# special-casing either, it's the same fallback path already exercised
# by BAR/NUMERIC today.

enum Mode { PIP, BAR, NUMERIC }

@export_group("Resource Display")
@export var mode: Mode = Mode.PIP
@export var pip_max_threshold: int = 6
# Above this many pips, PIP mode falls back to the plain numeric display
# instead of rendering that many symbols - see the class comment above.
@export var show_numeric_readout: bool = true
# The small "2/3" precision readout show ALONGSIDE the pips (not the
# fallback numeric display above, which is unconditional) - toggle off
# to see pips-only.

@export_group("Pip Appearance")
@export var pip_scene: PackedScene = preload("res://pip.tscn")
# Extracted 2026-08-26 (pip-scene pass) - resource_display.gd no longer
# builds pip polygons or knows about border width at all; it only ever
# calls pip_scene's instance through configure()/set_filled() (see pip.
# gd's own header). Swapping in a different pip scene here is the ONLY
# step needed to change pip appearance - _rebuild_pips() below has no
# per-shape logic to also update.
@export var pip_dim_color: Color = Color(0.22, 0.212, 0.188, 0.486)
# pip_lit_color REMOVED (2026-08-27, true-color pass) - a pip is either
# full color or empty, never a third tint in between, so "lit" never
# needed its own tunable color at all: it was a modulate multiply that
# should have just been Color.WHITE (a no-op), not a knob inviting
# retuning. It drifted anyway - first to a saturated gold left over from
# the old flat-diamond pip, then to a near-neutral (0.88, 0.87, 0.83)
# "contrast fix" that still wasn't white, quietly dulling every lit pip
# below its own pip.tscn-authored color for no measurable contrast gain
# (dim_color's own much lower luminance already carries that contrast on
# its own). See pip.gd's own set_filled()/_apply_geometry() - lit is
# just Color.WHITE now, a real constant, not an export.
@export var pip_size: float = 48.0
@export var pip_spacing: float = 6.0

@export_group("Pip Animation")
@export var refill_stagger_sec: float = 0.05
# spend_pulse_sec/refill_pip_duration_sec MOVED to pip.gd (2026-08-26) -
# see its own doc for why HOW one pip animates is its own business now,
# not the display's. This one stays here on purpose: staggering WHICH
# pip starts its own animation, and when, is a fact about the ROW of
# pips, not any single one of them - a pip has no way to know it's one
# of several, let alone which index it is.

const SECONDARY_READOUT_OFFSET_LEFT := 460.0
const SECONDARY_READOUT_FONT_SIZE := 24
const PRIMARY_READOUT_FONT_SIZE := 36
# "Secondary" = the small readout beside pips; "primary" = the readout
# standing in alone for an unimplemented/overflow mode, so it needs to
# read clearly on its own - see _apply_numeric_readout_layout().

@onready var pip_row: HBoxContainer = $PipRow
@onready var value_label: Label = $ValueLabel

var _pips: Array = []
# The pip instances themselves - was _pip_fills/_pip_visuals (direct
# references into each pip's own internal Polygon2D/Node2D nodes) before
# the pip-scene extraction (2026-08-26); this display no longer reaches
# inside a pip at all, only calls its configure()/set_filled() API (see
# pip.gd's own header). Deliberately untyped, NOT Array[Pip] - a custom
# pip scene's own script never needs to extend Pip's class, only match
# its two method signatures (duck-typed), so typing this to Pip
# specifically would impose a constraint nothing here actually needs.
var _current_value: int = 0
var _current_max: int = 0
# 0 is never a real max_value for any resource system this game has -
# used as an "unset" sentinel so the very first update() call is
# guaranteed to look like a max_value change (see update() below), which
# is what makes it SNAP into place instead of animating from nothing.
var _warned_unimplemented_mode: bool = false

func _ready() -> void:
	pip_row.add_theme_constant_override("separation", roundi(pip_spacing))

# The one entry point every caller uses, regardless of mode - see the
# class comment above for why that matters.
func update(current: int, max_value: int) -> void:
	var max_changed := max_value != _current_max
	if max_changed:
		_rebuild_pips(max_value)

	var numeric_only := mode != Mode.PIP or max_value > pip_max_threshold
	if mode != Mode.PIP and not _warned_unimplemented_mode:
		_warned_unimplemented_mode = true
		push_warning("ResourceDisplay: mode %s isn't implemented yet - falling back to a plain numeric readout." % Mode.keys()[mode])

	pip_row.visible = not numeric_only
	_apply_numeric_readout_layout(numeric_only)
	value_label.visible = numeric_only or show_numeric_readout
	value_label.text = "%d/%d" % [current, max_value]

	if not numeric_only:
		if max_changed:
			_snap_pips(current)
		elif current < _current_value:
			_animate_spend(_current_value, current)
		elif current > _current_value:
			_animate_refill(_current_value, current)

	_current_value = current
	_current_max = max_value

func _apply_numeric_readout_layout(is_primary: bool) -> void:
	if is_primary:
		value_label.offset_left = 0.0
		value_label.add_theme_font_size_override("font_size", PRIMARY_READOUT_FONT_SIZE)
	else:
		value_label.offset_left = SECONDARY_READOUT_OFFSET_LEFT
		value_label.add_theme_font_size_override("font_size", SECONDARY_READOUT_FONT_SIZE)

# --- Pip construction ---

# Instantiates pip_scene once per pip and hands it its static appearance
# via configure() - this display no longer builds any polygons or knows
# pip_border_width exists (see pip_scene's own doc above and pip.gd's own
# header). Swapping pip_scene in the Inspector is the only step needed to
# change what a pip looks like; nothing here has any per-shape logic to
# also update.
func _rebuild_pips(max_value: int) -> void:
	for child in pip_row.get_children():
		# remove_child() first so PipRow's layout updates immediately -
		# same reasoning as battle.gd's _discard_entire_hand() (queue_free()
		# alone doesn't remove a child from its container until the end of
		# the frame, which would count it in the meantime).
		pip_row.remove_child(child)
		child.queue_free()
	_pips.clear()

	for i in max_value:
		var pip = pip_scene.instantiate()
		pip_row.add_child(pip)
		pip.configure(pip_size, pip_dim_color)
		_pips.append(pip)

# --- Pip state ---
#
# All three functions below only ever call set_filled() on a pip - never
# touch a color or a Node2D directly (see pip.gd's own header for why:
# this display doesn't know or care HOW a pip shows filled/empty/its own
# transition, only WHICH pips should be in which state and, for refill,
# in what order).

func _snap_pips(current: int) -> void:
	for i in _pips.size():
		_pips[i].set_filled(i < current, false)

# Each newly-spent pip (index new_value..old_value-1) animates to empty
# at once, not staggered - a multi-cost card dims more than one pip
# simultaneously (staggering is reserved for refill, below, where the
# sequence itself is the point). What "animates to empty" actually LOOKS
# like (a color fade, a scale pulse, both, neither) is entirely pip.gd's
# own call now - this just triggers it.
func _animate_spend(old_value: int, new_value: int) -> void:
	for pip_index in range(new_value, old_value):
		_pips[pip_index].set_filled(false, true)

# Each newly-refilled pip (index old_value..new_value-1) animates to
# filled, but doesn't START until refill_stagger_sec later than the
# previous one - staggering WHEN each pip's own animation begins is this
# display's job (see _pips' own doc above); a single Tween of callbacks,
# each delayed by its own index, is what actually staggers the START
# times without this display needing to reach into any pip's own tween
# to do it.
func _animate_refill(old_value: int, new_value: int) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	var newly_lit := range(old_value, new_value)
	for i in newly_lit.size():
		var pip_index: int = newly_lit[i]
		tween.tween_callback(_pips[pip_index].set_filled.bind(true, true)).set_delay(i * refill_stagger_sec)
