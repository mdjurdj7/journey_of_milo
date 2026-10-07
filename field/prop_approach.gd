extends Node3D
class_name PropApproach

# The walk-up and the click a field prop answers the Wanderer with -
# shared by TroughProp, Collector and Wagon. A child its host builds in
# its own _ready() (add_child() of PropApproach.new()); the host keeps
# its exports and its own reach rule, and hands this the rest as
# callables:
#
# - An Area3D sphere of set_radius() round the host. The first physics
#   tick the Wanderer is inside it, and the host's can_speak (if set)
#   allows, on_visit runs - once per visit into the radius, reset on
#   leaving it. The host says its line there, through say()/say_near().
#   The check runs every tick rather than in body_entered, so a host that
#   wakes with the Wanderer already inside (the trough, its guard fallen
#   beside it) still speaks without him stepping out and back.
# - A left click on the host's padded screen rect (screen_rect, grown by
#   RegionField.click_target_padding_px) with the Wanderer in reach (the
#   host's can_open_from) is handled and emits open_requested; anything
#   else falls through to the field's move click.
#
# Field locking is the host's own business (the collector's screen locks
# it through RegionField; the trough's choice leaves it live). This runs
# under the host, so the field's freeze stops it with everything else:
# nothing is said or clicked over a fight or a screen.

signal open_requested()

# () -> bool: whether a due line may be said now. Unset = always.
var can_speak: Callable = Callable()
# () -> void: the visit's line - the host says it.
var on_visit: Callable = Callable()
# (Vector3) -> bool: whether the Wanderer standing there may open it.
var can_open_from: Callable = Callable()
# (Camera3D, float) -> Rect2: the host's body on screen, grown by the
# padding; an empty rect for none.
var screen_rect: Callable = Callable()
# Names the host in warnings: "TroughProp", "Collector".
var warning_label: String = "PropApproach"

var _area: Area3D = null
var _shape: SphereShape3D = null
var _wanderer_inside: bool = false
# This visit's line has been said (reset on leaving the radius).
var _line_said: bool = false

func _init() -> void:
	_area = Area3D.new()
	_area.name = "ApproachArea"
	_area.monitorable = false
	_shape = SphereShape3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = _shape
	_area.add_child(shape_node)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

func set_radius(radius: float) -> void:
	_shape.radius = maxf(radius, 0.0)

# The host said something of its own (the trough's drunk line): this
# visit's line counts as said.
func mark_said() -> void:
	_line_said = true

# The RegionField above the host, through the host's region_field_path -
# read at each use, as the hosts always did.
func get_region_field() -> RegionField:
	return _region_node() as RegionField

func _region_node() -> Node:
	var host := get_parent()
	if host == null:
		return null
	var path: NodePath = host.get(&"region_field_path")
	return host.get_node_or_null(path)

# The host's line on FieldHUD's world-voice line, centred.
func say(text: String, hold_seconds: float, fade_seconds: float) -> void:
	var line: WorldVoiceLine = _voice_line(text, fade_seconds)
	if line != null:
		line.show_line(text, hold_seconds)

# The same, held near `anchor` at `offset` above it.
func say_near(text: String, hold_seconds: float, fade_seconds: float, anchor: Node3D, offset: Vector3) -> void:
	var line: WorldVoiceLine = _voice_line(text, fade_seconds)
	if line != null:
		line.show_line_near(text, hold_seconds, anchor, offset)

func _voice_line(text: String, fade_seconds: float) -> WorldVoiceLine:
	if text.is_empty():
		return null
	var region_field: Node = _region_node()
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	var line := WorldVoiceLine.on_hud(hud)
	if line == null:
		push_warning("%s '%s': no FieldHUD to show its world line on." % [warning_label, get_parent().name])
		return null
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	return line

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_wanderer_inside = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_wanderer_inside = false
		_line_said = false

func _physics_process(_delta: float) -> void:
	if not _wanderer_inside or _line_said:
		return
	if can_speak.is_valid():
		var allowed: bool = can_speak.call()
		if not allowed:
			return
	_line_said = true
	if on_visit.is_valid():
		on_visit.call()

func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if not can_open_from.is_valid() or not screen_rect.is_valid():
		return
	var region_field: RegionField = get_region_field()
	if region_field == null or region_field.wanderer == null:
		return
	var in_reach: bool = can_open_from.call(region_field.wanderer.global_position)
	if not in_reach:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var rect: Rect2 = screen_rect.call(camera, region_field.click_target_padding_px)
	if rect.size == Vector2.ZERO or not rect.has_point(button.position):
		return
	get_viewport().set_input_as_handled()
	open_requested.emit()
