extends Control
class_name BattleResources

# The player's energy and Toll, fixed bottom-left of the battle overlay
# (BattleOverlay places it; the DECK line - a PileReadout - sits beneath).
# Ink on the world, drawn: one circle per point of max energy, filled
# while available and hollow once spent, with "ENERGY" tracked beneath;
# then the Toll numeral - the largest number on screen - with "TOLL"
# beside it on the same baseline and a rule under the numeral in the toll
# keyline colour, the one colour the battle UI has outside the cards'
# two tones. Toll changes pop the numeral briefly (toll_pop_scale over
# toll_pop_time) so a Toll paid reads as an event, not a repaint.
#
# Driven by BattleOverlay from BattleController's energy_changed (current
# only - max comes from the player Combatant at setup, see set_energy())
# and toll_changed.

@export var numeral_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")
@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
@export var label_tracking_em: float = 0.16

@export_group("Energy")
@export var pip_diameter_px: float = 22.0
@export var pip_stroke_px: float = 2.0
@export var pip_gap_px: float = 10.0
@export var energy_label_text: String = "ENERGY"
@export var energy_label_size_px: int = 10
@export_range(0.0, 1.0) var energy_label_alpha: float = 0.62
@export var pip_label_gap_px: float = 6.0

@export_group("Toll")
@export var toll_numeral_size_px: int = 52
@export var toll_label_text: String = "TOLL"
@export var toll_label_size_px: int = 12
@export var toll_label_gap_px: float = 8.0
@export var toll_rule_px: float = 2.0
@export var toll_rule_gap_px: float = 4.0
@export var toll_pop_scale: float = 1.15
@export var toll_pop_time: float = 0.22
# Space between the ENERGY line and the Toll numeral's top.
@export var section_gap_px: float = 14.0

var _energy: int = 0
var _max_energy: int = 0
var _toll: int = 0
var _toll_pop: float = 1.0
var _pop_tween: Tween = null
var _ink: Color = Color.BLACK
var _toll_rule_color: Color = Color.WHITE
var _energy_label_tracked: Font = null
var _toll_label_tracked: Font = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_style()

# Re-reads the theme's ink and toll rule colour - called at _ready() and by
# BattleOverlay's F2 flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_toll_rule_color = get_theme_color("toll_rule", "Battle")
	_energy_label_tracked = InkType.tracked(label_font, energy_label_size_px, label_tracking_em)
	_toll_label_tracked = InkType.tracked(label_font, toll_label_size_px, label_tracking_em)
	_relayout()

func set_energy(current: int, max_energy: int) -> void:
	_energy = maxi(current, 0)
	_max_energy = maxi(max_energy, 0)
	_relayout()

func set_toll(toll: int) -> void:
	var changed: bool = toll != _toll
	_toll = maxi(toll, 0)
	if changed:
		_pop()
	_relayout()

func _pop() -> void:
	if _pop_tween != null:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pop_tween.tween_method(_set_pop, 1.0, toll_pop_scale, toll_pop_time * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pop_tween.tween_method(_set_pop, toll_pop_scale, 1.0, toll_pop_time * 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_pop(value: float) -> void:
	_toll_pop = value
	queue_redraw()

# --- Geometry, top to bottom ---

func _pips_width() -> float:
	if _max_energy <= 0:
		return 0.0
	return _max_energy * pip_diameter_px + (_max_energy - 1) * pip_gap_px

func _energy_label_height() -> float:
	return label_font.get_height(energy_label_size_px) if label_font != null else float(energy_label_size_px)

func _toll_ascent() -> float:
	return numeral_font.get_ascent(toll_numeral_size_px) if numeral_font != null else float(toll_numeral_size_px)

func _toll_descent() -> float:
	return numeral_font.get_descent(toll_numeral_size_px) if numeral_font != null else 0.0

func _toll_top() -> float:
	return pip_diameter_px + pip_label_gap_px + _energy_label_height() + section_gap_px

func _toll_row_width() -> float:
	return InkType.width(numeral_font, str(_toll), toll_numeral_size_px) + toll_label_gap_px + InkType.width(_toll_label_tracked, toll_label_text, toll_label_size_px)

func _content_size() -> Vector2:
	var width: float = maxf(_pips_width(), maxf(InkType.width(_energy_label_tracked, energy_label_text, energy_label_size_px), _toll_row_width()))
	var height: float = _toll_top() + _toll_ascent() + _toll_descent() + toll_rule_gap_px + toll_rule_px
	return Vector2(width, height)

# Sized to its content; the bottom-left corner stays put (BattleOverlay
# anchors this by its bottom edge).
func _relayout() -> void:
	if not is_inside_tree():
		return
	var bottom: float = position.y + size.y
	size = _content_size()
	position.y = bottom - size.y
	queue_redraw()

func _draw() -> void:
	if numeral_font == null or label_font == null:
		return
	# Energy pips: filled while available, a stroked ring once spent.
	var radius: float = pip_diameter_px * 0.5
	for i in _max_energy:
		var centre := Vector2(i * (pip_diameter_px + pip_gap_px) + radius, radius)
		if i < _energy:
			draw_circle(centre, radius, _ink, true, -1.0, true)
		else:
			draw_circle(centre, radius - pip_stroke_px * 0.5, _ink, false, pip_stroke_px, true)

	var energy_label_color: Color = _ink
	energy_label_color.a = energy_label_alpha
	var energy_baseline: float = pip_diameter_px + pip_label_gap_px + label_font.get_ascent(energy_label_size_px)
	InkType.draw_run(self, _energy_label_tracked, energy_label_text, Vector2(0.0, energy_baseline), energy_label_size_px, energy_label_color)

	# Toll: the numeral pops about its baseline-left corner so the rule and
	# label hold still under it.
	var toll_baseline: float = _toll_top() + _toll_ascent()
	var numeral_text: String = str(_toll)
	var numeral_width: float = InkType.width(numeral_font, numeral_text, toll_numeral_size_px)
	if _toll_pop != 1.0:
		draw_set_transform(Vector2(0.0, toll_baseline), 0.0, Vector2.ONE * _toll_pop)
		InkType.draw_run(self, numeral_font, numeral_text, Vector2.ZERO, toll_numeral_size_px, _ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		InkType.draw_run(self, numeral_font, numeral_text, Vector2(0.0, toll_baseline), toll_numeral_size_px, _ink)
	InkType.draw_run(self, _toll_label_tracked, toll_label_text, Vector2(numeral_width + toll_label_gap_px, toll_baseline), toll_label_size_px, _ink)

	var rule_top: float = toll_baseline + _toll_descent() + toll_rule_gap_px
	draw_rect(Rect2(0.0, rule_top, numeral_width, toll_rule_px), _toll_rule_color)
