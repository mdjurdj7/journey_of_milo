extends Node3D
class_name Roamer

# Drifts one FieldEnemy about a patch of its floor - a FloorRoam (see
# floors/floor_roam.gd), driven for the enemy it names. Made by
# RegionField._spawn_floor_roams(), a child of RegionField so the field's
# freeze (a fight, the reward screen) stops it with everything else; on
# an escape it carries on from wherever the body stands.
#
# Aimless, not a route: the heading drifts on smoothed noise, the pace
# breathes around the FloorRoam's but never stops, and the only thing
# that turns it is the edge of where it may be - inside the FloorRoam's
# area, on sand shore_margin_m clear of the water, and band_keep_off_m
# clear of the worn band's centre line (RegionField.get_wear_path()).
# When the point lookahead_m ahead is outside that, it turns toward home
# (the allowed point nearest the area's centre, found once at setup); a
# step that would itself leave it isn't taken, so it turns on the spot
# instead.
#
# It never reads the Wanderer. It doesn't turn toward him, speed up or
# give way: contact happens only when he walks into it or stands where it
# is going.

# Every value is read each physics frame, so a Remote-tab edit takes at
# once.
# The pace's breathing: +/- this fraction of FloorRoam.speed_mps.
@export_range(0.0, 0.9) var speed_variation: float = 0.35
# The fastest the heading drifts on its own, degrees a second.
@export var wander_turn_degrees: float = 30.0
# How slowly the drift and the breathing change - roughly the seconds
# one swing of either takes.
@export var wander_seconds: float = 6.0
# How far ahead it looks for an edge, and how fast it turns from one.
@export var lookahead_m: float = 1.5
@export var avoid_turn_degrees: float = 70.0
# How fast the body turns to face its heading.
@export var face_turn_rate: float = 2.0
# How far from the water's edge it keeps, metres.
@export var shore_margin_m: float = 1.5

# The band's centre line as a polyline, sampled this finely from the
# three-point curve ground.gdshader draws (wear_curve_point()).
const BAND_SAMPLES := 24

var _member: FieldEnemy = null
var _ground: Ground = null
var _area: Rect2 = Rect2()
var _speed: float = 0.35
var _band_keep_off: float = 3.0
var _band: PackedVector2Array = PackedVector2Array()
var _home: Vector2 = Vector2.ZERO
# Radians, in face_toward_point()'s convention: travel direction
# (-sin, -cos) in XZ.
var _heading: float = 0.0
var _time: float = 0.0
var _noise := FastNoiseLite.new()

# member: the enemy, where it was authored; area: world XZ; wear_path:
# RegionField.get_wear_path() (empty = no band to keep off).
func setup(member: FieldEnemy, ground: Ground, area: Rect2, speed: float, band_keep_off: float, wear_path: PackedVector3Array) -> void:
	_member = member
	_ground = ground
	_area = area.abs()
	_speed = speed
	_band_keep_off = band_keep_off
	_band = _band_polyline(wear_path)
	_heading = member.rotation.y
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	_home = _find_home()

func _physics_process(delta: float) -> void:
	if not _can_move():
		return
	_time += delta
	var here := Vector2(_member.global_position.x, _member.global_position.z)
	var swing: float = _time / maxf(wander_seconds, 0.1)

	_heading += deg_to_rad(wander_turn_degrees) * _noise.get_noise_1d(swing) * delta
	if not _allowed(here + _direction(_heading) * lookahead_m):
		var to_home: Vector2 = _home - here
		if to_home.length() > 0.001:
			var home_heading: float = atan2(-to_home.x, -to_home.y)
			var max_turn: float = deg_to_rad(avoid_turn_degrees) * delta
			_heading += clampf(wrapf(home_heading - _heading, -PI, PI), -max_turn, max_turn)
	_heading = wrapf(_heading, -PI, PI)

	var pace: float = _speed * (1.0 + speed_variation * _noise.get_noise_1d(swing + 1000.0))
	var step: Vector2 = here + _direction(_heading) * maxf(pace, 0.0) * delta
	# Outside already (pushed, or authored out) it walks home regardless.
	if _allowed(step) or not _allowed(here):
		_member.roam_step(step, _heading, face_turn_rate * delta)

# A body still on the field and on its feet - not dying, not flying.
func _can_move() -> bool:
	if _member == null or not is_instance_valid(_member) or _member.is_queued_for_deletion():
		return false
	return not _member.is_defeated() and not _member.is_settling() and not _member.is_airborne()

func _direction(heading: float) -> Vector2:
	return Vector2(-sin(heading), -cos(heading))

func _allowed(point: Vector2) -> bool:
	if not _area.has_point(point):
		return false
	if _ground != null and _ground.get_landmass_distance(point) > -shore_margin_m:
		return false
	return _band_distance(point) >= _band_keep_off

# The allowed point nearest the area's centre, on a half-metre grid - what
# an edge turns it toward. The centre itself if nothing is allowed (loud:
# the FloorRoam leaves it nowhere to stand).
func _find_home() -> Vector2:
	var centre: Vector2 = _area.get_center()
	var best: Vector2 = centre
	var best_distance: float = INF
	var x: float = _area.position.x
	while x <= _area.end.x:
		var y: float = _area.position.y
		while y <= _area.end.y:
			var point := Vector2(x, y)
			var distance: float = point.distance_squared_to(centre)
			if distance < best_distance and _allowed(point):
				best_distance = distance
				best = point
			y += 0.5
		x += 0.5
	if best_distance == INF:
		push_warning("Roamer: no allowed ground in %s for '%s'; it will stand still." % [_area, _member.name])
	return best

# ground.gdshader's wear_curve_point(): a quadratic Bezier that passes
# THROUGH the middle point at t = 0.5 (handle = 2 mid - (start + end) / 2).
func _band_polyline(wear_path: PackedVector3Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	if wear_path.size() < 3:
		return points
	var start := Vector2(wear_path[0].x, wear_path[0].z)
	var mid := Vector2(wear_path[1].x, wear_path[1].z)
	var end := Vector2(wear_path[2].x, wear_path[2].z)
	var handle: Vector2 = 2.0 * mid - 0.5 * (start + end)
	for i in BAND_SAMPLES + 1:
		var t: float = float(i) / float(BAND_SAMPLES)
		var u: float = 1.0 - t
		points.append(u * u * start + 2.0 * u * t * handle + t * t * end)
	return points

func _band_distance(point: Vector2) -> float:
	var best: float = INF
	for i in _band.size() - 1:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, _band[i], _band[i + 1])
		best = minf(best, point.distance_to(closest))
	return best
