extends Node3D
class_name HeadTurn

# The Wardling's head and neck turning toward the Wanderer as he comes
# near - only the head and neck; the body never turns in the field. An
# attachment like RearPose (EnemyData.attachment_scene_path): FieldEnemy
# instances it under the model root after its material pass.
#
# Procedural, no clips: at _ready() the body's own mesh is skinned once
# (CodeSkin) onto a root bone and a chain of neck_bones bones from the
# pivot at the neck's base forward along the body, each turning
# 1/neck_bones of the head's angle about the body's up. Which vertices
# follow is a soft box in the body's own metres - ahead of the pivot,
# within region_half_width_m of the centre line, above region_floor_m -
# so the neck and head turn and the front legs beside and under them
# don't; across falloff_m ahead of the pivot a vertex goes from none of
# the turn to all of it, spread over the chain so the neck bends smoothly
# rather than kinking at one joint. The body's material is untouched, so
# the hover highlight and the hit flash still tint the whole body.
#
# Directions come from the body, not the asset (RearPose's way): forward
# is the body's -Z and up its +Y, taken into the mesh's own space through
# the transforms FieldEnemy has already set, so the pivot sits right
# whichever way a glb faces.
#
# The look: within look_range_m of the pivot the head turns toward the
# Wanderer, up to max_angle_degrees either side of the body's forward and
# no further; beyond the range it turns back to the front. The angle
# eases in and out - it speeds up over turn_ease_seconds to at most
# turn_speed_degrees a second and slows to a stop as it arrives. While
# the field is frozen (a fight - the body itself faces the Wanderer then
# - or the zone intro), on death and while settling, the head eases back
# to the front. Runs in _process at PROCESS_MODE_ALWAYS, through the
# freeze, so the head comes round in the battle frame as well.

@export_group("Region")
# The pivot at the neck's base: this far forward of the body's middle
# and this far above its underside, metres. Rebuilds the skin.
@export var pivot_forward_m: float = 0.55:
	set(value):
		pivot_forward_m = value
		_rebuild()
@export var pivot_up_m: float = 1.68:
	set(value):
		pivot_up_m = value
		_rebuild()
# The turning region: within this far either side of the centre line ...
@export var region_half_width_m: float = 0.17:
	set(value):
		region_half_width_m = value
		_rebuild()
# ... and above this height over the underside, metres.
@export var region_floor_m: float = 0.5:
	set(value):
		region_floor_m = value
		_rebuild()
# How soft the region's side and floor faces are, metres.
@export var region_softness_m: float = 0.05:
	set(value):
		region_softness_m = value
		_rebuild()
# Ahead of the pivot, the length over which the turn goes from none to
# all of it - the bend, metres.
@export var falloff_m: float = 0.6:
	set(value):
		falloff_m = value
		_rebuild()
# How many bones share the bend.
@export_range(1, 8) var neck_bones: int = 4:
	set(value):
		neck_bones = value
		_rebuild()
@export_group("")

@export_group("Look")
# Read each frame, so an edit takes at once.
# How near, from the pivot, the Wanderer has to be for the head to turn.
@export var look_range_m: float = 6.0
# The furthest the head turns either side of the body's forward.
@export_range(0.0, 120.0, 0.5) var max_angle_degrees: float = 70.0
# The fastest it turns, and how long it takes to get up to (and down
# from) that speed.
@export var turn_speed_degrees: float = 75.0
@export var turn_ease_seconds: float = 0.6
@export_group("")

var _skin: CodeSkin = null
var _ready_done: bool = false
# In the mesh's own space: the pivot, the body's forward and up.
var _pivot: Vector3 = Vector3.ZERO
var _forward: Vector3 = Vector3.FORWARD
var _up: Vector3 = Vector3.UP
# The head's angle now and its speed, degrees and degrees a second;
# positive turns it to the body's left.
var _angle: float = 0.0
var _speed: float = 0.0

func _ready() -> void:
	_skin = CodeSkin.on_body(get_parent() as Node3D, self, "NeckSkeleton", "HeadTurn")
	if _skin == null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_done = true
	_rebuild()

func _body() -> FieldEnemy:
	return get_parent().get_parent() as FieldEnemy

# The skin, from the exports: the pivot and axes in mesh space, each
# vertex's share of the turn, the mesh rebuilt with two neighbouring
# chain bones per vertex, and the chain.
func _rebuild() -> void:
	if not _ready_done:
		return
	var body := _body()
	if body == null:
		return
	var to_body: Transform3D = body.global_transform.affine_inverse() * _skin.mesh_instance.global_transform
	var from_body: Basis = to_body.basis.inverse()
	_forward = (from_body * Vector3.FORWARD).normalized()
	_up = (from_body * Vector3.UP).normalized()
	var across: Vector3 = _forward.cross(_up).normalized()
	var metres_per_unit: float = to_body.basis.get_scale().x

	var vertices: PackedVector3Array = _skin.get_vertices()
	var front_lo: float = INF
	var front_hi: float = -INF
	var floor_level: float = INF
	var side_lo: float = INF
	var side_hi: float = -INF
	for v in vertices:
		front_lo = minf(front_lo, v.dot(_forward))
		front_hi = maxf(front_hi, v.dot(_forward))
		floor_level = minf(floor_level, v.dot(_up))
		side_lo = minf(side_lo, v.dot(across))
		side_hi = maxf(side_hi, v.dot(across))
	var side_mid: float = (side_lo + side_hi) * 0.5
	var pivot_front: float = (front_lo + front_hi) * 0.5 + pivot_forward_m / metres_per_unit
	_pivot = _forward * pivot_front + _up * (floor_level + pivot_up_m / metres_per_unit) + across * side_mid

	var bend: float = maxf(falloff_m, 0.001) / metres_per_unit
	var soft: float = maxf(region_softness_m, 0.0001) / metres_per_unit
	var half_width: float = region_half_width_m / metres_per_unit
	var floor_top: float = floor_level + region_floor_m / metres_per_unit
	var count: int = maxi(neck_bones, 1)
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(vertices.size() * 4)
	weights.resize(vertices.size() * 4)
	var turning: int = 0
	for i in vertices.size():
		var v: Vector3 = vertices[i]
		var along: float = v.dot(_forward) - pivot_front
		var inside: float = (1.0 - smoothstep(half_width - soft, half_width + soft, absf(v.dot(across) - side_mid))) \
			* smoothstep(floor_top - soft, floor_top + soft, v.dot(_up))
		# The share of the full turn, spread over the chain: between bones
		# `low` and `low` + 1 (bone 0 the still root, bone k the k-th joint).
		var share: float = inside * smoothstep(0.0, bend, along) * float(count)
		var low: int = mini(int(floor(share)), count)
		var high: int = mini(low + 1, count)
		var blend: float = share - float(low) if high > low else 0.0
		bones[i * 4] = low
		bones[i * 4 + 1] = high
		weights[i * 4] = 1.0 - blend
		weights[i * 4 + 1] = blend
		if share > 0.0:
			turning += 1
	_skin.apply_weights(bones, weights)

	# The root, then the joints: the first on the pivot, each next one a
	# step of the bend further forward.
	var names := PackedStringArray(["body"])
	var parents := PackedInt32Array([-1])
	var rests: Array[Transform3D] = [Transform3D.IDENTITY]
	for k in count:
		names.append("neck_%d" % (k + 1))
		parents.append(k)
		rests.append(Transform3D(Basis.IDENTITY, _pivot if k == 0 else _forward * (bend / float(count))))
	_skin.set_bones(names, parents, rests)
	print("HeadTurn: %d of %d vertices turn, over %d bones." % [turning, vertices.size(), count])
	_apply_pose()

func _process(delta: float) -> void:
	if not _ready_done:
		return
	var target: float = _target_angle()
	# Ease in and out: the speed that would arrive in turn_ease_seconds,
	# capped, reached at no more than the cap per turn_ease_seconds.
	var ease_seconds: float = maxf(turn_ease_seconds, 0.01)
	var cap: float = maxf(turn_speed_degrees, 0.0)
	var wanted: float = clampf((target - _angle) / ease_seconds, -cap, cap)
	_speed = move_toward(_speed, wanted, cap / ease_seconds * delta)
	var step: float = _speed * delta
	# Never past the target.
	if absf(step) > absf(target - _angle):
		step = target - _angle
		_speed = 0.0
	if step != 0.0:
		_angle += step
		_apply_pose()

# Toward the Wanderer within look_range_m, clamped to max_angle_degrees;
# the front otherwise, and always while the field is frozen or the body
# is dead or going.
func _target_angle() -> float:
	var body := _body()
	if body == null or not body.can_process() or body.is_defeated() or body.is_settling():
		return 0.0
	var wanderer := get_tree().get_first_node_in_group("wanderer") as Node3D
	if wanderer == null:
		return 0.0
	var pivot: Vector3 = _skin.mesh_instance.global_transform * _pivot
	var to_wanderer := Vector3(wanderer.global_position.x - pivot.x, 0.0, wanderer.global_position.z - pivot.z)
	if to_wanderer.length() > look_range_m or to_wanderer.length() < 0.001:
		return 0.0
	var forward: Vector3 = -body.global_transform.basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var angle: float = rad_to_deg(forward.signed_angle_to(to_wanderer.normalized(), Vector3.UP))
	return clampf(angle, -max_angle_degrees, max_angle_degrees)

# Each joint turns its share of the angle about the body's up.
func _apply_pose() -> void:
	if _skin == null or _skin.skeleton.get_bone_count() < 2:
		return
	var skeleton: Skeleton3D = _skin.skeleton
	var count: int = skeleton.get_bone_count() - 1
	var turn := Quaternion(_up, deg_to_rad(_angle) / float(count))
	for k in range(1, count + 1):
		skeleton.set_bone_pose_position(k, skeleton.get_bone_rest(k).origin)
		skeleton.set_bone_pose_rotation(k, turn)

# The head's angle now, degrees (positive: to the body's left).
func get_head_angle() -> float:
	return _angle
