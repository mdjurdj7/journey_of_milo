extends CanvasLayer
class_name KeepsakeExamine

# A keepsake looked at closely: its KeepsakeTile at examine_scale, centred
# over the dimmed field - DeckView's inspect, for a keepsake. It grows out
# of where it was clicked (from_rect, the HUD row's keepsake) to the
# middle of the screen while an ink scrim fades in, over inspect_duration_
# sec; a click anywhere, Escape or a right click puts it back the same way
# and closes. Opened by RegionField.open_keepsake_examine(), which locks
# the field under it (as every screen over the field does) until `closed`.
# Layer 100, running ALWAYS.

signal closed()

@export var examine_scale: float = 2.0
# DeckView's inspect: its time and its scrim (the card's ink at 35%).
@export var inspect_duration_sec: float = 0.15
@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.35)

var _keepsake: TrinketData = null
var _from_rect: Rect2 = Rect2()
var _scrim: ColorRect = null
var _tile: KeepsakeTile = null
var _tween: Tween = null
var _closing: bool = false

# Called before the layer enters the tree. `from_rect`: where it grows
# from, in screen pixels (empty: from the middle).
func setup(keepsake: TrinketData, from_rect: Rect2) -> void:
	_keepsake = keepsake
	_from_rect = from_rect

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
	_tile = KeepsakeTile.new()
	_tile.name = "Tile"
	add_child(_tile)
	_tile.set_keepsake(_keepsake)
	if _keepsake == null:
		close()
		return
	_open()

func get_tile() -> KeepsakeTile:
	return _tile

# Grows from from_rect (at the scale that fits it) to the centre at
# examine_scale.
func _open() -> void:
	var view: Vector2 = _scrim.get_viewport_rect().size
	var start_scale: float = examine_scale
	var start_position: Vector2
	if _from_rect.size.x > 0.0:
		start_scale = clampf(_from_rect.size.y / _tile.tile_size.y, 0.1, examine_scale)
		start_position = _from_rect.position
	else:
		start_position = (view - _tile.tile_size * start_scale) / 2.0
	_tile.tile_scale = start_scale
	_tile.position = start_position
	_tween_to(examine_scale, ((view - _tile.tile_size * examine_scale) / 2.0).round(), 1.0)

func _tween_to(to_scale: float, to_position: Vector2, scrim_alpha: float) -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(_tile, "tile_scale", to_scale, inspect_duration_sec)
	_tween.tween_property(_tile, "position", to_position, inspect_duration_sec)
	_tween.tween_property(_scrim, "modulate:a", scrim_alpha, inspect_duration_sec)
	return _tween

func _on_scrim_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and (button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT):
		_scrim.accept_event()
		close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

# Back to where it came from, then gone - and `closed` for the field.
func close() -> void:
	if _closing:
		return
	_closing = true
	if _tile == null or _keepsake == null:
		closed.emit()
		queue_free()
		return
	var back_scale: float = examine_scale
	var back_position: Vector2 = _tile.position
	if _from_rect.size.x > 0.0:
		back_scale = clampf(_from_rect.size.y / _tile.tile_size.y, 0.1, examine_scale)
		back_position = _from_rect.position
	var tween: Tween = _tween_to(back_scale, back_position, 0.0)
	tween.chain().tween_callback(func() -> void:
		closed.emit()
		queue_free())
