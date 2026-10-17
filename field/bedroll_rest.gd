extends Node
class_name BedrollRest

# Resting on the Bedroll: a one-line confirm, then a night, then the day
# again. Made by RegionField.open_bedroll_rest() when the HUD's BEDROLL
# is clicked - on the field only, never in a fight, never at full HP -
# with the field frozen under it (PROCESS_MODE_DISABLED, as the screens
# freeze it) and the Wanderer standing still in his idle (there is no
# kneel or lie-down clip; Wanderer.stand_still()). This node runs ALWAYS.
#
# The confirm: "REST?  YES / NO" in the system voice's tracked caps, ink
# on the world, its baseline confirm_gap_px over the HUD row, left-aligned
# with BEDROLL. YES and NO carry the title menu's focus language - the
# utility grey at rest, full ink with the short hairline to the left when
# focused. The mouse focuses by hovering and answers by clicking; a click
# anywhere else, a right click and ui_cancel are NO; ui_left/ui_right move
# between the two, ui_accept answers. Nothing is focused until the mouse
# or a key says so. NO closes it and the field goes on, the Bedroll kept.
#
# YES is the night: the field dims through its fog to a cool blue-grey -
# the RegionSky's fog colour eased to night_fog_color (the Sea's own fog
# copy and the enemies' fog follow it on fog_changed) and an overlay that
# multiplies the 3D view, water and all, by night_tint, under the HUD
# (layer 0, FieldHUD is 1) - over night_in_sec. Not a lighting change:
# the sun and ambient stay as they are. It holds night_hold_sec; the
# Bedroll is spent as the hold begins (RunState.use_bedroll()), the HUD
# goes to its on-dark value set (bone - hud_value_set) so it stays
# readable on the night, and the HP it restores (BedrollData.heal_
# amount()) rises through heal_rise_sec of the hold, a point at a time. Then the day comes back over night_out_
# sec, and as it does one world-voice line (WorldVoiceLine, Spectral, one
# line) says one of rest_lines, picked at random, held line_hold_sec
# between its fades - the HUD back to the day's value set (day_on_dark)
# first, so the line is said in it. The fog colour returns to what it
# was; the field stays day. No rest screen.

# The confirm closed or the night is over - whether it was a rest.
signal finished(rested: bool)

enum Phase { CONFIRM, NIGHT, DONE }
enum Answer { YES, NO }

@export_group("Confirm")
@export var confirm_text: String = "REST?"
@export var yes_text: String = "YES"
@export var no_text: String = "NO"
@export var separator_text: String = "/"
@export var confirm_size_px: int = 15
@export_range(0.0, 1.0) var confirm_tracking_em: float = 0.16
# Between "REST?" and YES, and around the separator.
@export var confirm_question_gap_px: float = 30.0
@export var confirm_word_gap_px: float = 18.0
# The confirm's baseline this far over the HUD row's top.
@export var confirm_gap_px: float = 14.0
# The title menu's unfocused item: CardView's keyline_utility.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0)
@export var hairline_length_px: float = 10.0
@export var hairline_gap_px: float = 5.0
@export var hairline_thickness_px: float = 1.0
@export_group("")

@export_group("Night")
# The 3D view times this at full night - cool blue-grey, no warm cast.
@export var night_tint: Color = Color(0.36, 0.41, 0.50, 1.0)
# The fog the field dims into.
@export var night_fog_color: Color = Color(0.30, 0.34, 0.41, 1.0)
@export var night_in_sec: float = 0.9
@export var night_hold_sec: float = 2.0
@export var night_out_sec: float = 0.9
# Over how much of the hold the HP rises.
@export var heal_rise_sec: float = 1.4
@export_group("")

@export_group("Line")
@export var rest_lines: PackedStringArray = PackedStringArray([
	"The tide came in while you slept, and went out again.",
	"Nothing came in the night.",
	"The tower kept broadcasting.",
])
# Between the line's fades - 0.5 in, this, 0.5 out: about two seconds.
@export var line_hold_sec: float = 1.0
@export_group("")

# Switches the field HUD's value set (RegionField.set_hud_value_set());
# day_on_dark is the set the day uses. Set by RegionField before the node
# enters the tree.
var hud_value_set: Callable = Callable()
var day_on_dark: bool = false

var phase: Phase = Phase.CONFIRM
# The line said on the way back, once said.
var said_line: String = ""

var _bedroll: BedrollData = null
var _sky: RegionSky = null
var _hud: Node = null
var _anchor: Control = null
var _ink: Color = Color.BLACK
var _day_fog_color: Color = Color.WHITE
var _healed: int = 0
var _heal_target: int = 0

var _confirm_layer: CanvasLayer = null
var _confirm: Control = null
var _font: Font = null
var _focus: int = -1
var _mouse_on: int = -1
var _night_layer: CanvasLayer = null
var _overlay: ColorRect = null

# Called by RegionField before the node enters the tree: the Bedroll's
# data, the field's sky, its HUD (for the line) and the HUD item the
# confirm sits over.
func setup(bedroll: BedrollData, sky: RegionSky, hud: Node, anchor: Control) -> void:
	_bedroll = bedroll
	_sky = sky
	_hud = hud
	_anchor = anchor

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _anchor != null:
		_ink = _anchor.get_theme_color("ink", "Battle")
	_font = InkType.tracked(InkType.text_bold_font(), confirm_size_px, confirm_tracking_em)
	_confirm_layer = CanvasLayer.new()
	_confirm_layer.name = "Confirm"
	_confirm_layer.layer = 100
	add_child(_confirm_layer)
	_confirm = Control.new()
	_confirm.name = "Line"
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click anywhere is an answer, never a move order.
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.gui_input.connect(_on_gui_input)
	_confirm.draw.connect(_draw_confirm)
	_confirm_layer.add_child(_confirm)

# --- The confirm ---

func _confirm_origin() -> Vector2:
	if _anchor == null:
		return Vector2(48.0, 960.0)
	var rect: Rect2 = _anchor.get_global_rect()
	return Vector2(roundf(rect.position.x), roundf(rect.position.y - confirm_gap_px))

func _word(answer: int) -> String:
	return yes_text if answer == Answer.YES else no_text

# Each answer's left edge on the baseline.
func _answer_left(answer: int) -> float:
	var x: float = _confirm_origin().x + InkType.width(_font, confirm_text, confirm_size_px) + confirm_question_gap_px
	if answer == Answer.NO:
		x += InkType.width(_font, yes_text, confirm_size_px) + confirm_word_gap_px + InkType.width(_font, separator_text, confirm_size_px) + confirm_word_gap_px
	return roundf(x)

# An answer and the hairline's room to its left.
func _answer_rect(answer: int) -> Rect2:
	var left: float = _answer_left(answer)
	var baseline: float = _confirm_origin().y
	var hit_left: float = left - hairline_gap_px - hairline_length_px * 0.5
	return Rect2(hit_left, baseline - float(confirm_size_px) * 1.1, left + InkType.width(_font, _word(answer), confirm_size_px) - hit_left, float(confirm_size_px) * 1.5)

func _draw_confirm() -> void:
	if phase != Phase.CONFIRM:
		return
	var origin: Vector2 = _confirm_origin()
	InkType.draw_run(_confirm, _font, confirm_text, origin, confirm_size_px, _ink)
	var separator_left: float = _answer_left(Answer.YES) + InkType.width(_font, yes_text, confirm_size_px) + confirm_word_gap_px
	InkType.draw_run(_confirm, _font, separator_text, Vector2(roundf(separator_left), origin.y), confirm_size_px, unfocused_color)
	for answer: int in [Answer.YES, Answer.NO]:
		var left: float = _answer_left(answer)
		var focused: bool = _focus == answer
		InkType.draw_run(_confirm, _font, _word(answer), Vector2(left, origin.y), confirm_size_px, _ink if focused else unfocused_color)
		if focused:
			var mid: float = origin.y - float(confirm_size_px) * 0.35
			_confirm.draw_rect(Rect2(left - hairline_gap_px - hairline_length_px, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), _ink)

func _answer_at(position: Vector2) -> int:
	for answer: int in [Answer.YES, Answer.NO]:
		if _answer_rect(answer).has_point(position):
			return answer
	return -1

func _set_focus(answer: int) -> void:
	if answer == _focus:
		return
	_focus = answer
	_confirm.queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if phase != Phase.CONFIRM:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _answer_at(motion.position)
		if under != _mouse_on:
			if under >= 0:
				_set_focus(under)
			elif _focus == _mouse_on:
				_set_focus(-1)
			_mouse_on = under
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	_confirm.accept_event()
	if button.button_index == MOUSE_BUTTON_LEFT:
		var answer: int = _answer_at(button.position)
		answer_confirm(answer == Answer.YES)
	elif button.button_index == MOUSE_BUTTON_RIGHT:
		answer_confirm(false)

func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.CONFIRM:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_set_focus(Answer.NO if _focus == Answer.YES else Answer.YES)
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			answer_confirm(_focus == Answer.YES)
	elif event.is_action_pressed("ui_cancel"):
		answer_confirm(false)
	else:
		return
	get_viewport().set_input_as_handled()

# The confirm answered - the first answer wins. Public for probes.
func answer_confirm(yes: bool) -> void:
	if phase != Phase.CONFIRM:
		return
	_confirm_layer.queue_free()
	_confirm_layer = null
	if not yes:
		_finish(false)
		return
	_begin_night()

# --- The night ---

func _begin_night() -> void:
	phase = Phase.NIGHT
	_night_layer = CanvasLayer.new()
	_night_layer.name = "Night"
	# Over the 3D view, under FieldHUD (1): the HUD and the line stay as
	# they are.
	_night_layer.layer = 0
	add_child(_night_layer)
	_overlay = ColorRect.new()
	_overlay.name = "Tint"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.color = Color.WHITE
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_overlay.material = multiply
	_night_layer.add_child(_overlay)
	if _sky != null:
		_day_fog_color = _sky.fog_color
	_heal_target = _bedroll.heal_amount(RunState.player_max_hp) if _bedroll != null else 0
	var tween: Tween = create_tween()
	tween.tween_method(_set_night, 0.0, 1.0, maxf(night_in_sec, 0.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_begin_hold)
	tween.tween_interval(maxf(night_hold_sec, 0.0))
	tween.tween_callback(_say_line)
	tween.tween_method(_set_night, 1.0, 0.0, maxf(night_out_sec, 0.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_finish.bind(true))

# 0 day, 1 full night: the overlay's tint and the fog's colour, eased
# together.
func _set_night(amount: float) -> void:
	if _overlay != null:
		_overlay.color = Color.WHITE.lerp(night_tint, amount)
	if _sky != null:
		_sky.fog_color = _day_fog_color.lerp(night_fog_color, amount)

# The hold: the Bedroll spent, the HP rising a point at a time.
func _begin_hold() -> void:
	_set_hud_on_dark(true)
	RunState.use_bedroll()
	var room: int = maxi(RunState.player_max_hp - RunState.player_hp, 0)
	_heal_target = mini(_heal_target, room)
	var rise: Tween = create_tween()
	rise.tween_method(_heal_to, 0.0, float(_heal_target), maxf(minf(heal_rise_sec, night_hold_sec), 0.0))
	rise.tween_callback(_heal_to.bind(float(_heal_target)))

func _heal_to(amount: float) -> void:
	var step: int = mini(floori(amount), _heal_target) - _healed
	if step <= 0:
		return
	_healed += step
	RunState.heal(step)

func _say_line() -> void:
	# Whatever the rise hasn't reached by now lands at once.
	_heal_to(float(_heal_target))
	_set_hud_on_dark(day_on_dark)
	RunLogger.player_healed(_healed, "bedroll")
	if rest_lines.is_empty():
		return
	var pick := RandomNumberGenerator.new()
	pick.randomize()
	said_line = rest_lines[pick.randi_range(0, rest_lines.size() - 1)]
	var voice := WorldVoiceLine.on_hud(_hud)
	if voice != null:
		voice.show_line(said_line, line_hold_sec)

func _set_hud_on_dark(on_dark: bool) -> void:
	if hud_value_set.is_valid():
		hud_value_set.call(on_dark)

# What the rest restored so far.
func get_healed() -> int:
	return _healed

func _finish(rested: bool) -> void:
	phase = Phase.DONE
	if _sky != null and rested:
		_sky.fog_color = _day_fog_color
	finished.emit(rested)
	queue_free()
