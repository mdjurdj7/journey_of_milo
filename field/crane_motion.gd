extends Node3D
class_name CraneMotion

# The crowned cranes' moves (EnemyIntent.motion - bow, step, leap),
# played on the model this hangs under (FieldEnemy._attach_scene()) when
# the enemy turn hands them over (FieldEnemy.play_intent_motion()). No
# rig: each is a tween of the model's own pitch, roll and offset in the
# body's frame, about its feet - the glb's origin - and back to rest.
#   bow   pitched forward bow_degrees and back up: the Bow's Block
#   step  a short advance toward the target with a bob, and back: the
#         Step's contact at the end of the advance
#   leap  a hop of leap_height, landing a little toward the target, and
#         back: the Leap's contact on landing
# The two of a pair mirror each other: each splays its step and rolls its
# bow away from its living partner (the packmate sharing its FieldEnemy.
# group); a lone one - Bereft - goes straight. A move asked for while the
# last is still playing (Bereft's second) starts again from rest.

@export_group("Bow")
@export var bow_degrees: float = 25.0
@export var bow_roll_degrees: float = 5.0
@export var bow_down_seconds: float = 0.28
@export var bow_hold_seconds: float = 0.12
@export var bow_up_seconds: float = 0.32
@export_group("")

@export_group("Step")
@export var step_distance: float = 0.35
@export var step_bob_m: float = 0.06
@export var step_splay_degrees: float = 15.0
@export var step_out_seconds: float = 0.2
@export var step_back_seconds: float = 0.28
@export_group("")

@export_group("Leap")
@export var leap_height: float = 0.4
@export var leap_forward_m: float = 0.25
@export var leap_drift_m: float = 0.1
@export var leap_up_seconds: float = 0.2
@export var leap_down_seconds: float = 0.18
@export var leap_back_seconds: float = 0.3
@export_group("")

var _tween: Tween = null
# The model at rest, taken as a move starts from rest - the pose every
# move returns to and a cut-short one is put back at.
var _rest_position: Vector3 = Vector3.ZERO
var _rest_pitch: float = 0.0
var _rest_roll: float = 0.0
var _resting: bool = true

# The move `motion` toward `target`; how long until it lands - the
# contact of a step or a leap, the whole of a bow. -1 for a move this body
# hasn't got.
func play_motion(motion: StringName, target: Node3D) -> float:
	var model := get_parent() as Node3D
	if model == null:
		return -1.0
	_back_to_rest(model)
	match motion:
		&"bow":
			return _bow(model)
		&"step":
			return _step(model, target)
		&"leap":
			return _leap(model, target)
	return -1.0

func _bow(model: Node3D) -> float:
	var side: float = _side(null)
	var pitch: float = _rest_pitch + deg_to_rad(bow_degrees)
	var roll: float = _rest_roll + deg_to_rad(bow_roll_degrees) * side
	_tween = _new_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(model, "rotation:x", pitch, bow_down_seconds)
	_tween.parallel().tween_property(model, "rotation:z", roll, bow_down_seconds)
	_tween.tween_interval(bow_hold_seconds)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(model, "rotation:x", _rest_pitch, bow_up_seconds)
	_tween.parallel().tween_property(model, "rotation:z", _rest_roll, bow_up_seconds)
	_tween.tween_callback(_rested)
	return bow_down_seconds + bow_hold_seconds + bow_up_seconds

func _step(model: Node3D, target: Node3D) -> float:
	var side: float = _side(target)
	var toward: Vector3 = _toward(target).rotated(Vector3.UP, -deg_to_rad(step_splay_degrees) * side)
	var out: Vector3 = _rest_position + toward * step_distance
	_tween = _new_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(model, "position:x", out.x, step_out_seconds)
	_tween.parallel().tween_property(model, "position:z", out.z, step_out_seconds)
	_tween.parallel().tween_method(func(t: float) -> void:
		model.position.y = _rest_position.y + sin(t * PI) * step_bob_m, 0.0, 1.0, step_out_seconds)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(model, "position", _rest_position, step_back_seconds)
	_tween.tween_callback(_rested)
	return step_out_seconds

func _leap(model: Node3D, target: Node3D) -> float:
	var side: float = _side(target)
	var toward: Vector3 = _toward(target)
	var across: Vector3 = toward.cross(Vector3.UP).normalized() * side
	var landing: Vector3 = _rest_position + toward * leap_forward_m + across * leap_drift_m
	var apex: Vector3 = (_rest_position + landing) * 0.5 + Vector3.UP * leap_height
	_tween = _new_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(model, "position", apex, leap_up_seconds)
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(model, "position", landing, leap_down_seconds)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(model, "position", _rest_position, leap_back_seconds)
	_tween.tween_callback(_rested)
	return leap_up_seconds + leap_down_seconds

# Any move still playing stopped, the model put back at rest - or, from
# rest, the rest pose taken.
func _back_to_rest(model: Node3D) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _resting:
		_rest_position = model.position
		_rest_pitch = model.rotation.x
		_rest_roll = model.rotation.z
	else:
		model.position = _rest_position
		model.rotation.x = _rest_pitch
		model.rotation.z = _rest_roll
	_resting = false

func _rested() -> void:
	_resting = true

func _new_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween

# The flat direction to `target` in the body's frame (the model's
# parent's), or the body's own forward with none.
func _toward(target: Node3D) -> Vector3:
	var body := get_parent().get_parent() as Node3D
	if body == null:
		return Vector3.FORWARD
	var world: Vector3 = Vector3.ZERO
	if target != null:
		world = target.global_position - body.global_position
	world.y = 0.0
	if world.length() < 0.0001:
		return Vector3.FORWARD
	var local: Vector3 = body.global_basis.inverse() * world.normalized()
	local.y = 0.0
	return local.normalized() if local.length() > 0.0001 else Vector3.FORWARD

# +1 or -1: which side of the pair this one stands on, across the line to
# `target` (or across its own forward) - so the two turn away from each
# other. 0 with no living partner: a lone one goes straight.
func _side(target: Node3D) -> float:
	var body := get_parent().get_parent() as Node3D
	if body == null or not body.is_inside_tree():
		return 0.0
	var group: StringName = body.get("group")
	if group == &"":
		return 0.0
	var partner: Node3D = null
	for node in body.get_tree().get_nodes_in_group("enemies"):
		if node == body or node.get("group") != group or node.is_queued_for_deletion():
			continue
		if node.has_method("is_defeated") and bool(node.call("is_defeated")):
			continue
		partner = node as Node3D
		break
	if partner == null:
		return 0.0
	var forward: Vector3 = body.global_basis * _toward(target)
	var right: Vector3 = forward.cross(Vector3.UP)
	var apart: float = (body.global_position - partner.global_position).dot(right)
	return 1.0 if apart >= 0.0 else -1.0
