extends Node3D
class_name UnderfootPose

# The Underfoot's body (EnemyData.attachment_scene_path): a stingray lying
# in the sand at the waterline, Covered or Exposed as its queued intent
# says, its barb down or raised.
#
# Covered (the field, and while its Sting is queued): the model sunk to
# EnemyData.sink_m, so the disc's crown stands proud of the sand and its
# rim sits at the surface, and a sand-coloured pass over its back
# (field/underfoot_cover.gdshader) - fading off at the rim, so the disc's
# outline shows dark round the mound, and thinner over the eyes, so they
# still show. A visible mound, not a hidden one.
#
# The barb (set_rearing(), from BattleController._pose_for_intent() while
# the Sting is queued - EnemyIntent.rear_while_queued): down in the
# field, pitched along the tail into the sand; raised, it stands up out
# of it, held for the whole turn. A fight's first rise waits for the
# battle frame to settle (enter_battle_frame(), from FieldEnemy.enter_
# battle_hover()), so it comes up with the first intent.
#
# The Sting (play_windup(), from FieldEnemy.play_attack_snap()): the tail
# whips up and over toward the Wanderer, the body only nudging
# lunge_m after it - its nose is 0.4 m off the Sputter's back in the line
# (EnemyData.cluster_gap_m). The hit lands at the top of the whip; the
# barb drops with BattleController's set_rearing(false) after.
#
# Exposed (set_queued_status(), from _pose_for_intent() as the Rebury is
# queued): lifted clear of the sand to exposed_sink_m and tilted
# toward the camera by tilt_degrees - about the disc's near edge, so that
# edge stays on the sand - its fins raised by fin_raise_degrees and the
# cover gone: a dark patterned disc, its back to the camera. Covered
# again (the Sting queued after the Rebury), it settles back over
# rebury_seconds and the cover returns. An escape (exit_battle_frame(),
# from FieldEnemy.exit_battle_hover()) reburies it, barb down.
#
# The rig: CodeSkin bones - "body", the root, which the tilt turns about
# the near edge; "tail" behind the disc, which the whip and the raise
# pitch; "barb" on the tail; a fin each side. Regions by position in the
# body (metres from the disc's middle and the model's underside), so they
# sit right whichever way the glb faces. The cover's mask is measured on
# the rest pose into CUSTOM0 (r: the back, g: the eyes) like GreyshelfPose's
# throat. No particles, no glow.

const COVER_SHADER_PATH := "res://field/underfoot_cover.gdshader"
const BODY_BONE := 0
const TAIL_BONE := 1
const BARB_BONE := 2
const FIN_LEFT_BONE := 3
const FIN_RIGHT_BONE := 4

@export_group("Regions")
# Where the tail leaves the disc, and where the barb leaves the tail,
# metres behind the body's middle; the pivots' height over the underside.
# Rebuild the skin.
@export var tail_root_back_m: float = 0.16:
	set(value):
		tail_root_back_m = value
		_rebuild()
@export var tail_pivot_up_m: float = 0.05:
	set(value):
		tail_pivot_up_m = value
		_rebuild()
@export var barb_root_back_m: float = 0.33:
	set(value):
		barb_root_back_m = value
		_rebuild()
@export var barb_pivot_up_m: float = 0.07:
	set(value):
		barb_pivot_up_m = value
		_rebuild()
# The barb is what stands above this height over the underside, behind its
# root - the tail under it stays on the tail bone.
@export var barb_floor_m: float = 0.072:
	set(value):
		barb_floor_m = value
		_rebuild()
# The fins: what lies more than this far either side of the centre line,
# ahead of the tail root.
@export var fin_start_m: float = 0.3:
	set(value):
		fin_start_m = value
		_rebuild()
# The width of every region's soft edge, metres.
@export var region_softness_m: float = 0.012:
	set(value):
		region_softness_m = value
		_rebuild()
@export_group("")

@export_group("Barb")
# Degrees from the barb as modelled (about 17 degrees up off the tail):
# down in the field, laid along the tail into the sand, and raised for
# the telegraph, the tail lifting tail_raise_degrees under it.
@export_range(-45.0, 0.0, 0.5) var barb_down_degrees: float = -18.0:
	set(value):
		barb_down_degrees = value
		_measure()
		_apply_pose()
@export_range(0.0, 90.0, 0.5) var barb_raise_degrees: float = 55.0:
	set(value):
		barb_raise_degrees = value
		_measure()
		_apply_pose()
@export_range(0.0, 45.0, 0.5) var tail_raise_degrees: float = 8.0:
	set(value):
		tail_raise_degrees = value
		_measure()
		_apply_pose()
@export var rise_seconds: float = 0.5
@export var drop_seconds: float = 0.3
@export_group("")

@export_group("Sting")
# The whip: the tail pitched up and over by strike_tail_degrees, the barb
# by strike_barb_degrees more, over strike_seconds - the hit lands at the
# top - and the body nudged lunge_m toward the Wanderer after it.
@export_range(0.0, 90.0, 0.5) var strike_tail_degrees: float = 40.0
@export_range(0.0, 90.0, 0.5) var strike_barb_degrees: float = 25.0
@export var strike_seconds: float = 0.12
@export var lunge_m: float = 0.15
@export_group("")

@export_group("Exposed")
# The status whose being queued is Exposed (Status.id); any other is
# Covered.
@export var exposed_status_id: String = "exposed"
# Exposed: the sink it lifts to (0 = on its AABB feet), the tilt toward
# the camera about the disc's near edge, and the fins' lift, degrees.
@export var exposed_sink_m: float = 0.0:
	set(value):
		exposed_sink_m = value
		_apply_state()
@export_range(0.0, 60.0, 0.5) var tilt_degrees: float = 30.0:
	set(value):
		tilt_degrees = value
		_measure()
		_apply_pose()
@export_range(0.0, 30.0, 0.5) var fin_raise_degrees: float = 8.0:
	set(value):
		fin_raise_degrees = value
		_apply_pose()
@export var expose_seconds: float = 0.35
@export var rebury_seconds: float = 0.4
@export_group("")

@export_group("Cover")
# The sand over the back: its colour, how much of the body's own pattern
# shows through as grain, and how opaque it is at most.
@export var sand_colour: Color = Color(0.62, 0.55, 0.45):
	set(value):
		sand_colour = value
		_apply_cover()
@export_range(0.0, 1.0, 0.01) var grain: float = 0.12:
	set(value):
		grain = value
		_apply_cover()
@export_range(0.0, 1.0, 0.01) var cover_opacity: float = 0.88:
	set(value):
		cover_opacity = value
		_apply_cover()
# Over the eyes the cover is this fraction as opaque - they show through.
@export_range(0.0, 1.0, 0.01) var eye_opacity: float = 0.35:
	set(value):
		eye_opacity = value
		_apply_cover()
# The cover fades in over these heights above the underside, metres -
# from the sand line Covered (EnemyData.sink_m) up - so the band just
# above the sand is left dark as the disc's outline. Rebuild the skin.
@export var cover_rim_low_m: float = 0.09:
	set(value):
		cover_rim_low_m = value
		_rebuild()
@export var cover_rim_high_m: float = 0.13:
	set(value):
		cover_rim_high_m = value
		_rebuild()
# The eyes: this far ahead of the body's middle, this far either side of
# the centre line, and how far round each the cover thins, metres.
# Rebuild the skin.
@export var eye_forward_m: float = 0.66:
	set(value):
		eye_forward_m = value
		_rebuild()
@export var eye_across_m: float = 0.075:
	set(value):
		eye_across_m = value
		_rebuild()
@export var eye_radius_m: float = 0.05:
	set(value):
		eye_radius_m = value
		_rebuild()
@export_group("")

var _skin: CodeSkin = null
var _ready_done: bool = false
var _cover_material: ShaderMaterial = null
# In the mesh's own space: forward (head), up, across (forward x up), the
# middle, the underside, the half-width, the pivots, the barb's tip.
var _forward: Vector3 = Vector3.FORWARD
var _up: Vector3 = Vector3.UP
var _axis: Vector3 = Vector3.RIGHT
var _metres_per_unit: float = 1.0
var _side_mid: float = 0.0
var _half_width: float = 0.0
var _floor_level: float = 0.0
var _tail_pivot: Vector3 = Vector3.ZERO
var _barb_pivot: Vector3 = Vector3.ZERO
var _fin_pivot_left: Vector3 = Vector3.ZERO
var _fin_pivot_right: Vector3 = Vector3.ZERO
var _barb_tip: Vector3 = Vector3.ZERO
var _vertices: PackedVector3Array = PackedVector3Array()
var _tail_weights: PackedFloat32Array = PackedFloat32Array()
var _barb_weights: PackedFloat32Array = PackedFloat32Array()
# At the full raise and the full tilt: how much higher the top of the
# body stands than lying covered, metres.
var _raise_extra: float = 0.0
var _tilt_extra: float = 0.0

# 0 = down, 1 = raised; the strike's whip on top, 0..1.
var _barb: float = 0.0
var _barb_target: float = 0.0
var _whip: float = 0.0
var _barb_tween: Tween = null
var _whip_tween: Tween = null
# Whether a fight's frame has settled (enter_battle_frame()), and the
# barb's wish until it has.
var _in_frame: bool = false
var _barb_wanted: bool = false
# 0 = Covered, 1 = Exposed; the side the camera is on (+1 across, -1).
var _exposed: float = 0.0
var _exposed_target: float = 0.0
var _state_tween: Tween = null
var _camera_side: float = 1.0
# The body's sink Covered - EnemyData.sink_m, read once it has one.
var _covered_sink: float = -1.0

func _ready() -> void:
	_skin = CodeSkin.on_body(get_parent() as Node3D, self, "UnderfootSkeleton", "UnderfootPose")
	if _skin == null:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ready_done = true
	_rebuild()
	_add_cover_pass()

func _body() -> FieldEnemy:
	return get_parent().get_parent() as FieldEnemy

# The skin, from the exports: the axes and pivots in mesh space, and each
# vertex's weights - body, tail, barb, its side's fin - with the cover's
# mask in CUSTOM0.
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
	_axis = _forward.cross(_up).normalized()
	_metres_per_unit = to_body.basis.get_scale().x
	var units: float = 1.0 / _metres_per_unit

	_vertices = _skin.get_vertices()
	var normals: PackedVector3Array = _skin.arrays[Mesh.ARRAY_NORMAL]
	var front_lo: float = INF
	var front_hi: float = -INF
	var side_lo: float = INF
	var side_hi: float = -INF
	_floor_level = INF
	for v in _vertices:
		front_lo = minf(front_lo, v.dot(_forward))
		front_hi = maxf(front_hi, v.dot(_forward))
		side_lo = minf(side_lo, v.dot(_axis))
		side_hi = maxf(side_hi, v.dot(_axis))
		_floor_level = minf(_floor_level, v.dot(_up))
	var middle: float = (front_lo + front_hi) * 0.5
	_side_mid = (side_lo + side_hi) * 0.5
	_half_width = (side_hi - side_lo) * 0.5
	var tail_root: float = middle - tail_root_back_m * units
	var barb_root: float = middle - barb_root_back_m * units
	var soft: float = maxf(region_softness_m, 0.0001) * units
	var barb_floor: float = _floor_level + barb_floor_m * units
	var fin_start: float = fin_start_m * units
	var rim_low: float = _floor_level + cover_rim_low_m * units
	var rim_high: float = _floor_level + maxf(cover_rim_high_m, cover_rim_low_m + 0.001) * units
	var eye_along: float = middle + eye_forward_m * units
	var eye_radius: float = maxf(eye_radius_m, 0.001) * units
	_tail_pivot = _forward * tail_root + _up * (_floor_level + tail_pivot_up_m * units) + _axis * _side_mid
	_barb_pivot = _forward * barb_root + _up * (_floor_level + barb_pivot_up_m * units) + _axis * _side_mid
	var fin_height: Vector3 = _forward * middle + _up * (_floor_level + tail_pivot_up_m * units)
	_fin_pivot_left = fin_height + _axis * (_side_mid - fin_start)
	_fin_pivot_right = fin_height + _axis * (_side_mid + fin_start)

	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var custom := PackedFloat32Array()
	bones.resize(_vertices.size() * 4)
	weights.resize(_vertices.size() * 4)
	custom.resize(_vertices.size() * 4)
	_tail_weights.resize(_vertices.size())
	_barb_weights.resize(_vertices.size())
	var tip_along: float = INF
	var counts: Array[int] = [0, 0, 0]
	for i in _vertices.size():
		var v: Vector3 = _vertices[i]
		var along: float = v.dot(_forward)
		var across: float = v.dot(_axis) - _side_mid
		var height: float = v.dot(_up)
		var behind_tail: float = 1.0 - smoothstep(tail_root - soft, tail_root + soft, along)
		var barb: float = (1.0 - smoothstep(barb_root - soft, barb_root + soft, along)) * smoothstep(barb_floor - soft, barb_floor + soft, height)
		var tail: float = behind_tail * (1.0 - barb)
		var fin: float = (1.0 - behind_tail) * smoothstep(fin_start - soft, fin_start + soft * 4.0, absf(across))
		bones[i * 4] = BODY_BONE
		bones[i * 4 + 1] = TAIL_BONE
		bones[i * 4 + 2] = BARB_BONE
		bones[i * 4 + 3] = FIN_RIGHT_BONE if across > 0.0 else FIN_LEFT_BONE
		weights[i * 4] = 1.0 - tail - barb - fin
		weights[i * 4 + 1] = tail
		weights[i * 4 + 2] = barb
		weights[i * 4 + 3] = fin
		_tail_weights[i] = tail
		_barb_weights[i] = barb
		if barb > 0.5 and along < tip_along:
			tip_along = along
			_barb_tip = v
		# The cover: on the disc's back, faded off at the rim and thinned
		# over the eyes - measured on the rest pose.
		var normal_up: float = normals[i].dot(_up) if i < normals.size() else 1.0
		var back: float = (1.0 - behind_tail) * smoothstep(rim_low, rim_high, height) * smoothstep(0.0, 0.35, normal_up)
		var eye_offset: float = minf(Vector2(along - eye_along, across - eye_across_m * units).length(), Vector2(along - eye_along, across + eye_across_m * units).length())
		custom[i * 4] = back
		custom[i * 4 + 1] = 1.0 - smoothstep(eye_radius, eye_radius * 1.6, eye_offset)
		custom[i * 4 + 3] = 1.0
		if tail > 0.5:
			counts[0] += 1
		if barb > 0.5:
			counts[1] += 1
		if fin > 0.5:
			counts[2] += 1
	_skin.apply_weights(bones, weights, custom)

	var names := PackedStringArray(["body", "tail", "barb", "fin_left", "fin_right"])
	var parents := PackedInt32Array([-1, BODY_BONE, TAIL_BONE, BODY_BONE, BODY_BONE])
	var rests: Array[Transform3D] = [
		Transform3D.IDENTITY,
		Transform3D(Basis.IDENTITY, _tail_pivot),
		Transform3D(Basis.IDENTITY, _barb_pivot - _tail_pivot),
		Transform3D(Basis.IDENTITY, _fin_pivot_left),
		Transform3D(Basis.IDENTITY, _fin_pivot_right),
	]
	_skin.set_bones(names, parents, rests)
	print("UnderfootPose: of %d vertices, %d on the tail, %d on the barb, %d on the fins." % [_vertices.size(), counts[0], counts[1], counts[2]])
	_measure()
	_apply_pose()

# At the full raise and the full tilt: how far the body's top rises over
# lying covered - the same blend the GPU does, on the tail and barb shares
# and on the whole body.
func _measure() -> void:
	if not _ready_done or _vertices.is_empty():
		return
	var tail_turn := Basis(_axis, -deg_to_rad(tail_raise_degrees))
	var barb_turn := Basis(_axis, -deg_to_rad(barb_raise_degrees))
	var tilt := _tilt_transform(1.0)
	var top_flat: float = -INF
	var top_raised: float = -INF
	var top_tilted: float = -INF
	for i in _vertices.size():
		var v: Vector3 = _vertices[i]
		top_flat = maxf(top_flat, v.dot(_up))
		var tailed: Vector3 = _tail_pivot + tail_turn * (v - _tail_pivot)
		var barbed: Vector3 = _tail_pivot + tail_turn * (_barb_pivot + barb_turn * (v - _barb_pivot) - _tail_pivot)
		var raised: Vector3 = v.lerp(tailed, _tail_weights[i]).lerp(barbed, _barb_weights[i])
		top_raised = maxf(top_raised, raised.dot(_up))
		top_tilted = maxf(top_tilted, (tilt * v).dot(_up))
	_raise_extra = maxf(top_raised - top_flat, 0.0) * _metres_per_unit
	_tilt_extra = maxf(top_tilted - top_flat, 0.0) * _metres_per_unit

# The body's tilt at `fraction` of tilt_degrees: about the disc's edge on
# the camera's side, at the underside, so that edge stays down and the
# back turns to the camera.
func _tilt_transform(fraction: float) -> Transform3D:
	var edge: Vector3 = _forward * _tail_pivot.dot(_forward) + _up * _floor_level + _axis * (_side_mid + _camera_side * _half_width)
	edge -= _forward * edge.dot(_forward)
	var turn := Basis(_forward, deg_to_rad(tilt_degrees) * fraction * _camera_side)
	return Transform3D(turn, edge - turn * edge)

# The bones from the state: the body tilted by the Exposed fraction, the
# tail and barb from down through raised plus the whip, the fins lifted.
# A positive angle about _axis lifts what is ahead of a pivot, so the tail
# and barb - behind theirs - go up with a negative one.
func _apply_pose() -> void:
	if _skin == null or _skin.skeleton.get_bone_count() < 5:
		return
	var skeleton: Skeleton3D = _skin.skeleton
	var tilt: Transform3D = _tilt_transform(_exposed)
	skeleton.set_bone_pose_position(BODY_BONE, tilt.origin)
	skeleton.set_bone_pose_rotation(BODY_BONE, tilt.basis.get_rotation_quaternion())
	var tail_degrees: float = tail_raise_degrees * _barb + strike_tail_degrees * _whip
	skeleton.set_bone_pose_position(TAIL_BONE, skeleton.get_bone_rest(TAIL_BONE).origin)
	skeleton.set_bone_pose_rotation(TAIL_BONE, Quaternion(_axis, -deg_to_rad(tail_degrees)))
	var barb_degrees: float = lerpf(barb_down_degrees, barb_raise_degrees, _barb) + strike_barb_degrees * _whip
	skeleton.set_bone_pose_position(BARB_BONE, skeleton.get_bone_rest(BARB_BONE).origin)
	skeleton.set_bone_pose_rotation(BARB_BONE, Quaternion(_axis, -deg_to_rad(barb_degrees)))
	# About forward a positive angle takes the right (+_axis) side down.
	var fin: float = deg_to_rad(fin_raise_degrees) * _exposed
	skeleton.set_bone_pose_position(FIN_LEFT_BONE, skeleton.get_bone_rest(FIN_LEFT_BONE).origin)
	skeleton.set_bone_pose_rotation(FIN_LEFT_BONE, Quaternion(_forward, fin))
	skeleton.set_bone_pose_position(FIN_RIGHT_BONE, skeleton.get_bone_rest(FIN_RIGHT_BONE).origin)
	skeleton.set_bone_pose_rotation(FIN_RIGHT_BONE, Quaternion(_forward, -fin))

# The body's sink and the cover from the Exposed fraction.
func _apply_state() -> void:
	var body := _body()
	if body != null and _covered_sink >= 0.0:
		body.sink = lerpf(_covered_sink, exposed_sink_m, _exposed)
	_apply_cover()

func _apply_cover() -> void:
	if _cover_material == null:
		return
	_cover_material.set_shader_parameter("sand_colour", sand_colour)
	_cover_material.set_shader_parameter("grain", grain)
	_cover_material.set_shader_parameter("eye_opacity", eye_opacity)
	_cover_material.set_shader_parameter("cover", cover_opacity * (1.0 - _exposed))

# FieldEnemy.set_rearing(): the barb up for the queued Sting, or down.
# Before a fight's frame has settled the wish is kept for enter_battle_
# frame(). Raised after an Exposed body has settled back, so it comes up
# out of the sand. Returns how long that takes - 0 when it is already
# heading there.
func set_rearing(on: bool) -> float:
	if not _ready_done:
		return 0.0
	_barb_wanted = on
	if on and not _in_frame:
		return 0.0
	return _tween_barb(1.0 if on else 0.0, _state_left() if on else 0.0)

func _tween_barb(target: float, delay: float) -> float:
	if is_equal_approx(target, _barb_target):
		return 0.0
	_barb_target = target
	var seconds: float = maxf(rise_seconds if target > 0.0 else drop_seconds, 0.0)
	if _barb_tween != null and _barb_tween.is_valid():
		_barb_tween.kill()
	_barb_tween = create_tween()
	_barb_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		_barb_tween.tween_interval(delay)
	_barb_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if target > 0.0 else Tween.EASE_OUT)
	_barb_tween.tween_method(_set_barb, _barb, target, maxf(seconds, 0.001))
	# The whip, if a Sting was cut short, comes down with the barb.
	if target <= 0.0 and _whip > 0.0:
		_barb_tween.parallel().tween_method(_set_whip, _whip, 0.0, maxf(seconds, 0.001))
	return delay + seconds

func _set_barb(value: float) -> void:
	_barb = value
	_apply_pose()

func _set_whip(value: float) -> void:
	_whip = value
	_apply_pose()

# FieldEnemy.play_attack_snap(): the Sting's whip, up and over toward the
# Wanderer over strike_seconds - the hit lands at the top, the barb drops
# after (set_rearing(false)). Returns the whip's time, which the body's
# nudge waits on.
func play_windup(_land_after: float) -> float:
	if not _ready_done:
		return 0.0
	if _whip_tween != null and _whip_tween.is_valid():
		_whip_tween.kill()
	var seconds: float = maxf(strike_seconds, 0.001)
	_whip_tween = create_tween()
	_whip_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_whip_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_whip_tween.tween_method(_set_whip, _whip, 1.0, seconds)
	return seconds

# FieldEnemy.play_attack_snap(): how far the body itself lunges.
func get_lunge_distance() -> float:
	return maxf(lunge_m, 0.0)

# FieldEnemy.set_queued_status(): the queued intent's status_while_queued
# - Exposed for the Rebury, Covered for anything else. Lifts and tilts
# over expose_seconds, or settles back over rebury_seconds; returns how
# long that takes - 0 when it is already heading there, or for no status.
func set_queued_status(status: StatusData) -> float:
	if not _ready_done or status == null:
		return 0.0
	return _tween_state(1.0 if status.id == exposed_status_id else 0.0)

func _tween_state(target: float) -> float:
	if is_equal_approx(target, _exposed_target):
		return 0.0
	_exposed_target = target
	var body := _body()
	if body != null and _covered_sink < 0.0:
		_covered_sink = body.sink
	# Tilted toward the camera: its side of the disc's centre line, judged
	# as the tilt starts.
	if target > 0.0:
		var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		if camera != null:
			var to_camera: Vector3 = _skin.mesh_instance.global_transform.basis.inverse() * (camera.global_position - _skin.mesh_instance.global_position)
			_camera_side = 1.0 if to_camera.dot(_axis) >= 0.0 else -1.0
		_measure()
	var seconds: float = maxf(expose_seconds if target > 0.0 else rebury_seconds, 0.001)
	if _state_tween != null and _state_tween.is_valid():
		_state_tween.kill()
	_state_tween = create_tween()
	_state_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_state_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if target > 0.0 else Tween.EASE_IN_OUT)
	_state_tween.tween_method(_set_exposed, _exposed, target, seconds)
	return seconds

func _set_exposed(value: float) -> void:
	_exposed = value
	_apply_pose()
	_apply_state()

# How long the state's tween has left to run, seconds.
func _state_left() -> float:
	if _state_tween == null or not _state_tween.is_valid() or not _state_tween.is_running():
		return 0.0
	var seconds: float = expose_seconds if _exposed_target > 0.0 else rebury_seconds
	return maxf(seconds - _state_tween.get_total_elapsed_time(), 0.0)

# The fight's frame has settled (FieldEnemy.enter_battle_hover()): a barb
# asked for before now comes up.
func enter_battle_frame() -> void:
	_in_frame = true
	if _barb_wanted:
		_tween_barb(1.0, _state_left())

# An escape (FieldEnemy.exit_battle_hover()): back as the field has it -
# Covered, the barb down.
func exit_battle_frame() -> void:
	_in_frame = false
	_barb_wanted = false
	_tween_barb(0.0, 0.0)
	_tween_state(0.0)

# How much higher than lying covered the top of the body stands now,
# metres - FieldEnemy adds it to its head height, so the intent and the
# camera fit clear the raised barb and the tilted disc.
func get_rear_lift() -> float:
	return maxf(_raise_extra * _barb, _tilt_extra * _exposed)

# For the probes: the barb's raise (0 down, 1 raised), the Exposed
# fraction, the cover's opacity now, and the barb's tip and the point on
# its root, in the world.
func get_barb_raise() -> float:
	return _barb

func get_exposed() -> float:
	return _exposed

func get_cover() -> float:
	return cover_opacity * (1.0 - _exposed) if _cover_material != null else 0.0

func get_barb_tip() -> Vector3:
	return _posed_world(_barb_tip, BARB_BONE)

func get_barb_root() -> Vector3:
	return _posed_world(_barb_pivot, BARB_BONE)

func _posed_world(rest_point: Vector3, bone: int) -> Vector3:
	if _skin == null or _skin.skeleton.get_bone_count() <= bone:
		return global_position
	var skeleton: Skeleton3D = _skin.skeleton
	var posed: Vector3 = skeleton.get_bone_global_pose(bone) * (skeleton.get_bone_global_rest(bone).affine_inverse() * rest_point)
	return _skin.mesh_instance.global_transform * posed

# The cover's pass on the body's material - material_override, the one
# the highlight tints - as GreyshelfPose lays its throat.
func _add_cover_pass() -> void:
	var mesh_instance: MeshInstance3D = _skin.mesh_instance
	var body_material := mesh_instance.material_override as BaseMaterial3D
	if body_material == null:
		body_material = mesh_instance.get_active_material(0) as BaseMaterial3D
	if body_material == null:
		push_warning("UnderfootPose: the body has no material to lay the cover on.")
		return
	_cover_material = ShaderMaterial.new()
	_cover_material.shader = load(COVER_SHADER_PATH) as Shader
	_cover_material.set_shader_parameter("albedo_texture", body_material.albedo_texture)
	body_material.next_pass = _cover_material
	_apply_cover()
