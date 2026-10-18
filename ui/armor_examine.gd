extends CanvasLayer
class_name ArmorExamine

# A worn piece looked at closely: its ItemPlate at examine_scale (the one
# plate scale, every host's: the hovers', the offers'), centred
# over the dimmed field - KeepsakeExamine, for armor. It grows out of
# from_rect (the HUD row's WORN line; empty: from the middle) while an ink
# scrim fades in, over inspect_duration_sec, and goes back the same way.
#
# Two uses (RegionField opens both, locking the field under it until
# `closed`):
#   the piece on the sand (WorldArmor) - with_choice: TAKE and LEAVE in
#     the strip under the plate, and the "Replaces ..." line when
#     something is worn. TAKE
#     closes with taken = true; LEAVE, a click off the plate, Escape or a
#     right click close with false - the piece stays where it lies.
#   the piece worn (the WORN line) - no choice: any click, Escape or a
#     right click closes.
#   the run's weapon (the WEAPON line, setup_weapon()) - the same, on its
#     weapon plate (ItemPlate.set_weapon()).
#   a weapon offered (the Greyshelf's - setup_weapon() with_choice): TAKE
#     and LEAVE, and "REPLACES" the weapon carried, on the same terms as
#     the piece on the sand - LEAVE and every other close is false.
# Layer 100, running ALWAYS.

signal closed(taken: bool)

@export var examine_scale: float = 1.0
@export var inspect_duration_sec: float = 0.15
@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.35)

var _piece: TrinketData = null
var _weapon: WeaponData = null
var _worn: TrinketData = null
# The weapon carried, which taking an offered one would replace.
var _carried: WeaponData = null
var _with_choice: bool = false
var _from_rect: Rect2 = Rect2()
var _scrim: ColorRect = null
var _plate: ItemPlate = null
var _tween: Tween = null
var _closing: bool = false

# Called before the layer enters the tree. `worn`: the piece worn now,
# which taking this would replace (with_choice only).
func setup(piece: TrinketData, worn: TrinketData, with_choice: bool, from_rect: Rect2 = Rect2()) -> void:
	_piece = piece
	_worn = worn
	_with_choice = with_choice
	_from_rect = from_rect

# The weapon instead of a piece - no choice, or for an offer with_choice
# and `carried`, the weapon taking it would replace. Called before the
# layer enters the tree.
func setup_weapon(weapon: WeaponData, from_rect: Rect2 = Rect2(), carried: WeaponData = null, with_choice: bool = false) -> void:
	setup(null, null, with_choice, from_rect)
	_weapon = weapon
	_carried = carried

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_gui_input)
	_scrim.modulate.a = 0.0
	add_child(_scrim)
	_plate = ItemPlate.new()
	_plate.name = "Plate"
	add_child(_plate)
	if _piece == null and _weapon == null:
		close(false)
		return
	if _weapon != null:
		_plate.set_weapon(_weapon, _carried if _with_choice else null, _with_choice)
	else:
		_plate.set_piece(_piece, _worn if _with_choice else null, _with_choice)
	_plate.chosen.connect(close)
	_open()
	_plate.play_name_sheen()

func get_plate() -> ItemPlate:
	return _plate

# Grows from from_rect (at the scale that fits it) to the centre.
func _open() -> void:
	var view: Vector2 = _scrim.get_viewport_rect().size
	var unit: Vector2 = _plate.get_plate_size() / _plate.plate_scale
	var start_scale: float = examine_scale
	var start_position: Vector2
	if _from_rect.size.x > 0.0:
		start_scale = clampf(_from_rect.size.y / maxf(unit.y, 1.0), 0.1, examine_scale)
		start_position = _from_rect.position
	else:
		start_position = (view - unit * start_scale) / 2.0
	_plate.plate_scale = start_scale
	_plate.position = start_position
	_tween_to(examine_scale, ((view - unit * examine_scale) / 2.0).round(), 1.0)

func _tween_to(to_scale: float, to_position: Vector2, scrim_alpha: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(_plate, "plate_scale", to_scale, inspect_duration_sec)
	_tween.tween_property(_plate, "position", to_position, inspect_duration_sec)
	_tween.tween_property(_scrim, "modulate:a", scrim_alpha, inspect_duration_sec)
	return _tween

func _on_scrim_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and (button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT):
		_scrim.accept_event()
		close(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close(false)
		return
	if not _with_choice or _plate == null:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_plate.set_focus(ItemPlate.Choice.LEAVE if _plate.get_focus() == ItemPlate.Choice.TAKE else ItemPlate.Choice.TAKE)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_plate.activate(_plate.get_focus())

# Back to where it came from (a choice made fades where it stands), then
# gone - and `closed` for the field. The first close wins.
func close(taken: bool) -> void:
	if _closing:
		return
	_closing = true
	if _plate == null or (_piece == null and _weapon == null):
		closed.emit(false)
		queue_free()
		return
	var unit: Vector2 = _plate.get_plate_size() / _plate.plate_scale
	var back_scale: float = _plate.plate_scale
	var back_position: Vector2 = _plate.position
	if _from_rect.size.x > 0.0:
		back_scale = clampf(_from_rect.size.y / maxf(unit.y, 1.0), 0.1, examine_scale)
		back_position = _from_rect.position
	var tween: Tween = _tween_to(back_scale, back_position, 0.0)
	tween.tween_property(_plate, "modulate:a", 0.0, inspect_duration_sec)
	tween.chain().tween_callback(func() -> void:
		closed.emit(taken)
		queue_free())
