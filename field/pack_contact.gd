extends Node
class_name PackContact

# One cluster's contact zone - made by RegionField._spawn_pack_contacts(),
# one per group, a child of RegionField so the field's freeze (a fight,
# the reward screen) stops it with everything else. The zone is the
# convex hull of the living members' XZ positions (one member: its spot;
# two: the segment between them), grown by the margin
# (EncounterOption.contact_margin_m, else the largest member's
# contact_radius at spawn) - rebuilt every physics frame, so it follows
# a flying or stepping member. Contact fires when the Wanderer's body
# reaches it: his centre within margin + his own body radius, the reach
# a lone enemy's sphere has. The members' own contact areas stay off
# (FieldEnemy.pack_contact). Once fired it waits for him to leave the
# zone before it can fire again, as an area's body_exited does.

signal contacted(enemy: FieldEnemy)

var _members: Array[FieldEnemy] = []
var _option: EncounterOption = null
var _spawn_margin: float = 2.0
var _armed: bool = true

# members: the group's FieldEnemies as spawned; option: the encounter
# they stand, read live for its contact_margin_m.
func setup(members: Array[FieldEnemy], option: EncounterOption) -> void:
	_members = members.duplicate()
	_option = option
	_spawn_margin = 0.0
	for member in _members:
		_spawn_margin = maxf(_spawn_margin, member.contact_radius)
		member.pack_contact = true

func get_members() -> Array[FieldEnemy]:
	return _members

func get_margin() -> float:
	if _option != null and _option.contact_margin_m >= 0.0:
		return _option.contact_margin_m
	return _spawn_margin

# The living members' XZ spots - and, with homes, where each will walk
# back to as well (FieldEnemy.get_field_position()), for an escape.
func get_points(with_homes: bool = false) -> PackedVector2Array:
	var points := PackedVector2Array()
	for member in _members:
		if not is_instance_valid(member) or member.is_queued_for_deletion() or member.is_defeated():
			continue
		points.append(Vector2(member.global_position.x, member.global_position.z))
		if with_homes:
			var home: Vector3 = member.get_field_position()
			points.append(Vector2(home.x, home.z))
	return points

func _physics_process(_delta: float) -> void:
	var field := get_parent() as RegionField
	if field == null or field.wanderer == null:
		return
	var points: PackedVector2Array = get_points()
	if points.is_empty():
		return
	var at := Vector2(field.wanderer.global_position.x, field.wanderer.global_position.z)
	var inside: bool = distance_to_zone(at, points) <= get_margin() + field.wanderer.get_body_radius()
	if not inside:
		_armed = true
		return
	if not _armed:
		return
	_armed = false
	# Deferred, as an area's contact is: the handler freezes the field.
	contacted.emit.call_deferred(_nearest_member(at))

func _nearest_member(at: Vector2) -> FieldEnemy:
	var nearest: FieldEnemy = null
	var best: float = INF
	for member in _members:
		if not is_instance_valid(member) or member.is_queued_for_deletion() or member.is_defeated():
			continue
		var distance: float = at.distance_squared_to(Vector2(member.global_position.x, member.global_position.z))
		if distance < best:
			best = distance
			nearest = member
	return nearest

# --- The zone's shape, for any set of XZ points ---

# The closest point of the points' convex hull to `point` - `point`
# itself when it lies inside.
static func closest_point(point: Vector2, points: PackedVector2Array) -> Vector2:
	if points.size() == 1:
		return points[0]
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size() >= 4 and Geometry2D.is_point_in_polygon(point, hull):
		return point
	var best: Vector2 = points[0]
	var best_distance: float = INF
	for i in hull.size() - 1:
		var on_edge: Vector2 = Geometry2D.get_closest_point_to_segment(point, hull[i], hull[i + 1])
		var distance: float = point.distance_squared_to(on_edge)
		if distance < best_distance:
			best_distance = distance
			best = on_edge
	return best

static func distance_to_zone(point: Vector2, points: PackedVector2Array) -> float:
	if points.is_empty():
		return INF
	return point.distance_to(closest_point(point, points))

# The hull grown by `radius` as circles ([centre, radius], the zones
# NavGrid.find_path() and nearest_valid_fight_ground() take): along every
# edge no more than `radius` apart, and over the inside on a grid as
# fine, so nothing finds a way into the middle.
static func zone_circles(points: PackedVector2Array, radius: float) -> Array:
	var circles: Array = []
	if points.is_empty() or radius <= 0.0:
		return circles
	var hull: PackedVector2Array = Geometry2D.convex_hull(points) if points.size() > 1 else points
	if hull.is_empty():
		hull = points
	if hull.size() == 1:
		circles.append([hull[0], radius])
		return circles
	for i in hull.size() - 1:
		var length: float = hull[i].distance_to(hull[i + 1])
		var steps: int = maxi(ceili(length / radius), 1)
		for step in steps:
			circles.append([hull[i].lerp(hull[i + 1], float(step) / float(steps)), radius])
	if hull.size() >= 4:
		var box := Rect2(hull[0], Vector2.ZERO)
		for corner in hull:
			box = box.expand(corner)
		var x: float = box.position.x + radius
		while x < box.end.x:
			var y: float = box.position.y + radius
			while y < box.end.y:
				var spot := Vector2(x, y)
				if Geometry2D.is_point_in_polygon(spot, hull):
					circles.append([spot, radius])
				y += radius
			x += radius
	return circles
