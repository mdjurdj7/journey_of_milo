extends Node3D
class_name RearPose

# The Siltjaw rearing while its charge is queued: the front of the body
# lifts about a pivot near its middle, so the head and mandibles come up
# off the sand, and holds there until the charge lands or breaks. An
# attachment like DragonflyWings (EnemyData.attachment_scene_path) -
# FieldEnemy instances it under the model root and calls set_rearing()
# (see FieldEnemy.set_rearing(), driven by BattleController).
#
# Procedural, no clips: at _ready() the body's own mesh is skinned once
# onto a two-bone Skeleton3D made here (CodeSkin). Every vertex behind the pivot
# follows the still root bone; every vertex ahead of it follows a
# "front" bone whose rest sits on the pivot; across bend_blend_m at the
# pivot the weight blends from one to the other, so the body bends there
# rather than creasing. Rearing is that one bone rotating - the GPU does
# the rest, and a held pose costs nothing per frame. The segments inside
# the blend bunch as it bends - a thick neck at 45 degrees, a visible
# knot close up at 65 (at the battle frame's distance it still reads).
# Rotating the body whole and lifting it so the tail stays on the sand
# was tried and stood it on its tail at 65, so there is no such mode.
#
# Directions come from the body, not the asset: forward is the body's -Z
# and up its +Y, taken into the mesh's own space through the transforms
# FieldEnemy has already set (scale, yaw offset, grounding), so the pivot
# and the bend sit right whichever way a glb faces.
#
# The same skin breathes. A third bone, "breath", lies along the belly
# line; the soft segmented rear follows it, fading out across
# breath_blend_m centred breath_front_m ahead of the body's middle - on
# the Siltjaw, from the middle to just behind the head's plates, so the
# shell, jaws and eyes (separate pieces, all further forward) never move.
# A breath scales the bone across and up by 1 + breath_amount: the rear
# swells and settles on the belly, eased in and out (a cosine out and
# back). Each breath draws its own length, depth and rest after from this
# body's own random generator, the way SputterClaws spaces its claw, so
# there is no countable loop. It is independent of the front bone, so a
# reared body keeps breathing; once the body is settling on death
# (FieldEnemy.is_settling()) it eases out over breath_stop_seconds and
# stops. Not fold(): an attachment with fold() holds the sink back by
# settle_time (see FieldEnemy.settle_and_free()). Runs in _process at
# PROCESS_MODE_ALWAYS, like DragonflyWings - through the battle freeze
# and the reward screen - and leaves the bone alone while the body is
# hidden under its mound.
#
# The jaws open with the rear. The Siltjaw's two mandibles are the front
# of the main piece - two crescent lobes, apart ahead of glb z 0.55 and
# welded to the head behind it - not pieces of their own, so each lobe is
# skinned to a jaw bone by position (fading in across the weld band,
# neither side at the centre line) and only on the main piece: the face,
# cheek pads, palps, eyes and shell never move. Each jaw hinges at its
# own root and swings out about the head's up, mirrored, by jaw_degrees
# at the full rear. The jaw bones ride the front bone, and their angle is
# the rear's own fraction, so they track it - same curve, same timing -
# opening as the head lifts and closing as it drops, whether the charge
# lands, breaks or the burrow follows.
#
# The Snap winds up on the same bones (play_windup(), from FieldEnemy.
# play_attack_snap()): the front rises by head_raise_degrees and the jaws
# open - spreading by jaw_open_degrees and lifting their tips by
# jaw_lift_degrees about each hinge's own across axis, the part a side-on
# frame sees - over windup_time; the lunge starts as that ends, the jaws
# snap shut over snap_time to close on the frame the hit lands, and the
# head settles over settle_time. The front stands at whichever is higher
# of the rear and the wind-up, and the jaws spread by whichever is wider,
# so the charge looks as it did and a settle hands over to a rear without
# a jump; the lift is the wind-up's alone. A body already reared (the
# charge landing) doesn't wind up. get_rear_lift() counts the rear only,
# so the camera's fit and the intent hold still through a Snap.
#
# With hold_tell on, a queued Snap holds tell_fraction of the wind-up -
# head part raised, jaws slightly parted - through the player's turn
# (set_poised(), from BattleController._pose_for_intent()).

# How far the front comes up, degrees.
@export_range(0.0, 90.0, 0.5) var rear_degrees: float = 45.0:
	set(value):
		rear_degrees = value
		_measure()
		if _target > 0.0:
			_target = rear_degrees
			_set_angle(rear_degrees)
# The pivot: this far forward of the body's middle, and this far above
# its underside, metres.
@export var pivot_forward_m: float = 0.1:
	set(value):
		pivot_forward_m = value
		_rebuild()
@export var pivot_up_m: float = 0.15:
	set(value):
		pivot_up_m = value
		_rebuild()
# The length over which the body goes from flat to fully reared,
# centred on the pivot, metres.
@export var bend_blend_m: float = 0.5:
	set(value):
		bend_blend_m = value
		_rebuild()
# Up, and back down when the charge lands or is interrupted.
@export var rear_seconds: float = 0.5
@export var drop_seconds: float = 0.4

@export_group("Breath")
# Where the breathing rear fades out: the fade's centre, this far forward
# of the body's middle, and its length, metres. Rebuilds the skin.
@export var breath_front_m: float = 0.15:
	set(value):
		breath_front_m = value
		_rebuild()
@export var breath_blend_m: float = 0.3:
	set(value):
		breath_blend_m = value
		_rebuild()
# Read each frame, so an edit takes at once.
# How much the rear swells across and up at a breath's peak, as a
# fraction of its size.
@export var breath_amount: float = 0.03
# One swell and settle, seconds, before the variation below.
@export var breath_seconds: float = 3.5
# Each breath's length is breath_seconds times a factor drawn from
# 1 +- this; its depth is breath_amount times a factor drawn from
# (1 - breath_depth_variation) to 1.
@export_range(0.0, 0.9, 0.01) var breath_length_variation: float = 0.25
@export_range(0.0, 1.0, 0.01) var breath_depth_variation: float = 0.3
# The rest after each breath, drawn from 0 to this, seconds.
@export var breath_rest_max_seconds: float = 0.8
# From breathing to still once the body is settling on death.
@export var breath_stop_seconds: float = 0.4

@export_group("Jaws")
# How far each jaw swings out at the full rear, degrees. The jaws track
# the rear: at any moment they are open by the rear's own fraction of
# rear_degrees, so they open as the head lifts and close as it drops.
@export var jaw_degrees: float = 15.0:
	set(value):
		jaw_degrees = value
		_set_angle(_angle)
# The jaws' hinges: this far forward of the body's middle and this far
# either side of its centre line, metres (glb z 0.52, x +-0.2 on the
# Siltjaw - each lobe's own root, where it welds to the head).
@export var jaw_pivot_forward_m: float = 0.695:
	set(value):
		jaw_pivot_forward_m = value
		_rebuild()
@export var jaw_pivot_across_m: float = 0.267:
	set(value):
		jaw_pivot_across_m = value
		_rebuild()
# Where a jaw starts following its hinge: from nothing to fully over
# jaw_root_blend_m centred jaw_root_forward_m ahead of the body's middle
# - across the weld band behind the lobes (glb z 0.45-0.55).
@export var jaw_root_forward_m: float = 0.668:
	set(value):
		jaw_root_forward_m = value
		_rebuild()
@export var jaw_root_blend_m: float = 0.134:
	set(value):
		jaw_root_blend_m = value
		_rebuild()
# Within this far of the centre line a vertex follows neither jaw fully,
# so the weld between the two roots stretches rather than splits.
@export var jaw_midline_m: float = 0.04:
	set(value):
		jaw_midline_m = value
		_rebuild()

@export_group("Attack")
# The Snap's wind-up at its full: how far the front rises, how far each
# jaw spreads out and how far its tip lifts, degrees.
@export_range(0.0, 90.0, 0.5) var head_raise_degrees: float = 12.0:
	set(value):
		head_raise_degrees = value
		_apply_pose()
@export var jaw_open_degrees: float = 25.0:
	set(value):
		jaw_open_degrees = value
		_apply_pose()
@export var jaw_lift_degrees: float = 20.0:
	set(value):
		jaw_lift_degrees = value
		_apply_pose()
# Up and open before the lunge (eased in and out); the jaws shutting,
# ending as the lunge lands (eased in); the head back down after the hit.
# Read at each wind-up, so an edit takes on the next Snap.
@export var windup_time: float = 0.35:
	set(value):
		windup_time = value
@export var snap_time: float = 0.08:
	set(value):
		snap_time = value
@export var settle_time: float = 0.3:
	set(value):
		settle_time = value
# Hold tell_fraction of the wind-up while a Snap is queued (see the
# header). Off by default.
@export var hold_tell: bool = false:
	set(value):
		hold_tell = value
		_apply_tell()
@export_range(0.0, 1.0, 0.01) var tell_fraction: float = 0.4:
	set(value):
		tell_fraction = value
		_apply_tell()

var _skin: CodeSkin = null
var _skeleton: Skeleton3D = null
# In the mesh's own space: the pivot, the bend axis (forward x up, so a
# positive angle lifts the front) and up; metres per mesh unit.
var _pivot: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3.RIGHT
var _up: Vector3 = Vector3.UP
var _metres_per_unit: float = 1.0
# The source mesh's vertices and each one's weight on the front bone.
var _vertices: PackedVector3Array = PackedVector3Array()
var _weights: PackedFloat32Array = PackedFloat32Array()
# At rear_degrees: how much higher the top of the body stands, metres.
var _full_extra: float = 0.0
var _angle: float = 0.0
var _target: float = 0.0
var _tween: Tween = null
var _ready_done: bool = false
# The breath bone's rest in mesh space: across, up and back as its axes,
# on the belly line.
var _breath_rest: Transform3D = Transform3D.IDENTITY
# The breath now: seconds into the current breath (negative = resting
# that long before the next), its drawn length and depth, and the fade
# to still on death (1 breathing, 0 stopped).
var _breath_elapsed: float = 0.0
var _breath_length: float = 0.0
var _breath_depth: float = 0.0
var _breath_stop: float = 1.0
var _rng := RandomNumberGenerator.new()
# The jaws' hinges in mesh space: [right (+_axis), left].
var _jaw_pivots: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
# The wind-up now, as fractions of the full one: the head's raise and the
# jaws' opening (spread and lift together), moved apart since the jaws
# snap while the head is still up.
var _head_windup: float = 0.0
var _jaw_windup: float = 0.0
# Whether a queued Snap asks for the tell, and the wind-up and its settle
# while they run (set_poised() leaves the pose to the settle then).
var _poised: bool = false
var _attacking: bool = false
var _windup_tween: Tween = null

func _ready() -> void:
	_skin = CodeSkin.on_body(get_parent() as Node3D, self, "RearSkeleton", "RearPose")
	if _skin == null:
		return
	_skeleton = _skin.skeleton
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	# Arrives at rest: the first breath waits out a drawn rest.
	_draw_breath()
	_ready_done = true
	_rebuild()

func _process(delta: float) -> void:
	if not _ready_done:
		return
	var body := get_parent().get_parent() as Node3D
	if body != null and body.has_method("is_settling") and bool(body.call("is_settling")):
		_breath_stop = 0.0 if breath_stop_seconds <= 0.0 else maxf(_breath_stop - delta / breath_stop_seconds, 0.0)
	_breath_elapsed += delta
	if _breath_elapsed >= _breath_length:
		_draw_breath()
	if _skin.mesh_instance.is_visible_in_tree() or _breath_stop <= 0.0:
		_apply_breath()
	if _breath_stop <= 0.0:
		set_process(false)

# The next breath: a rest drawn from 0..breath_rest_max_seconds, then a
# swell and settle of its own length and depth.
func _draw_breath() -> void:
	_breath_elapsed = -_rng.randf_range(0.0, maxf(breath_rest_max_seconds, 0.0))
	_breath_length = maxf(breath_seconds, 0.01) * _rng.randf_range(1.0 - breath_length_variation, 1.0 + breath_length_variation)
	_breath_depth = _rng.randf_range(1.0 - breath_depth_variation, 1.0)

# How far the rear is swollen right now, as a fraction of its size.
func get_breath_swell() -> float:
	if _breath_elapsed <= 0.0 or _breath_length <= 0.0:
		return 0.0
	var phase: float = clampf(_breath_elapsed / _breath_length, 0.0, 1.0)
	return breath_amount * _breath_depth * _breath_stop * 0.5 * (1.0 - cos(TAU * phase))

# The breath bone at the current swell, across and up about the belly
# line.
func _apply_breath() -> void:
	if _skeleton == null or _skeleton.get_bone_count() < 3:
		return
	var swell: float = get_breath_swell()
	_skeleton.set_bone_pose_position(2, _breath_rest.origin)
	_skeleton.set_bone_pose_rotation(2, _breath_rest.basis.get_rotation_quaternion())
	_skeleton.set_bone_pose_scale(2, Vector3(1.0 + swell, 1.0 + swell, 1.0))

# FieldEnemy.set_rearing(): up to rear_degrees over rear_seconds, or down
# over drop_seconds (see the easing below); returns how long that takes - 0 when it is
# already heading there. Through the battle freeze (PAUSE_PROCESS).
func set_rearing(on: bool) -> float:
	if not _ready_done:
		return 0.0
	var target: float = rear_degrees if on else 0.0
	if is_equal_approx(target, _target):
		return 0.0
	_target = target
	var seconds: float = maxf(rear_seconds if on else drop_seconds, 0.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if seconds <= 0.0:
		_set_angle(target)
		return 0.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Up eases in and out; down eases out - it gives way at once and lands
	# soft, so a charge broken mid-turn settles on the very frame its ring
	# closes (BattleController._resolve_play()) rather than after a pause.
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if on else Tween.EASE_OUT)
	_tween.tween_method(_set_angle, _angle, target, seconds)
	return seconds

# How much higher than flat the top of the body stands right now, metres
# - FieldEnemy adds it to its head height, so the intent and the camera
# fit clear a reared head.
func get_rear_lift() -> float:
	if rear_degrees <= 0.0:
		return 0.0
	return _full_extra * clampf(_angle / rear_degrees, 0.0, 1.0)

# The skin, from the exports: the pivot and axes in mesh space, each
# vertex's weights (front, a jaw, breath, the rest on the still root), the
# mesh rebuilt once with bones/weights, the five bones and their binds.
func _rebuild() -> void:
	if not _ready_done:
		return
	var body := get_parent().get_parent() as Node3D
	if body == null:
		return
	var to_body: Transform3D = body.global_transform.affine_inverse() * _skin.mesh_instance.global_transform
	var from_body: Basis = to_body.basis.inverse()
	var forward: Vector3 = (from_body * Vector3.FORWARD).normalized()
	_up = (from_body * Vector3.UP).normalized()
	_axis = forward.cross(_up).normalized()
	_metres_per_unit = to_body.basis.get_scale().x

	_vertices = _skin.get_vertices()
	var front_lo: float = INF
	var front_hi: float = -INF
	var floor_level: float = INF
	var side_lo: float = INF
	var side_hi: float = -INF
	for v in _vertices:
		front_lo = minf(front_lo, v.dot(forward))
		front_hi = maxf(front_hi, v.dot(forward))
		floor_level = minf(floor_level, v.dot(_up))
		side_lo = minf(side_lo, v.dot(_axis))
		side_hi = maxf(side_hi, v.dot(_axis))
	var pivot_front: float = (front_lo + front_hi) * 0.5 + pivot_forward_m / _metres_per_unit
	_pivot = forward * pivot_front + _up * (floor_level + pivot_up_m / _metres_per_unit) + _axis * ((side_lo + side_hi) * 0.5)

	var half_blend: float = maxf(bend_blend_m, 0.001) * 0.5 / _metres_per_unit
	# The breath: its fade along the body, and its bone on the belly line
	# with across, up and back as its axes (a right-handed basis, so the
	# pose scale's X and Y are the short axes).
	var breath_centre: float = (front_lo + front_hi) * 0.5 + breath_front_m / _metres_per_unit
	var breath_half: float = maxf(breath_blend_m, 0.001) * 0.5 / _metres_per_unit
	var belly: Vector3 = forward * pivot_front + _up * floor_level + _axis * ((side_lo + side_hi) * 0.5)
	_breath_rest = Transform3D(Basis(_axis, _up, -forward), belly)
	# The jaws: the two lobes at the front of the main piece, each on its
	# own bone hinged at its root. Only the main piece - the face, cheek
	# pads, palps, eyes and shell are pieces of their own, and the cheek
	# pads sit inside the crescents where a box would catch them.
	var middle: float = (front_lo + front_hi) * 0.5
	var side_mid: float = (side_lo + side_hi) * 0.5
	var jaw_hinge: Vector3 = forward * (middle + jaw_pivot_forward_m / _metres_per_unit) + _up * floor_level + _axis * side_mid
	_jaw_pivots = [jaw_hinge + _axis * (jaw_pivot_across_m / _metres_per_unit), jaw_hinge - _axis * (jaw_pivot_across_m / _metres_per_unit)]
	var jaw_root: float = middle + jaw_root_forward_m / _metres_per_unit
	var jaw_half: float = maxf(jaw_root_blend_m, 0.001) * 0.5 / _metres_per_unit
	var midline: float = maxf(jaw_midline_m, 0.0001) / _metres_per_unit
	var main_piece: PackedByteArray = _main_piece(_skin.arrays[Mesh.ARRAY_INDEX])
	_weights.resize(_vertices.size())
	var bones := PackedInt32Array()
	var bone_weights := PackedFloat32Array()
	bones.resize(_vertices.size() * 4)
	bone_weights.resize(_vertices.size() * 4)
	for i in _vertices.size():
		var along: float = _vertices[i].dot(forward)
		var w: float = smoothstep(pivot_front - half_blend, pivot_front + half_blend, along)
		var breath: float = (1.0 - w) * (1.0 - smoothstep(breath_centre - breath_half, breath_centre + breath_half, along))
		var across: float = _vertices[i].dot(_axis) - side_mid
		var jaw: float = 0.0
		if main_piece[i] == 1:
			jaw = w * smoothstep(jaw_root - jaw_half, jaw_root + jaw_half, along) * smoothstep(0.0, midline, absf(across))
		_weights[i] = w
		bones[i * 4] = 0
		bones[i * 4 + 1] = 1
		bones[i * 4 + 2] = 2
		bones[i * 4 + 3] = 3 if across >= 0.0 else 4
		bone_weights[i * 4] = 1.0 - w - breath
		bone_weights[i * 4 + 1] = w - jaw
		bone_weights[i * 4 + 2] = breath
		bone_weights[i * 4 + 3] = jaw
	_skin.apply_weights(bones, bone_weights)

	# The breath hangs off the still root; the jaws ride the front bone, so
	# they lift with the rear and open on top of it.
	_skin.set_bones(
		PackedStringArray(["body", "front", "breath", "jaw_right", "jaw_left"]),
		PackedInt32Array([-1, 0, 0, 1, 1]),
		[
			Transform3D.IDENTITY,
			Transform3D(Basis.IDENTITY, _pivot),
			_breath_rest,
			Transform3D(Basis.IDENTITY, _jaw_pivots[0] - _pivot),
			Transform3D(Basis.IDENTITY, _jaw_pivots[1] - _pivot),
		] as Array[Transform3D])
	_measure()
	_set_angle(_angle)
	_apply_breath()
	_apply_tell()

# At rear_degrees: how far the body's top rises - one pass over the
# vertices, the same linear blend the GPU does.
func _measure() -> void:
	if not _ready_done or _vertices.is_empty():
		return
	var turn := Basis(_axis, deg_to_rad(rear_degrees))
	var top_flat: float = -INF
	var top_reared: float = -INF
	for i in _vertices.size():
		var v: Vector3 = _vertices[i]
		var reared: Vector3 = _pivot + turn * (v - _pivot)
		top_flat = maxf(top_flat, v.dot(_up))
		top_reared = maxf(top_reared, v.lerp(reared, _weights[i]).dot(_up))
	_full_extra = (top_reared - top_flat) * _metres_per_unit

# The rear at `degrees`, and the pose redrawn.
func _set_angle(degrees: float) -> void:
	_angle = degrees
	_apply_pose()

# The front bone about the bend axis, on the pivot (its rest), at the
# higher of the rear and the wind-up's raise; the jaws spread by the
# wider of the rear's share of jaw_degrees and the wind-up's, and lifted
# by the wind-up's share of jaw_lift_degrees.
func _apply_pose() -> void:
	if _skeleton == null or _skeleton.get_bone_count() < 2:
		return
	_skeleton.set_bone_pose_position(0, Vector3.ZERO)
	_skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	_skeleton.set_bone_pose_position(1, _pivot)
	var front: float = maxf(_angle, head_raise_degrees * _head_windup)
	_skeleton.set_bone_pose_rotation(1, Quaternion(_axis, deg_to_rad(front)))
	if _skeleton.get_bone_count() < 5:
		return
	# About the head's own up; a turn of -angle takes a tip ahead of the
	# hinge toward +_axis (up x forward is -_axis), so the right jaw turns
	# by -open and the left by +open. The lift turns about _axis first -
	# positive raises a tip ahead of its hinge, as the rear does - so it
	# stays a lift whichever way the spread then takes it.
	var fraction: float = clampf(_angle / rear_degrees, 0.0, 1.0) if rear_degrees > 0.0 else 0.0
	var open: float = deg_to_rad(maxf(jaw_degrees * fraction, jaw_open_degrees * _jaw_windup))
	var lift := Quaternion(_axis, deg_to_rad(jaw_lift_degrees * _jaw_windup))
	for side in 2:
		_skeleton.set_bone_pose_position(3 + side, _jaw_pivots[side] - _pivot)
		_skeleton.set_bone_pose_rotation(3 + side, Quaternion(_up, -open if side == 0 else open) * lift)

# FieldEnemy.play_attack_snap(), before its lunge: the wind-up, the snap
# timed to end land_after seconds after the wind-up does (the lunge's
# own landing), then the settle. Returns how long the lunge waits - 0
# for a body already reared (the charge) or not yet skinned.
func play_windup(land_after: float) -> float:
	if not _ready_done or _skeleton == null or _target > 0.0:
		return 0.0
	var windup: float = maxf(windup_time, 0.0)
	var snap: float = maxf(snap_time, 0.0)
	if _windup_tween != null and _windup_tween.is_valid():
		_windup_tween.kill()
	_attacking = true
	_windup_tween = create_tween()
	_windup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_windup_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_windup_tween.tween_method(_set_head_windup, _head_windup, 1.0, windup)
	_windup_tween.parallel().tween_method(_set_jaw_windup, _jaw_windup, 1.0, windup)
	# Held open until the snap has just long enough left to close on the
	# landing (a snap longer than the lunge starts as the wind-up ends).
	var hold: float = maxf(land_after - snap, 0.0)
	if hold > 0.0:
		_windup_tween.tween_interval(hold)
	_windup_tween.set_ease(Tween.EASE_IN)
	_windup_tween.tween_method(_set_jaw_windup, 1.0, 0.0, snap)
	_windup_tween.set_ease(Tween.EASE_IN_OUT)
	_windup_tween.tween_method(_settle_step, 0.0, 1.0, maxf(settle_time, 0.0))
	_windup_tween.tween_callback(_end_windup)
	return windup

func _set_head_windup(value: float) -> void:
	_head_windup = value
	_apply_pose()

func _set_jaw_windup(value: float) -> void:
	_jaw_windup = value
	_apply_pose()

# The settle, t from 0 to 1: the head down from full and the jaws up from
# shut, both to the tell's level - read live, so a tell asked for mid-
# settle is where it ends.
func _settle_step(t: float) -> void:
	var level: float = _tell_level()
	_head_windup = lerpf(1.0, level, t)
	_jaw_windup = lerpf(0.0, level, t)
	_apply_pose()

func _end_windup() -> void:
	_attacking = false
	_apply_tell()

# BattleController._pose_for_intent(): whether a Snap is queued. Shows
# only with hold_tell on.
func set_poised(on: bool) -> void:
	_poised = on
	_apply_tell()

func _tell_level() -> float:
	return tell_fraction if hold_tell and _poised else 0.0

# The held pose eased to the tell's level - up over windup_time, down
# over settle_time - unless a wind-up is running, whose settle reads the
# level itself.
func _apply_tell() -> void:
	if not _ready_done or _attacking:
		return
	var level: float = _tell_level()
	if is_equal_approx(level, _head_windup) and is_equal_approx(level, _jaw_windup):
		return
	if _windup_tween != null and _windup_tween.is_valid():
		_windup_tween.kill()
	var seconds: float = maxf(windup_time if level > _head_windup else settle_time, 0.0)
	if seconds <= 0.0:
		_head_windup = level
		_jaw_windup = level
		_apply_pose()
		return
	_windup_tween = create_tween()
	_windup_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_windup_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_windup_tween.tween_method(_set_head_windup, _head_windup, level, seconds)
	_windup_tween.parallel().tween_method(_set_jaw_windup, _jaw_windup, level, seconds)

# 1 for each vertex of the mesh's largest piece - connected by its
# triangles, or sharing a position with a vertex that is (a UV seam
# splits a vertex without splitting the surface) - 0 for the rest.
func _main_piece(indices: PackedInt32Array) -> PackedByteArray:
	var count: int = _vertices.size()
	var parent := PackedInt32Array()
	parent.resize(count)
	for i in count:
		parent[i] = i
	var at_position: Dictionary = {}
	for i in count:
		var key: Vector3 = _vertices[i]
		if at_position.has(key):
			_union(parent, i, int(at_position[key]))
		else:
			at_position[key] = i
	for t in range(0, indices.size() - 2, 3):
		_union(parent, indices[t], indices[t + 1])
		_union(parent, indices[t + 1], indices[t + 2])
	var sizes: Dictionary = {}
	var biggest: int = -1
	for i in count:
		var root: int = _find(parent, i)
		var size: int = int(sizes.get(root, 0)) + 1
		sizes[root] = size
		if biggest < 0 or size > int(sizes[biggest]):
			biggest = root
	var main := PackedByteArray()
	main.resize(count)
	for i in count:
		main[i] = 1 if _find(parent, i) == biggest else 0
	return main

func _find(parent: PackedInt32Array, i: int) -> int:
	var root: int = i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var next: int = parent[i]
		parent[i] = root
		i = next
	return root

func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		parent[ra] = rb
