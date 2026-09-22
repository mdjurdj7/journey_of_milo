extends Node3D
class_name PackPatrol

# Flies one cluster between its perches - a FloorPatrol's route (see
# floors/floor_patrol.gd), driven for the group's FieldEnemies. Made by
# RegionField._spawn_floor_patrols(), one per route, a child of
# RegionField so the field's freeze (a fight, the reward screen) stops
# it with everything else: this node's _process halts, and every flight
# tween is the default TWEEN_PAUSE_BOUND, unlike the battle's own
# PAUSE_PROCESS tweens.
#
# The loop: PERCHED for a dwell rolled between the route's min and max,
# then a leg - every living member takes off a little apart (its own
# countdown, 0..takeoff_stagger_max, ticked HERE rather than by a scene
# timer, which would keep counting through a freeze) toward the next
# waypoint plus its own offset from the pack's authored centroid, so the
# flock keeps its shape without moving in lockstep - and PERCHED again
# once the last of them has landed. A member that dies drops out of the
# list; the loop goes on with whoever is left.
#
# A fight interrupts it (interrupt(), from RegionField's contact handler
# after it has landed any flyer for the battle line): pending take-offs
# are dropped and the state goes back to PERCHED with a fresh dwell, so
# when the field thaws - on an escape, after the members have walked
# back to their spots - the loop simply resumes from wherever they stand
# toward the next waypoint. The route ignores the Wanderer entirely.

enum State { PERCHED, FLYING }

# Every value is read when a leg or a landing starts, so a Remote-tab
# edit takes on the next one.
@export var hover_height: float = 0.5
@export var speed: float = 1.5
@export var takeoff_stagger_max: float = 0.6
# Rise at take-off and descent at landing, each.
@export var rise_seconds: float = 0.3
@export var land_seconds: float = 0.3

var _members: Array[FieldEnemy] = []
var _offsets: Dictionary = {} # FieldEnemy -> Vector3 (XZ offset from the pack's centroid)
var _waypoints: Array[Vector3] = []
var _dwell_min: float = 2.0
var _dwell_max: float = 5.0
var _state: State = State.PERCHED
var _index: int = 0
var _dwell_left: float = 0.0
var _pending: Dictionary = {} # FieldEnemy -> seconds until take-off

# members: the group's FieldEnemies, where they were authored; waypoints:
# world positions (XZ) the pack's centroid visits, in loop order.
func setup(members: Array[FieldEnemy], waypoints: Array[Vector3], dwell_min: float, dwell_max: float) -> void:
	_members = members.duplicate()
	_waypoints = waypoints.duplicate()
	_dwell_min = dwell_min
	_dwell_max = dwell_max
	var centroid := Vector3.ZERO
	for member in _members:
		centroid += member.global_position
	if not _members.is_empty():
		centroid /= float(_members.size())
	for member in _members:
		var offset: Vector3 = member.global_position - centroid
		_offsets[member] = Vector3(offset.x, 0.0, offset.z)
	_index = 0
	_roll_dwell()

func interrupt() -> void:
	_pending.clear()
	_state = State.PERCHED
	_roll_dwell()

func _roll_dwell() -> void:
	_dwell_left = randf_range(minf(_dwell_min, _dwell_max), maxf(_dwell_min, _dwell_max))

func _process(delta: float) -> void:
	_prune()
	if _members.is_empty() or _waypoints.size() < 2:
		return
	match _state:
		State.PERCHED:
			_dwell_left -= delta
			if _dwell_left <= 0.0:
				_start_leg()
		State.FLYING:
			_tick_takeoffs(delta)
			if _pending.is_empty() and not _any_airborne():
				_state = State.PERCHED
				_roll_dwell()

# The dead and the freed leave the flock.
func _prune() -> void:
	var alive: Array[FieldEnemy] = []
	for member in _members:
		if is_instance_valid(member) and not member.is_queued_for_deletion() and not member.is_defeated():
			alive.append(member)
		else:
			_pending.erase(member)
	_members = alive

func _start_leg() -> void:
	_index = (_index + 1) % _waypoints.size()
	_state = State.FLYING
	for member in _members:
		_pending[member] = randf_range(0.0, maxf(takeoff_stagger_max, 0.0))

func _tick_takeoffs(delta: float) -> void:
	for member in _pending.keys():
		_pending[member] = float(_pending[member]) - delta
		if float(_pending[member]) <= 0.0:
			_pending.erase(member)
			var spot: Vector3 = _waypoints[_index] + (_offsets.get(member, Vector3.ZERO) as Vector3)
			(member as FieldEnemy).fly_to(spot, hover_height, speed, rise_seconds, land_seconds)

func _any_airborne() -> bool:
	for member in _members:
		if member.is_airborne():
			return true
	return false
