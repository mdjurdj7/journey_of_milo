extends Button
class_name EndTurnButton

# End Turn as a line of ink, not a box: tracked caps in Alegreya Sans Bold
# with a rule beneath the text, no background, no border. Hover thickens
# the rule (rule_px -> rule_hover_px); disabled dims text and rule to
# disabled_alpha. A real Button still - pressed/focus/keyboard all work -
# just with every stylebox emptied and the rule drawn by _draw() over the
# text. Sized to its own text so BattleOverlay can anchor it flush
# bottom-right; the rule spans the text's width, not the control's.
#
# Disabled by BattleOverlay while the enemy turn runs (BattleController.
# turn_phase_changed) and while a card is armed (HandContainer.
# armed_changed) - the two moments ending the turn makes no sense.

@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
@export var font_size_px: int = 15
@export var tracking_em: float = 0.16
@export var rule_px: float = 2.0
@export var rule_hover_px: float = 3.0
# Space between the text's descent and the rule's top.
@export var rule_gap_px: float = 3.0
@export_range(0.0, 1.0) var disabled_alpha: float = 0.4
@export var label_text: String = "END TURN"

var _ink: Color = Color.BLACK
var _hovered: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = label_text
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)
	add_theme_constant_override("outline_size", 0)
	mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
	refresh_style()

# Re-reads the theme's ink - called at _ready() and by BattleOverlay's F2
# flip. Font/size/tracking are applied here too so the text's own metrics
# and _draw()'s rule agree.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	var tracked: Font = InkType.tracked(label_font, font_size_px, tracking_em)
	if tracked != null:
		add_theme_font_override("font", tracked)
	add_theme_font_size_override("font_size", font_size_px)
	var dim: Color = _ink
	dim.a = disabled_alpha
	add_theme_color_override("font_color", _ink)
	add_theme_color_override("font_hover_color", _ink)
	add_theme_color_override("font_pressed_color", _ink)
	add_theme_color_override("font_focus_color", _ink)
	add_theme_color_override("font_hover_pressed_color", _ink)
	add_theme_color_override("font_disabled_color", dim)
	_relayout()

func _text_width() -> float:
	var font: Font = get_theme_font("font")
	return InkType.width(font, text, font_size_px)

func _text_height() -> float:
	var font: Font = get_theme_font("font")
	return font.get_height(font_size_px) if font != null else float(font_size_px)

# Sized to the text alone (Button always centres its text vertically, so
# any extra height would push the caps off their baseline); the rule is
# drawn just below the control's own rect - see rule_bottom(). The right
# edge stays put so the bottom-right anchor holds if the text changes.
func _relayout() -> void:
	if not is_inside_tree():
		return
	var right_edge: float = position.x + size.x
	var new_size := Vector2(_text_width(), _text_height())
	custom_minimum_size = new_size
	size = new_size
	position.x = right_edge - new_size.x
	queue_redraw()

# The rule's underside, below this control's bottom edge - what a caller
# stacking something beneath should clear.
func rule_bottom() -> float:
	return size.y + rule_gap_px + rule_hover_px

func _draw() -> void:
	var thickness: float = rule_hover_px if (_hovered and not disabled) else rule_px
	var color: Color = _ink
	if disabled:
		color.a = disabled_alpha
	var rule_top: float = _text_height() + rule_gap_px
	draw_rect(Rect2(0.0, rule_top, _text_width(), thickness), color)

func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	queue_redraw()
