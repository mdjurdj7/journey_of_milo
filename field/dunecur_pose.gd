extends Node3D
class_name DunecurPose

# The Dunecur's two procedural poses on one rig: its crest of bristles
# along the spine, folded flat when calm and rising a step with each
# stack of Roused, and its head, dipped to the bones while the field
# runs and lifted for a fight. An attachment like HeadTurn (EnemyData.
# attachment_scene_path): FieldEnemy instances it under the model root
# after its material pass, and the body's material is untouched, so the
# hover highlight and the hit flash still tint the whole body.
#
# The glb has no rig and carries the crest raised, fused into the body
# mesh, so at _ready() the mesh is skinned once (CodeSkin) onto:
#   - a still root ("body");
#   - a neck chain of neck_bones joints from the pivot near the withers
#     forward along the body, as HeadTurn's, each pitching 1/neck_bones of
#     the dip nose-down about the body's across axis;
#   - crest_segments crest bones spaced from the tail root to behind the
#     ears, each hinged at the crest's base under it. A segment over the
#     neck is a child of the neck joint there, so the head's dip carries
#     the crest along and the fold still folds on top of it.
# Which vertices are crest is a soft box in the body's own metres: along
# from crest_back_m to crest_front_m of the body's middle, within
# crest_half_width_m of the spine (wide enough to take the shoulder
# flaps beside it), and above the crest's base - its own top there,
# sampled from the mesh in slices along the body, less crest_depth_m.
# Directions come from the body, not the asset (RearPose's way).
#
# The crest: flat_fold_degrees back (the top toward the tail) with
# Roused at 0, rise_per_stack_degrees less per stack, the glb's own
# raised pose at 0 - and as it folds the band also squashes toward its
# base, to flat_squash of its height when fully folded, so nothing on the
# back or shoulders stands up when calm. Roused only stands it up during
# a fight (FieldEnemy.set_roused(), from BattleController after each card
# and each enemy turn); out of one - the field running - it is flat. Each
# change eases over crest_ease_seconds.
#
# The head: feed_dip_degrees nose-down while the field runs and the body
# is alive, eased over head_ease_seconds; level while the field is frozen
# (a fight, the zone intro), on death and while settling - HeadTurn's
# freeze rule. Runs in _process at PROCESS_MODE_ALWAYS, through the
# freeze.

@export_group("Crest Region")
# Along the body from its middle, metres: where the crest begins at the
# tail root (negative, toward the tail) and ends behind the ears.
@export var crest_back_m: float = -0.74:
	set(value):
		crest_back_m = value
		_rebuild()
@export var crest_front_m: float = 1.1:
	set(value):
		crest_front_m = value
		_rebuild()
# From here forward to crest_front_m - the nape and the tuft on top of
# the head - the band narrows to crest_nape_half_width_m, so it takes the
# tuft between the ears and leaves the ears, metres along.
@export var crest_nape_m: float = 0.72:
	set(value):
		crest_nape_m = value
		_rebuild()
@export var crest_nape_half_width_m: float = 0.1:
	set(value):
		crest_nape_half_width_m = value
		_rebuild()
# Over this last stretch before crest_front_m the fold fades out, so the
# tuft eases into the head rather than tearing from it, metres.
@export var crest_front_fade_m: float = 0.12:
	set(value):
		crest_front_fade_m = value
		_rebuild()
# How far either side of the spine the band reaches, metres.
@export var crest_half_width_m: float = 0.3:
	set(value):
		crest_half_width_m = value
		_rebuild()
# How far below the crest's top its base - the hinge - sits, metres.
@export var crest_depth_m: float = 0.2:
	set(value):
		crest_depth_m = value
		_rebuild()
# How soft the band's faces are, metres.
@export var crest_softness_m: float = 0.04:
	set(value):
		crest_softness_m = value
		_rebuild()
@export_range(1, 12) var crest_segments: int = 6:
	set(value):
		crest_segments = value
		_rebuild()
@export_group("")

@export_group("Crest Pose")
# The fold back with Roused at 0, degrees: flat.
@export_range(0.0, 120.0, 0.5) var flat_fold_degrees: float = 70.0:
	set(value):
		flat_fold_degrees = value
		_retarget_crest()
# How much of the fold each stack of Roused takes back, degrees.
@export_range(0.0, 60.0, 0.5) var rise_per_stack_degrees: float = 17.5:
	set(value):
		rise_per_stack_degrees = value
		_retarget_crest()
# The band's height, fully folded, as a fraction of its own: the squash
# that keeps the shoulder flaps down. 1 = no squash.
@export_range(0.05, 1.0, 0.01) var flat_squash: float = 0.35:
	set(value):
		flat_squash = value
		_apply_pose()
@export var crest_ease_seconds: float = 0.35
@export_group("")

@export_group("Head")
# The pivot near the withers: this far forward of the body's middle and
# this far above its underside, metres. Rebuilds the skin.
@export var pivot_forward_m: float = 0.8:
	set(value):
		pivot_forward_m = value
		_rebuild()
@export var pivot_up_m: float = 0.95:
	set(value):
		pivot_up_m = value
		_rebuild()
# The head and neck: within this far of the centre line ...
@export var head_half_width_m: float = 0.3:
	set(value):
		head_half_width_m = value
		_rebuild()
# ... and above this height over the underside, so the front legs stay.
@export var head_floor_m: float = 0.66:
	set(value):
		head_floor_m = value
		_rebuild()
@export var head_softness_m: float = 0.05:
	set(value):
		head_softness_m = value
		_rebuild()
# Ahead of the pivot, the length over which the dip goes from none to
# all of it, metres.
@export var neck_falloff_m: float = 0.3:
	set(value):
		neck_falloff_m = value
		_rebuild()
@export_range(1, 8) var neck_bones: int = 3:
	set(value):
		neck_bones = value
		_rebuild()
# Nose-down while feeding, degrees.
@export_range(0.0, 90.0, 0.5) var feed_dip_degrees: float = 40.0
@export var head_ease_seconds: float = 0.8
@export_group("")

var _skin: CodeSkin = null
var _ready_done: bool = false
# In the mesh's own space: the body's forward, up and across (forward x
# up: a turn about it by a positive angle folds the top toward the tail).
var _forward: Vector3 = Vector3.FORWARD
var _up: Vector3 = Vector3.UP
var _across: Vector3 = Vector3.RIGHT
# Bone indices: the neck joints and the crest segments.
var _neck_first: int = 1
var _crest_first: int = 1
# Roused stacks shown, and the fold now / easing from / to, degrees.
var _stacks: int = 0
var _fold: float = 70.0
var _fold_from: float = 70.0
var _fold_to: float = 70.0
var _fold_t: float = 1.0
# The head's dip now / from / to, degrees, and its ease.
var _dip: float = 0.0
var _dip_from: float = 0.0
var _dip_to: float = 0.0
var _dip_t: float = 1.0

func _ready() -> void:
	_skin = CodeSkin.on_body(get_parent() as Node3D, self, "DunecurSkeleton", "DunecurPose")
	if _skin == null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_done = true
	_fold = _crest_target()
	_fold_from = _fold
	_fold_to = _fold
	_dip = _dip_target()
	_dip_from = _dip
	_dip_to = _dip
	_rebuild()

func _body() -> FieldEnemy:
	return get_parent().get_parent() as FieldEnemy

# Roused's stacks (FieldEnemy.set_roused()): the crest eases to its step.
func set_roused(stacks: int) -> void:
	_stacks = maxi(stacks, 0)
	_retarget_crest()

# The crest's fold now, and where it is heading - degrees back from the
# glb's own raised pose.
func get_crest_fold_degrees() -> float:
	return _fold

func get_crest_target_degrees() -> float:
	return _crest_target()

# The head's dip now, degrees nose-down.
func get_head_dip_degrees() -> float:
	return _dip

# Flat out of a fight; in one, the fold Roused's stacks leave.
func _crest_target() -> float:
	var body := _body()
	if body != null and body.can_process():
		return flat_fold_degrees
	return clampf(flat_fold_degrees - rise_per_stack_degrees * float(_stacks), 0.0, flat_fold_degrees)

func _dip_target() -> float:
	var body := _body()
	if body == null or not body.can_process() or body.is_defeated() or body.is_settling():
		return 0.0
	return feed_dip_degrees

func _retarget_crest() -> void:
	if not _ready_done:
		return
	var target: float = _crest_target()
	if is_equal_approx(target, _fold_to):
		return
	_fold_from = _fold
	_fold_to = target
	_fold_t = 0.0

func _process(delta: float) -> void:
	if not _ready_done:
		return
	var changed: bool = false
	var crest_target: float = _crest_target()
	if not is_equal_approx(crest_target, _fold_to):
		_fold_from = _fold
		_fold_to = crest_target
		_fold_t = 0.0
	if _fold_t < 1.0:
		_fold_t = minf(_fold_t + delta / maxf(crest_ease_seconds, 0.01), 1.0)
		_fold = lerpf(_fold_from, _fold_to, smoothstep(0.0, 1.0, _fold_t))
		changed = true
	var dip_target: float = _dip_target()
	if not is_equal_approx(dip_target, _dip_to):
		_dip_from = _dip
		_dip_to = dip_target
		_dip_t = 0.0
	if _dip_t < 1.0:
		_dip_t = minf(_dip_t + delta / maxf(head_ease_seconds, 0.01), 1.0)
		_dip = lerpf(_dip_from, _dip_to, smoothstep(0.0, 1.0, _dip_t))
		changed = true
	if changed:
		_apply_pose()

# The skin, from the exports: axes in mesh space, the crest's top sampled
# along the body, each vertex's bones and weights, then the bones.
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
	_across = _forward.cross(_up).normalized()
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
		side_lo = minf(side_lo, v.dot(_across))
		side_hi = maxf(side_hi, v.dot(_across))
	var middle: float = (front_lo + front_hi) * 0.5
	var side_mid: float = (side_lo + side_hi) * 0.5

	# The crest's top along the body: the highest vertex within its half
	# width, in slices, a missing slice taking its neighbour's.
	var back: float = middle + crest_back_m / metres_per_unit
	var front: float = middle + crest_front_m / metres_per_unit
	var depth: float = crest_depth_m / metres_per_unit
	var soft: float = maxf(crest_softness_m, 0.0001) / metres_per_unit
	var front_fade: float = maxf(maxf(crest_front_fade_m, crest_softness_m), 0.0001) / metres_per_unit
	var slices: int = 32
	var tops: PackedFloat32Array = PackedFloat32Array()
	tops.resize(slices)
	tops.fill(-INF)
	var span: float = maxf(front - back, 0.0001)
	for v in vertices:
		var along: float = v.dot(_forward)
		if along < back or along > front or absf(v.dot(_across) - side_mid) > _half_width_at(along, middle, metres_per_unit):
			continue
		var slice: int = clampi(int((along - back) / span * float(slices)), 0, slices - 1)
		tops[slice] = maxf(tops[slice], v.dot(_up))
	for i in slices:
		if tops[i] == -INF:
			tops[i] = tops[i - 1] if i > 0 else floor_level
	for i in range(slices - 2, -1, -1):
		if tops[i] == floor_level and tops[i + 1] != floor_level:
			tops[i] = tops[i + 1]

	# The neck, as HeadTurn's: a pivot near the withers, joints a step of
	# the bend apart ahead of it.
	var pivot_front: float = middle + pivot_forward_m / metres_per_unit
	var pivot: Vector3 = _forward * pivot_front + _up * (floor_level + pivot_up_m / metres_per_unit) + _across * side_mid
	var bend: float = maxf(neck_falloff_m, 0.001) / metres_per_unit
	var head_soft: float = maxf(head_softness_m, 0.0001) / metres_per_unit
	var head_half: float = head_half_width_m / metres_per_unit
	var head_floor: float = floor_level + head_floor_m / metres_per_unit
	var joints: int = maxi(neck_bones, 1)
	var segments: int = maxi(crest_segments, 1)
	_neck_first = 1
	_crest_first = 1 + joints

	# Bones, in mesh space first: root, the neck joints, the crest hinges.
	var names := PackedStringArray(["body"])
	var parents := PackedInt32Array([-1])
	var globals: Array[Transform3D] = [Transform3D.IDENTITY]
	for k in joints:
		names.append("neck_%d" % (k + 1))
		parents.append(k)
		globals.append(Transform3D(Basis.IDENTITY, pivot + _forward * (bend * float(k) / float(joints))))
	# A crest hinge's basis: across, up, back - so its pose turns about
	# its X and squashes along its Y.
	var hinge_basis := Basis(_across, _up, -_forward)
	for s in segments:
		var along: float = back + span * (float(s) + 0.5) / float(segments)
		var base: float = _top_at(tops, along, back, span) - depth
		names.append("crest_%d" % (s + 1))
		# Over the neck, the joint it sits under carries it.
		var share: float = smoothstep(0.0, bend, along - pivot_front) * float(joints)
		parents.append(mini(int(round(share)), joints))
		globals.append(Transform3D(hinge_basis, _forward * along + _up * base + _across * side_mid))
	var rests: Array[Transform3D] = []
	for i in names.size():
		rests.append(globals[i] if parents[i] < 0 else globals[parents[i]].affine_inverse() * globals[i])

	# Weights: a crest vertex to its two nearest crest hinges; any other
	# vertex ahead of the pivot over the head floor to the neck chain, as
	# HeadTurn's; the rest to the root.
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(vertices.size() * 4)
	weights.resize(vertices.size() * 4)
	var crest_count: int = 0
	var head_count: int = 0
	for i in vertices.size():
		var v: Vector3 = vertices[i]
		var along: float = v.dot(_forward)
		var across: float = absf(v.dot(_across) - side_mid)
		var height: float = v.dot(_up)
		var base: float = _top_at(tops, along, back, span) - depth
		var band: float = _half_width_at(along, middle, metres_per_unit)
		var crest: float = (1.0 - smoothstep(band - soft, band + soft, across)) \
			* smoothstep(base - soft, base + soft, height) \
			* smoothstep(back - soft, back + soft, along) * (1.0 - smoothstep(front - front_fade, front, along))
		# The neck's share for this vertex, spread over the chain.
		var head_inside: float = (1.0 - smoothstep(head_half - head_soft, head_half + head_soft, across)) \
			* smoothstep(head_floor - head_soft, head_floor + head_soft, height)
		var share: float = head_inside * smoothstep(0.0, bend, along - pivot_front) * float(joints)
		var low: int = mini(int(floor(share)), joints)
		var high: int = mini(low + 1, joints)
		var blend: float = share - float(low) if high > low else 0.0
		# The neck pair: bone 0 the root, bone k the k-th joint.
		var neck_low: int = 0 if low == 0 else _neck_first + low - 1
		var neck_high: int = 0 if high == 0 else _neck_first + high - 1
		# The crest pair: the hinges either side along.
		var slot: float = (along - back) / span * float(segments) - 0.5
		var seg_low: int = clampi(int(floor(slot)), 0, segments - 1)
		var seg_high: int = clampi(seg_low + 1, 0, segments - 1)
		var seg_blend: float = clampf(slot - float(seg_low), 0.0, 1.0) if seg_high > seg_low else 0.0
		bones[i * 4] = neck_low
		bones[i * 4 + 1] = neck_high
		bones[i * 4 + 2] = _crest_first + seg_low
		bones[i * 4 + 3] = _crest_first + seg_high
		weights[i * 4] = (1.0 - crest) * (1.0 - blend)
		weights[i * 4 + 1] = (1.0 - crest) * blend
		weights[i * 4 + 2] = crest * (1.0 - seg_blend)
		weights[i * 4 + 3] = crest * seg_blend
		if crest > 0.0:
			crest_count += 1
		if share > 0.0:
			head_count += 1
	_skin.apply_weights(bones, weights)
	_skin.set_bones(names, parents, rests)
	print("DunecurPose: %d of %d vertices in the crest over %d segments, %d in the head over %d joints." % [crest_count, vertices.size(), segments, head_count, joints])
	_apply_pose()

# The band's half width at `along`, mesh units: crest_half_width_m, and
# crest_nape_half_width_m from the nape forward (eased over the softness).
func _half_width_at(along: float, middle: float, metres_per_unit: float) -> float:
	var nape: float = middle + crest_nape_m / metres_per_unit
	var soft: float = maxf(crest_softness_m, 0.0001) / metres_per_unit
	return lerpf(crest_half_width_m, crest_nape_half_width_m, smoothstep(nape - soft, nape + soft, along)) / metres_per_unit

# The crest's top at `along`, between the slices either side.
static func _top_at(tops: PackedFloat32Array, along: float, back: float, span: float) -> float:
	var slices: int = tops.size()
	var slot: float = clampf((along - back) / span * float(slices) - 0.5, 0.0, float(slices - 1))
	var low: int = int(floor(slot))
	var high: int = mini(low + 1, slices - 1)
	return lerpf(tops[low], tops[high], slot - float(low))

# The neck joints pitch their share of the dip nose-down; every crest
# hinge folds back by the fold and squashes toward its base with it.
func _apply_pose() -> void:
	if _skin == null or _skin.skeleton.get_bone_count() < _crest_first:
		return
	var skeleton: Skeleton3D = _skin.skeleton
	var joints: int = _crest_first - _neck_first
	var nod := Quaternion(_across, -deg_to_rad(_dip) / float(maxi(joints, 1)))
	for k in joints:
		var bone: int = _neck_first + k
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_rest(bone).origin)
		skeleton.set_bone_pose_rotation(bone, nod)
	var folded: float = clampf(_fold / maxf(flat_fold_degrees, 0.001), 0.0, 1.0)
	var squash: float = lerpf(1.0, flat_squash, folded)
	for bone in range(_crest_first, skeleton.get_bone_count()):
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		skeleton.set_bone_pose_position(bone, rest.origin)
		# About the hinge's own X (across): the top goes toward the tail.
		skeleton.set_bone_pose_rotation(bone, rest.basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(_fold)))
		skeleton.set_bone_pose_scale(bone, Vector3(1.0, squash, 1.0))
