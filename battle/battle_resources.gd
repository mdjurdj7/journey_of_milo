extends Control
class_name BattleResources

# The player's energy, fixed bottom-left of the battle overlay
# (BattleOverlay places it; the DECK line - a DeckPanel - sits beneath).
# Ink on the world, drawn: one circle per point of max energy, filled
# while available and hollow once spent, with "ENERGY" tracked beneath.
# Toll lives on the Wanderer's own readout (see HPBar), not here.
#
# Driven by BattleOverlay from BattleController's energy_changed (current
# only - max comes from the player Combatant at setup, see set_energy()).

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

# --- Geometry, top to bottom ---

func _pips_width() -> float:
	if _max_energy <= 0:
		return 0.0
	return _max_energy * pip_diameter_px + (_max_energy - 1) * pip_gap_px

func _energy_label_height() -> float:
	return label_font.get_height(energy_label_size_px) if label_font != null else float(energy_label_size_px)

func _content_size() -> Vector2:
	var width: float = maxf(_pips_width(), InkType.width(_energy_label_tracked, energy_label_text, energy_label_size_px))
	var height: float = pip_diameter_px + pip_label_gap_px + _energy_label_height()
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
	if label_font == null:
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
