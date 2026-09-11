extends Polygon2D
class_name ClickMoveMarker
# The ground indicator for click-to-move (see player.gd's destination_
# set/destination_cleared signals, which field_room.gd relays into show_
# at()/hide_marker() below). A flat placeholder ellipse, same "simple
# primitive, no shader" language every other field silhouette in this
# game already uses - real art can replace this shape later without
# either signal-consuming side needing to change.
#
# One instance, reused for every click, not respawned per click - see
# field_room.gd's _ready(), which builds this exactly once the same
# "set_script() on a plain node" way field_particulate.gd's motes are
# built (field_room.gd's own FIELD_PARTICULATE_SCRIPT note explains why
# that's preferred over a whole .tscn for a single-shape node with no
# children).

@export var radius_x: float = 26.0
@export var radius_y: float = 9.0
@export var point_count: int = 20
@export var marker_color: Color = Color(1, 1, 1, 0.6)
@export var fade_duration_sec: float = 0.2

var _fade_tween: Tween

func _ready() -> void:
	color = marker_color
	polygon = _build_ellipse()
	visible = false
	modulate.a = 0.0

func _build_ellipse() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in point_count:
		var angle := TAU * i / point_count
		points.append(Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points

# Shows (or re-shows, if it was mid-fade) the marker at world x - used for
# both a fresh destination and a retarget alike (see player.gd's
# destination_set doc for why those two cases don't need to be told
# apart here either).
func show_at(x: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	position.x = x
	visible = true
	modulate.a = 1.0

# Fades out on arrival OR cancellation (see player.gd's destination_
# cleared doc) - this function doesn't need to know which happened, only
# that the marker should disappear now.
func hide_marker() -> void:
	if not visible:
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration_sec)
	_fade_tween.tween_callback(func(): visible = false)
