extends Control
class_name BattleResources

# The player's energy, fixed bottom-left of the battle overlay
# (BattleOverlay places it; the DECK line - a DeckPanel - sits beneath).
# An instrument readout in ink, drawn: the current value as a large
# numeral with "ENERGY" tracked on its baseline (the way TOLL sits beside
# its numeral, see HPBar), and under them a tally - one short rule per
# point of max energy, full ink while available, faint once spent. No
# "/ max": the tally carries capacity. Past tally_max_points the tally is
# dropped and the numeral stands alone.
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
@export var numeral_size_px: int = 42:
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

@export_group("Tally")
@export var tally_segment_width_px: float = 22.0:
	set(value):
		tally_segment_width_px = value
		_relayout()
@export var tally_thickness_px: float = 3.0:
	set(value):
		tally_thickness_px = value
		_relayout()
@export var tally_gap_px: float = 8.0:
	set(value):
		tally_gap_px = value
		_relayout()
# Between the numeral's baseline and the tally's top.
@export var tally_baseline_gap_px: float = 8.0:
	set(value):
		tally_baseline_gap_px = value
		_relayout()
@export_range(0.0, 1.0) var tally_spent_alpha: float = 0.22:
	set(value):
		tally_spent_alpha = value
		queue_redraw()
# Max energy above this hides the tally - the numeral alone reads.
@export var tally_max_points: int = 6:
	set(value):
		tally_max_points = value
		_relayout()

var _energy: int = 0
var _max_energy: int = 0
var _ink: Color = Color.BLACK
var _energy_label_tracked: Font = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_style()

# Re-reads the theme's ink - called at _ready() and by BattleOverlay's F2
# flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_energy_label_tracked = InkType.tracked(label_font, energy_label_size_px, label_tracking_em)
	_relayout()

func set_energy(current: int, max_energy: int) -> void:
	_energy = maxi(current, 0)
	_max_energy = maxi(max_energy, 0)
	_relayout()

# Export setters run before _ready() too - only restyle once in the tree.
func _restyle() -> void:
	if is_inside_tree():
		refresh_style()

# --- Geometry, top to bottom ---

func _numeral_text() -> String:
	return str(_energy)

func _numeral_ascent() -> float:
	return numeral_font.get_ascent(numeral_size_px) if numeral_font != null else float(numeral_size_px)

func _numeral_width() -> float:
	return InkType.width(numeral_font, _numeral_text(), numeral_size_px) if numeral_font != null else 0.0

func _shows_tally() -> bool:
	return _max_energy > 0 and _max_energy <= tally_max_points

func _tally_width() -> float:
	if not _shows_tally():
		return 0.0
	return _max_energy * tally_segment_width_px + (_max_energy - 1) * tally_gap_px

func _content_size() -> Vector2:
	var label_width: float = InkType.width(_energy_label_tracked, energy_label_text, energy_label_size_px) if _energy_label_tracked != null else 0.0
	var width: float = maxf(_numeral_width() + numeral_label_gap_px + label_width, _tally_width())
	var height: float = _numeral_ascent()
	if _shows_tally():
		height += tally_baseline_gap_px + tally_thickness_px
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
	var baseline: float = _numeral_ascent()
	InkType.draw_run(self, numeral_font, _numeral_text(), Vector2(0.0, baseline), numeral_size_px, _ink)

	var label_color: Color = _ink
	label_color.a = energy_label_alpha
	InkType.draw_run(self, _energy_label_tracked, energy_label_text, Vector2(_numeral_width() + numeral_label_gap_px, baseline), energy_label_size_px, label_color)

	if not _shows_tally():
		return
	# Tally: one rule per point of max energy, spent ones faint.
	var spent_color: Color = _ink
	spent_color.a = tally_spent_alpha
	var tally_top: float = baseline + tally_baseline_gap_px
	for i in _max_energy:
		var x: float = i * (tally_segment_width_px + tally_gap_px)
		draw_rect(Rect2(x, tally_top, tally_segment_width_px, tally_thickness_px), _ink if i < _energy else spent_color)
