extends Control
class_name TroughChoice

# A trough's two choices, shown beside it on the world - LootScreen's
# column without its item row: no scrim, no header, and the field never
# stops. TroughProp opens it from a click on the trough in reach and
# parents it under FieldHUD (see TroughProp._open_choice()).
#
# Placed every physics tick the way LootScreen is: the anchor - the
# trough plus anchor_offset, x metres along the camera's right and y
# metres up - is unprojected, and this control's scale follows camera
# distance (DistanceScale). The anchor is the column's left edge, level
# with its middle.
#
# DRINK and LEAVE in the title menu's focus language, LootScreen's: the
# focused item in full ink (the Battle ink token) with a short hairline
# to its left, the other in the utility grey with none. DRINK has focus
# on open. ui_up/ui_down move it (wrapping), ui_accept activates;
# hovering an item focuses it and a click activates. ui_cancel and a
# right click anywhere are LEAVE, and that right click is spent on
# closing. The two items are the only things here that stop the mouse.
#
# DRINK calls TroughProp.drink() - the heal, the line, spent for the run
# - and closes. LEAVE closes and changes nothing, and so does walking
# out of the trough's reach or the field freezing: the next click on the
# trough opens this again.

signal closed()

enum Item { DRINK, LEAVE }

# x: metres along the camera's right from the trough; y: metres up.
@export var anchor_offset: Vector2 = Vector2(0.8, 0.6)
@export var text_outline_px: int = 0
@export var open_fade_sec: float = 0.18

@export_group("Choices")
# %d is the trough's heal_amount.
@export var drink_text_format: String = "Drink (+%d HP)"
@export var leave_text: String = "Leave it"
@export var choice_size_px: int = 22:
	set(value):
		choice_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var choice_tracking_em: float = 0.16:
	set(value):
		choice_tracking_em = value
		_rebuild_fonts()
@export var choice_gap_px: float = 14.0
# The title menu's unfocused item: CardView's keyline_utility.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0)
@export var hairline_length_px: float = 28.0
@export var hairline_gap_px: float = 14.0
@export var hairline_thickness_px: float = 1.0
@export_group("")

# Apparent-size correction, LootScreen's knobs and defaults.
@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0
@export_group("")

const THEME_PATH := "res://ui/battle_theme.tres"

var _trough: TroughProp = null
var _wanderer: Node3D = null
var _region_field: Node = null
var _focused: int = Item.DRINK
var _done: bool = false
var _closing: bool = false
var _choices: Array[Control] = []
var _choice_font: Font = null

# Called by TroughProp before this enters the tree.
func setup(trough: TroughProp, wanderer: Node3D, region_field: Node) -> void:
	_trough = trough
	_wanderer = wanderer
	_region_field = region_field

func _ready() -> void:
	# After CameraRig has placed the camera this tick (EnemyStatus's reason).
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = load(THEME_PATH) as Theme
	_rebuild_fonts()

	for index in 2:
		var choice := Control.new()
		choice.name = "Drink" if index == Item.DRINK else "Leave"
		choice.mouse_filter = Control.MOUSE_FILTER_STOP
		choice.mouse_entered.connect(_set_focus.bind(index))
		choice.gui_input.connect(_on_choice_gui_input.bind(index))
		add_child(choice)
		_choices.append(choice)

	if _trough == null:
		close()
		return

	visible = false
	modulate.a = 0.0
	if open_fade_sec > 0.0:
		create_tween().tween_property(self, "modulate:a", 1.0, open_fade_sec)
	else:
		modulate.a = 1.0

func _rebuild_fonts() -> void:
	_choice_font = InkType.tracked(InkType.text_bold_font(), choice_size_px, choice_tracking_em)
	queue_redraw()

func _labels() -> Array[String]:
	var heal: int = _trough.heal_amount if _trough != null and is_instance_valid(_trough) else 0
	var drink_text: String = drink_text_format % heal if drink_text_format.contains("%d") else drink_text_format
	return [drink_text, leave_text]

# --- Tick ---

func _physics_process(_delta: float) -> void:
	if _done or _closing:
		return
	if _trough == null or not is_instance_valid(_trough):
		close()
		return
	# The field froze under us (a fight, the floor transition) - FieldHUD
	# runs ALWAYS, so this would otherwise sit over the battle.
	if _region_field != null and is_instance_valid(_region_field) and not _region_field.can_process():
		close()
		return
	if _wanderer != null and is_instance_valid(_wanderer) and not _trough.can_open_from(_wanderer.global_position):
		close()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var anchor: Vector3 = _trough.global_position + right * anchor_offset.x + Vector3.UP * anchor_offset.y
	if camera.is_position_behind(anchor):
		visible = false
		return
	visible = true
	_layout()
	var distance: float = camera.global_position.distance_to(anchor)
	scale = Vector2.ONE * DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	position = (camera.unproject_position(anchor) - pivot_offset).round()
	queue_redraw()

# --- Layout (local space; the anchor is pivot_offset) ---

func _choices_width() -> float:
	var widest: float = 0.0
	for label in _labels():
		widest = maxf(widest, InkType.width(_choice_font, label, choice_size_px))
	return hairline_length_px + hairline_gap_px + widest

func _choice_top(index: int) -> float:
	return float(index) * (float(choice_size_px) + choice_gap_px)

# The two choices, left-aligned, the column's middle on the anchor.
func _layout() -> void:
	var row_height: float = float(choice_size_px) * 1.3
	size = Vector2(_choices_width(), _choice_top(1) + row_height)
	pivot_offset = Vector2(0.0, size.y * 0.5)
	for index in _choices.size():
		_choices[index].position = Vector2(0.0, _choice_top(index))
		_choices[index].size = Vector2(_choices_width(), row_height)

# --- Draw ---

func _ink() -> Color:
	return get_theme_color("ink", "Battle")

func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	if text_outline_px > 0:
		var outline: Color = get_theme_color("bone", "Battle")
		outline.a *= color.a
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	InkType.draw_run(self, font, text, origin, size_px, color)

func _draw() -> void:
	if _trough == null or _choices.size() < 2:
		return
	var ink: Color = _ink()
	var labels: Array[String] = _labels()
	var label_left: float = hairline_length_px + hairline_gap_px
	for index in labels.size():
		var focused: bool = index == _focused
		var baseline: float = _choice_top(index) + float(choice_size_px)
		_text(_choice_font, labels[index], Vector2(label_left, baseline), choice_size_px, ink if focused else unfocused_color)
		if focused:
			var mid: float = baseline - float(choice_size_px) * 0.35
			draw_rect(Rect2(0.0, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), ink)

# --- Input ---

func _set_focus(index: int) -> void:
	if _done or index == _focused:
		return
	_focused = index
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _done or _closing or not visible:
		return
	if event.is_action_pressed("ui_down"):
		_set_focus(posmod(_focused + 1, 2))
	elif event.is_action_pressed("ui_up"):
		_set_focus(posmod(_focused - 1, 2))
	elif event.is_action_pressed("ui_accept"):
		_activate(_focused)
	elif event.is_action_pressed("ui_cancel") or _is_right_press(event):
		_activate(Item.LEAVE)
	else:
		return
	get_viewport().set_input_as_handled()

func _is_right_press(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed

func _on_choice_gui_input(event: InputEvent, index: int) -> void:
	if _done:
		return
	if _is_right_press(event):
		_activate(Item.LEAVE)
		accept_event()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_set_focus(index)
	_activate(index)
	accept_event()

# The one gate: the first activation wins.
func _activate(index: int) -> void:
	if _done:
		return
	_done = true
	var hp_before: int = RunState.player_hp
	var drank: bool = index == Item.DRINK and _trough != null and is_instance_valid(_trough)
	if drank:
		_trough.drink()
	RunLogger.event("trough", {"drank": drank, "hp_before": hp_before, "hp_after": RunState.player_hp})
	close()

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
