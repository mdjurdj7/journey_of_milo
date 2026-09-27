extends Control
class_name TollLine

# The field HUD's Toll: "TOLL n" as a line of ink, the same shape as the
# DeckPanel's DECK line it sits beside - a tracked caps label (Alegreya
# Sans Bold at label_alpha) and the count right after in Alegreya Sans
# Regular at full ink. Drawn, not boxed; sized to its own text. Always
# shown on the field, 0 included.
#
# RegionField creates it in _setup_field_hud() and hands it the DECK line
# (sit_beside()) and the Toll to start on; after that RunState.toll_
# changed keeps it current. It follows the DECK line's rect and its
# visibility, so it goes when BattleOverlay hides the field line for a
# fight (the HPBar's own Toll block reads Toll there) and comes back with
# it.
#
# Reads the theme's Battle/ink token, so it inverts with the on-pale/
# on-dark value set (see BattleTheme) - re-read via refresh_style().

@export var label_text: String = "TOLL":
	set(value):
		label_text = value
		_relayout()
@export var label_font: Font = InkType.text_bold_font():
	set(value):
		label_font = value
		_refresh_if_ready()
@export var count_font: Font = InkType.text_font():
	set(value):
		count_font = value
		_refresh_if_ready()
@export var font_size_px: int = 12:
	set(value):
		font_size_px = value
		_refresh_if_ready()
# One tracking value for every caps label in the battle UI - see InkType.
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_refresh_if_ready()
@export_range(0.0, 1.0) var label_alpha: float = 0.62:
	set(value):
		label_alpha = value
		queue_redraw()
@export var label_count_gap_px: float = 6.0:
	set(value):
		label_count_gap_px = value
		_relayout()
# Space between the DECK line's right edge and this line's left.
@export var beside_gap_px: float = 14.0:
	set(value):
		beside_gap_px = value
		_follow()

var _toll: int = 0
var _ink: Color = Color.BLACK
var _label_font_tracked: Font = null
var _beside: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	RunState.toll_changed.connect(set_toll)
	refresh_style()

func set_toll(toll: int) -> void:
	_toll = maxi(toll, 0)
	_relayout()

# Sits this line to the right of `line`, bottom edges level, and keeps it
# there as that line resizes or moves - and shown only while it is.
func sit_beside(line: Control) -> void:
	if _beside != null:
		_beside.item_rect_changed.disconnect(_follow)
		_beside.visibility_changed.disconnect(_follow)
	_beside = line
	_beside.item_rect_changed.connect(_follow)
	_beside.visibility_changed.connect(_follow)
	_follow()

# Re-reads the theme's ink and rebuilds the tracked label font - called
# at _ready() and by RegionField right after it applies this region's
# value set to the shared BattleTheme.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_label_font_tracked = InkType.tracked(label_font, font_size_px, tracking_em)
	_relayout()

func _refresh_if_ready() -> void:
	if is_inside_tree():
		refresh_style()

func _count_text() -> String:
	return str(_toll)

func _relayout() -> void:
	if not is_inside_tree():
		return
	var width: float = InkType.width(_label_font_tracked, label_text, font_size_px) + label_count_gap_px + InkType.width(count_font, _count_text(), font_size_px)
	var height: float = label_font.get_height(font_size_px) if label_font != null else float(font_size_px)
	size = Vector2(width, height)
	_follow()
	queue_redraw()

func _follow() -> void:
	if _beside == null or not is_instance_valid(_beside):
		return
	visible = _beside.visible
	position = Vector2(_beside.position.x + _beside.size.x + beside_gap_px, _beside.position.y + _beside.size.y - size.y)

func _draw() -> void:
	if _label_font_tracked == null or count_font == null:
		return
	var label_color: Color = _ink
	label_color.a = label_alpha
	var baseline: float = label_font.get_ascent(font_size_px)
	var x: float = InkType.draw_run(self, _label_font_tracked, label_text, Vector2(0.0, baseline), font_size_px, label_color)
	x += label_count_gap_px
	InkType.draw_run(self, count_font, _count_text(), Vector2(x, baseline), font_size_px, _ink)
