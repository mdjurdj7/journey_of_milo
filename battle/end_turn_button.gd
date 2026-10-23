extends Button
class_name EndTurnButton

# End Turn as a line of ink, not a box: tracked caps in Alegreya Sans Bold
# with a rule beneath the text, no background, no border. Hover thickens
# the rule (rule_px -> rule_hover_px); disabled dims text and rule to
# disabled_alpha. A real Button still - pressed/focus/keyboard all work -
# just with every stylebox emptied and the rule drawn by _draw() over the
# text. Sized to its own text, its right edge held, so BattleOverlay can
# anchor it by that edge; the rule spans the text's width, not the
# control's. Every export re-applies live. The battle's END TURN sets its
# own size and rule in battle_overlay.tscn; the defaults here are Bide's
# DONE's.
#
# Disabled by BattleOverlay while the enemy turn runs (BattleController.
# turn_phase_changed), while a card is armed (HandContainer.
# armed_changed) and through the fight's opening hold (BattleController.
# entry_lock_changed) - the moments ending the turn makes no sense.

@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf"):
	set(value):
		label_font = value
		_restyle()
@export var font_size_px: int = 15:
	set(value):
		font_size_px = value
		_restyle()
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_restyle()
@export var rule_px: float = 2.0:
	set(value):
		rule_px = value
		queue_redraw()
@export var rule_hover_px: float = 3.0:
	set(value):
		rule_hover_px = value
		queue_redraw()
# Space between the text's descent and the rule's top.
@export var rule_gap_px: float = 3.0:
	set(value):
		rule_gap_px = value
		queue_redraw()
@export_range(0.0, 1.0) var disabled_alpha: float = 0.4:
	set(value):
		disabled_alpha = value
		_restyle()
@export var label_text: String = "END TURN"
# Quiet (set_quiet()): enabled, but its text and rule in grey ink - the
# ink at quiet_alpha - for a confirm that will do the least (KEEP NONE).
@export_range(0.0, 1.0) var quiet_alpha: float = 0.55:
	set(value):
		quiet_alpha = value
		if is_inside_tree():
			refresh_style()
# A note over the label (set_note() - the keep's "KEEP SLASH" over END
# TURN): right-aligned to it, its bottom note_gap_px over the label's
# top, in the same tracked caps at note_font_size_px - in ink, or grey
# ink when quiet. Drawn over the control, not in it: the button keeps its
# own size and place.
@export var note_font_size_px: int = 15:
	set(value):
		note_font_size_px = value
		queue_redraw()
@export var note_gap_px: float = 4.0:
	set(value):
		note_gap_px = value
		queue_redraw()

var _ink: Color = Color.BLACK
var _hovered: bool = false
var _quiet: bool = false
var _note: String = ""
var _note_quiet: bool = false

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
	var shown: Color = _text_ink()
	add_theme_color_override("font_color", shown)
	add_theme_color_override("font_hover_color", shown)
	add_theme_color_override("font_pressed_color", shown)
	add_theme_color_override("font_focus_color", shown)
	add_theme_color_override("font_hover_pressed_color", shown)
	add_theme_color_override("font_disabled_color", dim)
	_relayout()

# The label's ink: full, or grey while quiet.
func _text_ink() -> Color:
	var shown: Color = _ink
	if _quiet:
		shown.a = _ink.a * quiet_alpha
	return shown

# A new label: the text, and the size it takes - the right edge held.
func set_label(value: String) -> void:
	label_text = value
	text = value
	_relayout()

func set_quiet(quiet: bool) -> void:
	if quiet == _quiet:
		return
	_quiet = quiet
	refresh_style()

# The note over the label (note_*), empty for none.
func set_note(note: String, quiet: bool = false) -> void:
	if note == _note and quiet == _note_quiet:
		return
	_note = note
	_note_quiet = quiet
	queue_redraw()

func get_note() -> String:
	return _note

func _note_font() -> Font:
	return InkType.tracked(label_font, note_font_size_px, tracking_em)

# The box a note would take over the label, in this control's space.
func note_rect(note: String) -> Rect2:
	var font: Font = _note_font()
	var width: float = InkType.width(font, note, note_font_size_px)
	var height: float = font.get_height(note_font_size_px) if font != null else float(note_font_size_px)
	return Rect2(size.x - width, -note_gap_px - height, width, height)

# A live edit before the theme can be read waits for _ready().
func _restyle() -> void:
	if is_node_ready():
		refresh_style()

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

# The caps' baseline below this control's top - what a caller setting it
# on a line reads.
func text_ascent() -> float:
	var font: Font = get_theme_font("font")
	return font.get_ascent(font_size_px) if font != null else float(font_size_px)

# The rule's underside, below this control's bottom edge - what a caller
# stacking something beneath should clear.
func rule_bottom() -> float:
	return size.y + rule_gap_px + rule_hover_px

func _draw() -> void:
	var thickness: float = rule_hover_px if (_hovered and not disabled) else rule_px
	var color: Color = _text_ink()
	if disabled:
		color.a = disabled_alpha
	var rule_top: float = _text_height() + rule_gap_px
	draw_rect(Rect2(0.0, rule_top, _text_width(), thickness), color)
	if not _note.is_empty():
		var font: Font = _note_font()
		var box: Rect2 = note_rect(_note)
		var note_color: Color = _ink
		if _note_quiet:
			note_color.a = _ink.a * quiet_alpha
		if disabled:
			note_color.a = minf(note_color.a, disabled_alpha)
		var ascent: float = font.get_ascent(note_font_size_px) if font != null else float(note_font_size_px)
		InkType.draw_run(self, font, _note, Vector2(box.position.x, box.position.y + ascent), note_font_size_px, note_color)

func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	queue_redraw()
