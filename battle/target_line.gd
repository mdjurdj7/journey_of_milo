extends Control
class_name TargetLine

# Faint curved line from the armed card's top-center to the mouse (or, if
# an enemy is hovered, that enemy's chest) - reads as a thrown line
# rather than a ruler thanks to the upward sag (see _bezier_points()). One
# Control (mouse_filter IGNORE, covers the whole overlay so its own local
# coordinates line up with screen coordinates) holding two Line2D
# children: the curve itself and a small hollow circle shown only while
# an enemy is hovered.
#
# Built purely in code - instantiated via TargetLine.new() and added as a
# child of BattleOverlay via setup() in enter_battle(), not part of any
# .tscn.

const SEGMENT_COUNT := 20
const CIRCLE_POINT_COUNT := 24
const CIRCLE_RADIUS := 10.0
const FADE_DURATION := 0.1

@export var line_width: float = 2.0
@export var line_alpha: float = 0.25
@export var curve_amount: float = 60.0

# Just above the Sputter's own shell, chest height. An untested guess
# like every other body-relative offset in this project (no way to check
# without running the game); retune live if it reads high or low.
@export var chest_offset: Vector3 = Vector3(0.0, 0.5, 0.0)

var _battle_controller: BattleController
var _line: Line2D
var _end_circle: Line2D
var _armed: bool = false

func setup(battle_controller: BattleController) -> void:
	_battle_controller = battle_controller
	_battle_controller.target_requested.connect(_on_target_requested)
	_battle_controller.target_cancelled.connect(_on_target_ended)
	_battle_controller.card_played.connect(_on_card_played)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0

	_line = Line2D.new()
	_line.antialiased = true
	add_child(_line)

	# The "small hollow circle" at the end - only populated with points
	# (see _circle_points()) while an enemy is actually hovered.
	_end_circle = Line2D.new()
	_end_circle.antialiased = true
	_end_circle.closed = true
	_end_circle.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_end_circle)

func _on_target_requested(_card: CardData) -> void:
	_armed = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)

# Shared by target_cancelled and card_played - either way the armed state
# is over. _armed flips false immediately so _process() below stops
# recomputing the curve, freezing it at its last shape/position while
# modulate fades it out - a fade with nothing left to fade would just be
# an instant pop, not a fade.
func _on_target_ended() -> void:
	_armed = false
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)

func _on_card_played(_card: CardData, _target: FieldEnemy) -> void:
	_on_target_ended()

func _process(_delta: float) -> void:
	if not _armed or _battle_controller == null:
		return

	var card_view: CardView = _battle_controller.get_pending_card_view()
	if card_view == null:
		return

	# The card's rendered top-centre through its own transform - CardView
	# scales about a bottom-centre pivot (hover/armed), so the rendered
	# rect is not global_position + size * scale.
	var start: Vector2 = card_view.get_global_transform() * Vector2(card_view.size.x / 2.0, 0.0)

	var hovered_enemy: FieldEnemy = _battle_controller.get_hovered_enemy()
	var show_circle := false
	var end: Vector2 = get_viewport().get_mouse_position()
	if hovered_enemy != null and is_instance_valid(hovered_enemy):
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			end = camera.unproject_position(hovered_enemy.global_position + chest_offset)
			show_circle = true

	var color: Color = get_theme_color("text_color", "CardFace")
	color.a = line_alpha

	_line.default_color = color
	_line.width = line_width
	_line.points = _bezier_points(start, end)

	if show_circle:
		_end_circle.default_color = color
		_end_circle.width = line_width
		_end_circle.points = _circle_points(end)
	else:
		_end_circle.clear_points()

# Sags the midpoint upward (screen-up, i.e. toward smaller Y) off the
# straight line between start and end by curve_amount, regardless of the
# line's own direction - a taut ruler-straight line has no personality;
# this reads as something thrown rather than drawn.
func _bezier_points(start: Vector2, end: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(SEGMENT_COUNT + 1)

	var delta: Vector2 = end - start
	if delta.length() < 0.0001:
		points[0] = start
		points[SEGMENT_COUNT] = end
		return points

	var direction: Vector2 = delta.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	if perpendicular.y > 0.0:
		perpendicular = -perpendicular
	var control: Vector2 = (start + end) / 2.0 + perpendicular * curve_amount

	for i in SEGMENT_COUNT + 1:
		var t: float = float(i) / float(SEGMENT_COUNT)
		var one_minus_t: float = 1.0 - t
		points[i] = start * (one_minus_t * one_minus_t) + control * (2.0 * one_minus_t * t) + end * (t * t)
	return points

func _circle_points(center: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(CIRCLE_POINT_COUNT)
	for i in CIRCLE_POINT_COUNT:
		var angle: float = TAU * float(i) / float(CIRCLE_POINT_COUNT)
		points[i] = center + Vector2(cos(angle), sin(angle)) * CIRCLE_RADIUS
	return points
