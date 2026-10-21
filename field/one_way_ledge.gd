extends LedgeBarrier
class_name OneWayLedge

# A ledge wall walked down through but never up (FloorData.one_way_ledges,
# OneWayLedgeData) - floor 3's rim trail ending in its bank. Built like
# any LedgeBarrier, one box per segment of its line; what makes it one-way
# is that its boxes stand only while the Wanderer (watch()) is on the down
# side:
#   - up the trail side (the side away from down_point, any distance): open
#     - he walks down through it;
#   - down past the line by clear_m or more: shut behind him - he can't
#     walk back up. Between the two the last state holds, so it never
#     shuts on a capsule still crossing it and pushes him back.
# The walk grid follows the same state: RegionField leaves this out of the
# grid's static shapes and hands its boxes to every path query as dynamic
# ones (_nav_dynamic_shapes()), which stamp nothing while they are
# disabled (NavGrid.footprint_cells()) - so a plan comes down the bank,
# never goes up it.

# World XZ: any point on the down side (OneWayLedgeData.down_point, from
# the spawn, mapped by RegionField).
@export var down_point: Vector2 = Vector2.ZERO
# How far past the line onto the down side he must be, metres, before it
# shuts behind him - his capsule's radius and the wall's thickness, with
# room to spare.
@export var clear_m: float = 0.8

var _watched: Node3D = null
var _blocking: bool = true

# The body whose side of the line opens and shuts it (the Wanderer).
func watch(body: Node3D) -> void:
	_watched = body

# Whether its boxes stand now - he is on the down side.
func is_blocking() -> bool:
	return _blocking

# Metres from the line to `p`, world XZ: + toward the down side, - up the
# other. Against the nearest segment, its normal turned toward down_point.
func side_of(p: Vector2) -> float:
	var best: float = INF
	var signed: float = 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var along: Vector2 = b - a
		if along.length() < 0.001:
			continue
		var t: float = clampf((p - a).dot(along) / along.length_squared(), 0.0, 1.0)
		var distance: float = p.distance_to(a + along * t)
		if distance < best:
			best = distance
			var normal := Vector2(-along.y, along.x).normalized()
			if (down_point - (a + b) * 0.5).dot(normal) < 0.0:
				normal = -normal
			signed = (p - a).dot(normal)
	return signed

func _physics_process(_delta: float) -> void:
	if _watched == null or not is_instance_valid(_watched):
		return
	var side: float = side_of(Vector2(_watched.global_position.x, _watched.global_position.z))
	var blocking: bool = _blocking
	if side < 0.0:
		blocking = false
	elif side >= clear_m:
		blocking = true
	if blocking != _blocking:
		_blocking = blocking
		_apply()

func _rebuild() -> void:
	super._rebuild()
	_apply()

# Every box of the wall standing or not, by _blocking - deferred, as a
# shape changed inside the physics step must be.
func _apply() -> void:
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null and not shape.is_queued_for_deletion():
			shape.set_deferred(&"disabled", not _blocking)
