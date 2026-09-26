extends StaticBody3D
class_name LedgeBarrier

# An invisible wall along the lip of a raised face, so a face painted
# wide enough to render smoothly can still be a drop he can't walk up.
# At the relief's 0.35 m spacing, anything steep enough to stop him on
# its own (over floor_max_angle, 45 degrees) is at most ~2.4 cells wide
# and renders as a sawtooth; a ~1.2 m face renders cleanly but is only
# 25-35 degrees - walkable. This body is the difference: the look comes
# from the elevation painting, the "can't climb it" from here.
#
# One box per segment of `points` (world XZ, in order along the lip),
# each standing from sink_m under the lowest ground along the segment to
# height_m over the highest, lengthened by its own thickness so the
# joins between segments close. Rebuilt whenever the relief is (Ground.
# relief_rebuilt) and on any export change. Built by RegionField from
# FloorData.ledges (_spawn_floor_ledges()); nothing draws it.
#
# RegionField's click-to-move ray excludes it (it is in LEDGE_GROUP), so
# a click on the face beyond the lip lands on the sand, not on the air.

const LEDGE_GROUP := &"ledge_barriers"

@export var points: PackedVector2Array = PackedVector2Array():
	set(value):
		points = value
		_rebuild()
# Over the highest ground along each segment. Enough to stop his capsule,
# not a wall anyone could see from its effect on anything else.
@export var height_m: float = 0.8:
	set(value):
		height_m = value
		_rebuild()
@export var sink_m: float = 0.3:
	set(value):
		sink_m = value
		_rebuild()
@export var thickness_m: float = 0.2:
	set(value):
		thickness_m = value
		_rebuild()
# Ground samples per segment when finding its lowest and highest ground.
@export var samples_per_segment: int = 5:
	set(value):
		samples_per_segment = value
		_rebuild()

var _ground: Ground = null

func _ready() -> void:
	add_to_group(LEDGE_GROUP)
	_rebuild()

# The ground to stand on, and the line. Safe before or after entering the
# tree - the build waits for both.
func setup(ground: Ground, line: PackedVector2Array) -> void:
	_ground = ground
	if _ground != null and not _ground.relief_rebuilt.is_connected(_rebuild):
		_ground.relief_rebuilt.connect(_rebuild)
	points = line

func _rebuild() -> void:
	if not is_inside_tree() or _ground == null:
		return
	for child in get_children():
		child.queue_free()
	var steps: int = maxi(samples_per_segment, 2)
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length: float = a.distance_to(b)
		if length < 0.001:
			continue
		var low: float = INF
		var high: float = -INF
		for s in steps:
			var h: float = _ground.get_height_at(a.lerp(b, float(s) / float(steps - 1)))
			low = minf(low, h)
			high = maxf(high, h)
		var bottom: float = low - sink_m
		var top: float = high + height_m
		var shape := BoxShape3D.new()
		shape.size = Vector3(length + thickness_m, top - bottom, thickness_m)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var mid: Vector2 = (a + b) * 0.5
		var along: Vector2 = (b - a) / length
		# Box local +X along the segment.
		var basis := Basis(Vector3(along.x, 0.0, along.y), Vector3.UP, Vector3(-along.y, 0.0, along.x))
		add_child(collision)
		collision.global_transform = Transform3D(basis, Vector3(mid.x, (bottom + top) * 0.5, mid.y))
