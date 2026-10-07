extends Control
class_name BattleResources

# The player's energy, bottom-left of the battle overlay beside the hand
# (BattleOverlay pins it: its right edge and its numeral's top at
# energy_anchor, whatever the hand holds).
# An instrument readout in ink, drawn: the current value as a large
# numeral with "ENERGY" tracked on its baseline (the way TOLL sits beside
# its numeral, see HPBar), and under them a row of pips - one short heavy
# bar per point of max energy, full ink while available, faint (spent_
# pip_alpha) once spent, in place; energy above max adds solid pips past
# a gap. No "/ max": the pips carry capacity. A pip changing state
# crossfades over pip_fade_sec - no pulse, no flash.
# Toll lives on the Wanderer's own readout (see HPBar), not here.
#
# Driven by BattleOverlay from BattleController's energy_changed (current
# only - max comes from the player Combatant at setup, see set_energy()).

@export var numeral_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf"):
	set(value):
		numeral_font = value
		_restyle()
@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf"):
	set(value):
		label_font = value
		_restyle()
@export var label_tracking_em: float = 0.16:
	set(value):
		label_tracking_em = value
		_restyle()

@export_group("Energy")
@export var numeral_size_px: int = 72:
	set(value):
		numeral_size_px = value
		_relayout()
@export var energy_label_text: String = "ENERGY":
	set(value):
		energy_label_text = value
		_relayout()
@export var energy_label_size_px: int = 10:
	set(value):
		energy_label_size_px = value
		_restyle()
@export_range(0.0, 1.0) var energy_label_alpha: float = 0.62:
	set(value):
		energy_label_alpha = value
		queue_redraw()
# Between the numeral's right edge and the label.
@export var numeral_label_gap_px: float = 8.0:
	set(value):
		numeral_label_gap_px = value
		_relayout()

@export_group("Pips")
# One bar per point of max energy, this size, pip_gap_px apart.
@export var pip_size: Vector2 = Vector2(18.0, 5.0):
	set(value):
		pip_size = value
		_relayout()
@export var pip_gap_px: float = 6.0:
	set(value):
		pip_gap_px = value
		_relayout()
# Between the numeral's baseline and the pips' top.
@export var pip_baseline_gap_px: float = 8.0:
	set(value):
		pip_baseline_gap_px = value
		_relayout()
# A spent pip: the same bar in ink at this alpha, so it inverts with the
# theme like the ink does.
@export_range(0.0, 1.0) var spent_pip_alpha: float = 0.25:
	set(value):
		spent_pip_alpha = value
		queue_redraw()
# Energy above max: its pips follow the max row after this many pip
# widths of space.
@export var over_max_gap_pips: float = 2.0:
	set(value):
		over_max_gap_pips = value
		_relayout()
# How long a pip takes to cross from available to spent, or back - and an
# over-max pip to come or go.
@export var pip_fade_sec: float = 0.12

const GLYPH_RECT_MARGIN_PX := 1.0

var _energy: int = 0
var _max_energy: int = 0
var _ink: Color = Color.BLACK
var _energy_label_tracked: Font = null
# Each pip's shown state, 0 (spent / an over-max pip gone) to 1
# (available), easing to its target in _process() - the max row first,
# then the over-max pips. Empty until the first set_energy(), which snaps.
var _pip_lit: Array[float] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	refresh_style()

# Re-reads the theme's ink - called at _ready() and by BattleOverlay's F2
# flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_energy_label_tracked = InkType.tracked(label_font, energy_label_size_px, label_tracking_em)
	_relayout()

func set_energy(current: int, max_energy: int) -> void:
	var first: bool = _pip_lit.is_empty()
	_energy = maxi(current, 0)
	_max_energy = maxi(max_energy, 0)
	# Room for every pip that is or is still fading out.
	var count: int = maxi(_max_energy + _over_max(), _pip_lit.size())
	while _pip_lit.size() < count:
		var index: int = _pip_lit.size()
		# A max-row pip that's new at the first reading starts where it
		# belongs; an over-max pip always fades in.
		_pip_lit.append(_pip_target(index) if first and index < _max_energy else 0.0)
	if first:
		for i in _max_energy:
			_pip_lit[i] = _pip_target(i)
	set_process(true)
	_relayout()

# Export setters run before _ready() too - only restyle once in the tree.
func _restyle() -> void:
	if is_inside_tree():
		refresh_style()

func _process(delta: float) -> void:
	var step: float = delta / maxf(pip_fade_sec, 0.001)
	var settled: bool = true
	for i in _pip_lit.size():
		var target: float = _pip_target(i)
		_pip_lit[i] = move_toward(_pip_lit[i], target, step)
		if _pip_lit[i] != target:
			settled = false
	if settled:
		# Over-max pips that have faded out leave the row.
		var count: int = maxi(_max_energy + _over_max(), _max_energy)
		if _pip_lit.size() > count:
			_pip_lit.resize(count)
			_relayout()
		set_process(false)
	queue_redraw()

func _over_max() -> int:
	return maxi(_energy - _max_energy, 0)

# Pip `index`'s state to ease toward: a max-row pip is available while
# index < energy; an over-max pip is there while energy reaches it.
func _pip_target(index: int) -> float:
	if index < _max_energy:
		return 1.0 if index < _energy else 0.0
	return 1.0 if index - _max_energy < _over_max() else 0.0

# --- Geometry, top to bottom ---

func _numeral_text() -> String:
	return str(_energy)

func _numeral_ascent() -> float:
	return numeral_font.get_ascent(numeral_size_px) if numeral_font != null else float(numeral_size_px)

func _numeral_width() -> float:
	return InkType.width(numeral_font, _numeral_text(), numeral_size_px) if numeral_font != null else 0.0

# Pip `index`'s left x: the max row from 0, an over-max pip past the gap.
func _pip_x(index: int) -> float:
	var x: float = float(index) * (pip_size.x + pip_gap_px)
	if index >= _max_energy:
		x += over_max_gap_pips * pip_size.x
	return x

func _pips_width() -> float:
	if _pip_lit.is_empty():
		return 0.0
	return _pip_x(_pip_lit.size() - 1) + pip_size.x

func _content_size() -> Vector2:
	var label_width: float = InkType.width(_energy_label_tracked, energy_label_text, energy_label_size_px) if _energy_label_tracked != null else 0.0
	var width: float = maxf(_numeral_width() + numeral_label_gap_px + label_width, _pips_width())
	var height: float = _numeral_ascent()
	if not _pip_lit.is_empty():
		height += pip_baseline_gap_px + pip_size.y
	return Vector2(width, height)

# Where the numeral's ink starts, from this readout's top: the tallest
# figure's top (figure_ink_top()), so it holds whatever the digit.
# BattleOverlay pins this to energy_anchor's y.
func numeral_ink_top() -> float:
	if numeral_font == null:
		return 0.0
	return _numeral_ascent() + figure_ink_top(numeral_font, numeral_size_px)

# How far above the baseline `font` inks its tallest figure at size_px
# (negative = up), from the glyphs themselves - the line box's ascent
# overstates it. The glyph's offset is its bitmap's, which the
# rasteriser pads by GLYPH_RECT_MARGIN_PX on every side (CardView's
# _cap_top() reads its "H" the same way).
static func figure_ink_top(font: Font, size_px: int) -> float:
	var ts: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var glyph_size := Vector2i(size_px, 0)
	var top: float = 0.0
	for figure in "0123456789":
		var glyph: int = ts.font_get_glyph_index(rid, size_px, figure.unicode_at(0), 0)
		ts.font_render_glyph(rid, glyph_size, glyph)
		top = minf(top, ts.font_get_glyph_offset(rid, glyph_size, glyph).y + GLYPH_RECT_MARGIN_PX)
	return top

# Sized to its content; BattleOverlay holds its right edge and numeral
# top where they belong (see BattleOverlay._apply_energy_anchor()).
func _relayout() -> void:
	if not is_inside_tree():
		return
	size = _content_size()
	queue_redraw()

func _draw() -> void:
	if numeral_font == null or label_font == null:
		return
	var baseline: float = _numeral_ascent()
	InkType.draw_run(self, numeral_font, _numeral_text(), Vector2(0.0, baseline), numeral_size_px, _ink)

	var label_color: Color = _ink
	label_color.a = energy_label_alpha
	InkType.draw_run(self, _energy_label_tracked, energy_label_text, Vector2(_numeral_width() + numeral_label_gap_px, baseline), energy_label_size_px, label_color)

	# Pips: the max row available or spent in place, then any over-max
	# ones past the gap - each at its own crossfade.
	var pip_top: float = baseline + pip_baseline_gap_px
	for i in _pip_lit.size():
		var lit: float = _pip_lit[i]
		var color: Color = _ink
		if i < _max_energy:
			color.a = lerpf(spent_pip_alpha, 1.0, lit)
		else:
			color.a = lit
		if color.a <= 0.0:
			continue
		draw_rect(Rect2(_pip_x(i), pip_top, pip_size.x, pip_size.y), color)
