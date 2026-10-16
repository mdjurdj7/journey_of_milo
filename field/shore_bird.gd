extends Node3D
class_name ShoreBird

# One bird of a ShoreFlock: on the sand it idles on its own clock - a
# pause, then a peck (the body tipped forward round its hip and back), a
# hop (a short arc forward over the sand) or a turn - and once told to go
# (take_off()) it swaps to the flying model, flaps by squashing it
# vertically, climbs, and flies off between away-from-him and downwind,
# curving on toward downwind. Gone once out of the camera's view (or
# after the data's flight cap). Its forward is this node's -Z; the
# models, beak on +Z, are yawed by the data's model_yaw_offset_degrees
# under it.
#
# Moved only through advance(), which the flock calls every frame: idling
# when the flock says the field is live, flying whatever it says.

enum State { PAUSE, PECK, HOP, TURN, WAITING_TO_FLY, FLYING }

var _data: ShoreFlockData = null
var _ground: Ground = null
var _rng := RandomNumberGenerator.new()
var _home: Vector2 = Vector2.ZERO
# The standing model hangs off a pivot at its hip (the peck tips it); the
# flying one off a holder at its body's centre (the flap squashes it).
var _pivot: Node3D = null
var _standing: Node3D = null
var _holder: Node3D = null
var _flying: Node3D = null
var _hip: float = 0.0

var _state: State = State.PAUSE
var _clock: float = 0.0
var _span: float = 0.0
var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _yaw_from: float = 0.0
var _yaw_to: float = 0.0
var _heading: Vector2 = Vector2.ZERO
var _target_heading: Vector2 = Vector2.ZERO
var _lift_from: float = 0.0
var _aloft: float = 0.0

# Builds both models (wearing these materials) and stands it at `at` on
# the sand, facing `yaw`, `home` the flock's spot.
func setup(data: ShoreFlockData, ground: Ground, standing_material: Material, flying_material: Material, at: Vector2, yaw: float, home: Vector2, seed_value: int) -> void:
	_data = data
	_ground = ground
	_home = home
	_rng.seed = seed_value
	rotation.y = yaw
	_place_on_sand(at, 0.0)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_standing = _model(data.standing_model_path)
	if _standing != null:
		_pivot.add_child(_standing)
		var box: AABB = PaintedProp.dress_model(_standing, standing_material, self) if standing_material != null else AABB()
		_hip = box.size.y * 0.45
		_pivot.position.y = _hip
		_standing.position.y -= box.position.y + _hip
	_holder = Node3D.new()
	_holder.name = "Flying"
	_holder.visible = false
	add_child(_holder)
	_flying = _model(data.flying_model_path)
	if _flying != null:
		_holder.add_child(_flying)
		var box: AABB = PaintedProp.dress_model(_flying, flying_material, self) if flying_material != null else AABB()
		_flying.position -= box.get_center() - _holder.position
		_holder.position.y = box.size.y * 0.5
	_begin_pause()

func _model(path: String) -> Node3D:
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		push_warning("ShoreBird: no model at '%s'." % path)
		return null
	var model := scene.instantiate() as Node3D
	model.scale = Vector3.ONE * maxf(_data.model_scale, 0.01)
	model.rotation.y = deg_to_rad(_data.model_yaw_offset_degrees)
	return model

func is_flying() -> bool:
	return _state == State.WAITING_TO_FLY or _state == State.FLYING

# Leaves after `delay` seconds on a heading between `away` (flat, from
# him) and `downwind`, curving on toward downwind.
func take_off(delay: float, away: Vector2, downwind: Vector2) -> void:
	if is_flying():
		return
	_state = State.WAITING_TO_FLY
	_clock = 0.0
	_span = maxf(delay, 0.0)
	var jitter: float = deg_to_rad(_rng.randf_range(-_data.heading_jitter_degrees, _data.heading_jitter_degrees))
	_target_heading = downwind.rotated(jitter)
	# Away from him and downwind together - straight across the wind when
	# he stands downwind of it, on the side away from him.
	var off: Vector2 = away.normalized() * maxf(_data.away_weight, 0.0) if away.length() > 1.0e-4 else Vector2.ZERO
	_heading = off + _target_heading
	if _heading.length() < 0.2:
		_heading = _target_heading.orthogonal()
		if off.dot(_heading) < 0.0:
			_heading = -_heading
	_heading = _heading.normalized()

# One frame: the flight always; the idle only when `idle` (the field live).
func advance(delta: float, idle: bool) -> void:
	if _state == State.WAITING_TO_FLY:
		_clock += delta
		if _clock >= _span:
			_lift_off()
		return
	if _state == State.FLYING:
		_fly(delta)
		return
	if not idle:
		return
	_clock += delta
	var t: float = clampf(_clock / maxf(_span, 1.0e-3), 0.0, 1.0)
	match _state:
		State.PECK:
			_pivot.rotation.x = -deg_to_rad(_data.peck_degrees) * sin(t * PI)
		State.HOP:
			_place_on_sand(_from.lerp(_to, t), _data.hop_height_m * sin(t * PI))
		State.TURN:
			rotation.y = lerp_angle(_yaw_from, _yaw_to, smoothstep(0.0, 1.0, t))
	if t >= 1.0:
		if _state == State.PAUSE:
			_begin_move()
		else:
			_begin_pause()

func _begin_pause() -> void:
	_state = State.PAUSE
	_clock = 0.0
	_span = _rng.randf_range(_data.pause_seconds.x, maxf(_data.pause_seconds.x, _data.pause_seconds.y))
	if _pivot != null:
		_pivot.rotation.x = 0.0

func _begin_move() -> void:
	_clock = 0.0
	var weights: Vector3 = _data.idle_weights.max(Vector3.ZERO)
	var roll: float = _rng.randf() * maxf(weights.x + weights.y + weights.z, 1.0e-4)
	var here := Vector2(position.x, position.z)
	var forward3: Vector3 = -global_transform.basis.z
	var forward := Vector2(forward3.x, forward3.z).normalized()
	var strayed: bool = here.distance_to(_home) > _data.leash_m
	if roll < weights.x and not strayed:
		_state = State.PECK
		_span = _data.peck_seconds
	elif roll < weights.x + weights.y and not strayed:
		_state = State.HOP
		_span = _data.hop_seconds
		_from = here
		_to = here + forward * _rng.randf_range(_data.hop_distance_m.x, maxf(_data.hop_distance_m.x, _data.hop_distance_m.y))
	else:
		_state = State.TURN
		_span = _data.turn_seconds
		_yaw_from = rotation.y
		if strayed:
			# Back toward the flock's spot before anything else.
			var back: Vector2 = (_home - here).normalized()
			_yaw_to = atan2(-back.x, -back.y)
		else:
			var swing: float = deg_to_rad(_rng.randf_range(_data.turn_degrees.x, maxf(_data.turn_degrees.x, _data.turn_degrees.y)))
			_yaw_to = _yaw_from + (swing if _rng.randf() < 0.5 else -swing)

func _lift_off() -> void:
	_state = State.FLYING
	_aloft = 0.0
	_lift_from = position.y
	if _pivot != null:
		_pivot.visible = false
	_holder.visible = true
	rotation.y = atan2(-_heading.x, -_heading.y)

func _fly(delta: float) -> void:
	_aloft += delta
	var turn: float = deg_to_rad(_data.curve_degrees_per_second) * delta
	var angle: float = _heading.angle_to(_target_heading)
	_heading = _heading.rotated(clampf(angle, -turn, turn))
	var step: Vector2 = _heading * _data.flight_speed_m * delta
	position.x += step.x
	position.z += step.y
	var rise: float = position.y - _lift_from
	position.y += _data.climb_speed_m * delta * clampf(1.0 - rise / maxf(_data.climb_height_m, 0.01), 0.1, 1.0)
	rotation.y = atan2(-_heading.x, -_heading.y)
	var beat: float = 0.5 + 0.5 * sin(_aloft * TAU * _data.flap_hz)
	_holder.scale.y = lerpf(1.0, _data.flap_squash, beat)
	if _aloft >= _data.flight_cap_seconds or (_aloft > 0.4 and not _in_view()):
		queue_free()

func _in_view() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	return camera == null or camera.is_position_in_frustum(global_position)

func _place_on_sand(at: Vector2, lift: float) -> void:
	var height: float = _ground.get_visible_height_at(at) if _ground != null else 0.0
	position = Vector3(at.x, height + lift, at.y)
