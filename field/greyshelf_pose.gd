extends HeadTurn
class_name GreyshelfPose

# The Greyshelf's body (EnemyData.attachment_scene_path): HeadTurn's head,
# which also lifts, and the Gape's tell - the forequarters rearing off the
# rock while the throat swells and its blue deepens.
#
# The head (HeadTurn, unchanged in what it decides): within look_range_m
# the head and neck turn toward the Wanderer, and lift by lift_degrees,
# both eased the same way; frozen, dead or settling, both ease back. Only
# the head - the body lies as it lies, part of the rock. The throat is
# below region_floor_m, so it hangs where it is while the head comes up
# and stretches under it, the way a lizard's does.
#
# The tell (set_rearing(), from BattleController._pose_for_intent() while
# the Gape is queued - EnemyIntent.rear_while_queued): the front of the
# body lifts by rear_degrees about a pivot behind the shoulders, the way
# RearPose lifts the Siltjaw's, only across rear_half_width_m of the
# centre line and above rear_floor_m, so the forelegs and their feet stay
# planted and the chest comes up between them - the throat excepted,
# which comes up whole. The throat swells with it - a bone under the jaw scaled across,
# down and along by throat_swell at the full rear - and a next pass on
# the body's material (field/greyshelf_throat.gdshader) deepens and
# darkens its blue by the rear's own fraction of tell_deepen. Each Goaded
# stack (set_roused()) deepens it by goaded_deepen more, within the same
# rule: hue and value only, never lighter, nothing that glows. A broken
# Gape lets it all down on the card that broke it.
#
# The rig: CodeSkin bones - the still root, "fore" on the rear's pivot,
# HeadTurn's neck chain riding fore, and "throat" riding fore. Each vertex
# blends the root and fore across bend_blend_m at the pivot; ahead of the
# neck pivot its fore share goes on up the chain the way HeadTurn spreads
# it; the throat takes its share of fore's. Directions from the body, so
# the pivots sit right whichever way the glb faces.

const THROAT_SHADER_PATH := "res://field/greyshelf_throat.gdshader"

@export_group("Rear")
# How far the forequarters come up for the Gape, degrees.
@export_range(0.0, 45.0, 0.5) var rear_degrees: float = 14.0:
	set(value):
		rear_degrees = value
		_measure()
		if _rear_target > 0.0:
			_rear_target = rear_degrees
			_set_rear(rear_degrees)
# The rear's pivot: this far forward of the body's middle and this far
# above its underside, metres. Rebuilds the skin.
@export var rear_pivot_forward_m: float = 0.27:
	set(value):
		rear_pivot_forward_m = value
		_rebuild()
@export var rear_pivot_up_m: float = 0.41:
	set(value):
		rear_pivot_up_m = value
		_rebuild()
# The length over which the body goes from lying to reared, centred on
# the pivot, and how far either side of the centre line it lifts (the
# forelegs are outside it), metres.
@export var bend_blend_m: float = 0.8:
	set(value):
		bend_blend_m = value
		_rebuild()
@export var rear_half_width_m: float = 0.62:
	set(value):
		rear_half_width_m = value
		_rebuild()
@export var rear_side_softness_m: float = 0.14:
	set(value):
		rear_side_softness_m = value
		_rebuild()
# Below this height over the underside the body stays down - the feet -
# soft over rear_side_softness_m; the throat lifts whatever its height.
@export var rear_floor_m: float = 0.35:
	set(value):
		rear_floor_m = value
		_rebuild()
# Up, and back down when the Gape lands or breaks.
@export var rear_seconds: float = 0.6
@export var drop_seconds: float = 0.4
@export_group("")

@export_group("Head Lift")
# How far the head lifts while it looks, degrees, shared over the chain
# like the turn. Read each frame.
@export_range(0.0, 45.0, 0.5) var lift_degrees: float = 16.0
@export_group("")

@export_group("Throat")
# The throat as fractions of the mesh's own bounds (x across, y up from
# the feet, z from tail to snout): the box the swell moves, and the box
# the colour may deepen in (the jaw's blue as well). Rebuild the skin.
@export var swell_min: Vector3 = Vector3(0.32, 0.1, 0.75):
	set(value):
		swell_min = value
		_rebuild()
@export var swell_max: Vector3 = Vector3(0.68, 0.5, 0.97):
	set(value):
		swell_max = value
		_rebuild()
@export var colour_min: Vector3 = Vector3(0.3, 0.1, 0.74):
	set(value):
		colour_min = value
		_rebuild()
@export var colour_max: Vector3 = Vector3(0.7, 0.66, 1.0):
	set(value):
		colour_max = value
		_rebuild()
@export_range(0.0, 0.2) var throat_softness: float = 0.03:
	set(value):
		throat_softness = value
		_rebuild()
# The swell at the full rear: across, down and along the throat, as
# fractions of its size.
@export var throat_swell: Vector3 = Vector3(0.18, 0.3, 0.08):
	set(value):
		throat_swell = value
		_apply_pose()
# The blue deepened at the full rear, and by each Goaded stack on top -
# 0..1 of greyshelf_throat.gdshader's full deepen, held at 1.
@export_range(0.0, 1.0, 0.01) var tell_deepen: float = 0.75:
	set(value):
		tell_deepen = value
		_apply_throat_colour()
@export_range(0.0, 0.5, 0.01) var goaded_deepen: float = 0.08:
	set(value):
		goaded_deepen = value
		_apply_throat_colour()
@export_group("")

# In the mesh's own space: the rear's pivot and its axis (forward x up, so
# a positive angle lifts the front), the throat bone's rest.
var _rear_pivot: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3.RIGHT
var _throat_rest: Transform3D = Transform3D.IDENTITY
var _metres_per_unit: float = 1.0
var _chain: int = 1
# The rest vertices and each one's fore share, for the rear's measure.
var _vertices: PackedVector3Array = PackedVector3Array()
var _rear_weights: PackedFloat32Array = PackedFloat32Array()
# At rear_degrees: how much higher the top of the body stands, metres.
var _full_extra: float = 0.0
var _rear: float = 0.0
var _rear_target: float = 0.0
var _rear_tween: Tween = null
# The head's lift now, degrees, and its speed.
var _lift: float = 0.0
var _lift_speed: float = 0.0
var _stacks: int = 0
var _throat_material: ShaderMaterial = null

func _ready() -> void:
	super()
	if _skin != null:
		_add_throat_pass()

# HeadTurn's turn, then the lift eased the same way toward lift_degrees
# while the head has something to look at.
func _process(delta: float) -> void:
	super(delta)
	if not _ready_done:
		return
	var target: float = lift_degrees if _looking() else 0.0
	var ease_seconds: float = maxf(turn_ease_seconds, 0.01)
	var cap: float = maxf(turn_speed_degrees, 0.0)
	var wanted: float = clampf((target - _lift) / ease_seconds, -cap, cap)
	_lift_speed = move_toward(_lift_speed, wanted, cap / ease_seconds * delta)
	var step: float = _lift_speed * delta
	if absf(step) > absf(target - _lift):
		step = target - _lift
		_lift_speed = 0.0
	if step != 0.0:
		_lift += step
		_apply_pose()

# HeadTurn's own test for a turn, without the angle: the Wanderer in range
# of the pivot while the field runs and the body stands.
func _looking() -> bool:
	var body := _body()
	if body == null or not body.can_process() or body.is_defeated() or body.is_settling():
		return false
	var wanderer := get_tree().get_first_node_in_group("wanderer") as Node3D
	if wanderer == null:
		return false
	var pivot: Vector3 = _skin.mesh_instance.global_transform * _pivot
	var to_wanderer := Vector3(wanderer.global_position.x - pivot.x, 0.0, wanderer.global_position.z - pivot.z)
	return to_wanderer.length() <= look_range_m

# The skin: HeadTurn's pivot and chain, the rear's pivot, the throat, and
# every vertex's four weights - root, two neighbours on the fore/neck
# chain, throat - with the throat's colour mask in CUSTOM0.
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

	_vertices = _skin.get_vertices()
	var bounds: AABB = _skin.mesh_instance.mesh.get_aabb()
	var front_lo: float = INF
	var front_hi: float = -INF
	var floor_level: float = INF
	var side_lo: float = INF
	var side_hi: float = -INF
	for v in _vertices:
		front_lo = minf(front_lo, v.dot(_forward))
		front_hi = maxf(front_hi, v.dot(_forward))
		floor_level = minf(floor_level, v.dot(_up))
		side_lo = minf(side_lo, v.dot(_axis))
		side_hi = maxf(side_hi, v.dot(_axis))
	var middle: float = (front_lo + front_hi) * 0.5
	var side_mid: float = (side_lo + side_hi) * 0.5
	var neck_front: float = middle + pivot_forward_m / _metres_per_unit
	_pivot = _forward * neck_front + _up * (floor_level + pivot_up_m / _metres_per_unit) + _axis * side_mid
	var rear_front: float = middle + rear_pivot_forward_m / _metres_per_unit
	_rear_pivot = _forward * rear_front + _up * (floor_level + rear_pivot_up_m / _metres_per_unit) + _axis * side_mid

	var half_blend: float = maxf(bend_blend_m, 0.001) * 0.5 / _metres_per_unit
	var rear_half: float = rear_half_width_m / _metres_per_unit
	var rear_soft: float = maxf(rear_side_softness_m, 0.0001) / _metres_per_unit
	var rear_floor: float = floor_level + rear_floor_m / _metres_per_unit
	var bend: float = maxf(falloff_m, 0.001) / _metres_per_unit
	var soft: float = maxf(region_softness_m, 0.0001) / _metres_per_unit
	var half_width: float = region_half_width_m / _metres_per_unit
	var floor_top: float = floor_level + region_floor_m / _metres_per_unit
	_chain = maxi(neck_bones, 1)
	var throat_bone: int = _chain + 2

	# The throat bone: on the swell box's top centre, across, up and back
	# as its axes, so its scale's Y is the swell downward.
	var swell_top: Vector3 = bounds.position + bounds.size * Vector3((swell_min.x + swell_max.x) * 0.5, swell_max.y, (swell_min.z + swell_max.z) * 0.5)
	_throat_rest = Transform3D(Basis(_axis, _up, -_forward), swell_top)

	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var custom := PackedFloat32Array()
	bones.resize(_vertices.size() * 4)
	weights.resize(_vertices.size() * 4)
	custom.resize(_vertices.size() * 4)
	_rear_weights.resize(_vertices.size())
	var turning: int = 0
	for i in _vertices.size():
		var v: Vector3 = _vertices[i]
		var fraction: Vector3 = (v - bounds.position) / bounds.size
		var across: float = absf(v.dot(_axis) - side_mid)
		var swell_box: float = _in_box(fraction, swell_min, swell_max)
		var above: float = maxf(smoothstep(rear_floor - rear_soft, rear_floor + rear_soft, v.dot(_up)), swell_box)
		var rear: float = smoothstep(rear_front - half_blend, rear_front + half_blend, v.dot(_forward)) \
			* (1.0 - smoothstep(rear_half - rear_soft, rear_half + rear_soft, across)) * above
		var inside: float = (1.0 - smoothstep(half_width - soft, half_width + soft, across)) \
			* smoothstep(floor_top - soft, floor_top + soft, v.dot(_up))
		var share: float = inside * smoothstep(0.0, bend, v.dot(_forward) - neck_front) * float(_chain)
		var throat: float = rear * swell_box * (1.0 - clampf(share, 0.0, 1.0))
		var on_chain: float = rear - throat
		# Chain position 0 is fore (bone 1), k the k-th neck joint (bone k+1).
		var low: int = mini(int(floor(share)), _chain)
		var high: int = mini(low + 1, _chain)
		var blend: float = share - float(low) if high > low else 0.0
		bones[i * 4] = 0
		bones[i * 4 + 1] = low + 1
		bones[i * 4 + 2] = high + 1
		bones[i * 4 + 3] = throat_bone
		weights[i * 4] = 1.0 - rear
		weights[i * 4 + 1] = on_chain * (1.0 - blend)
		weights[i * 4 + 2] = on_chain * blend
		weights[i * 4 + 3] = throat
		custom[i * 4] = _in_box(fraction, colour_min, colour_max)
		custom[i * 4 + 3] = 1.0
		_rear_weights[i] = rear
		if share > 0.0:
			turning += 1
	_skin.apply_weights(bones, weights, custom)

	var names := PackedStringArray(["body", "fore"])
	var parents := PackedInt32Array([-1, 0])
	var rests: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, _rear_pivot)]
	for k in _chain:
		names.append("neck_%d" % (k + 1))
		parents.append(k + 1)
		rests.append(Transform3D(Basis.IDENTITY, (_pivot - _rear_pivot) if k == 0 else _forward * (bend / float(_chain))))
	names.append("throat")
	parents.append(1)
	rests.append(Transform3D(_throat_rest.basis, _throat_rest.origin - _rear_pivot))
	_skin.set_bones(names, parents, rests)
	print("GreyshelfPose: %d of %d vertices turn, over %d bones." % [turning, _vertices.size(), _chain])
	_measure()
	_apply_pose()

# 1 inside the box (fractions of the bounds), 0 outside, soft faces.
func _in_box(fraction: Vector3, lo: Vector3, hi: Vector3) -> float:
	var s: float = maxf(throat_softness, 0.0001)
	var result: float = 1.0
	for axis in 3:
		result *= smoothstep(lo[axis] - s, lo[axis] + s, fraction[axis]) * (1.0 - smoothstep(hi[axis] - s, hi[axis] + s, fraction[axis]))
	return result

# At rear_degrees: how far the body's top rises - the same blend the GPU
# does, on the fore share alone.
func _measure() -> void:
	if not _ready_done or _vertices.is_empty():
		return
	var turn := Basis(_axis, deg_to_rad(rear_degrees))
	var top_flat: float = -INF
	var top_reared: float = -INF
	for i in _vertices.size():
		var v: Vector3 = _vertices[i]
		var reared: Vector3 = _rear_pivot + turn * (v - _rear_pivot)
		top_flat = maxf(top_flat, v.dot(_up))
		top_reared = maxf(top_reared, v.lerp(reared, _rear_weights[i]).dot(_up))
	_full_extra = (top_reared - top_flat) * _metres_per_unit

# Fore about the rear's axis; each neck joint its share of the turn about
# up and of the lift about across; the throat scaled by the rear's
# fraction of throat_swell.
func _apply_pose() -> void:
	if _skin == null or _skin.skeleton.get_bone_count() < _chain + 3:
		return
	var skeleton: Skeleton3D = _skin.skeleton
	skeleton.set_bone_pose_position(0, Vector3.ZERO)
	skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	skeleton.set_bone_pose_position(1, _rear_pivot)
	skeleton.set_bone_pose_rotation(1, Quaternion(_axis, deg_to_rad(_rear)))
	var joint := Quaternion(_up, deg_to_rad(_angle) / float(_chain)) * Quaternion(_axis, deg_to_rad(_lift) / float(_chain))
	for k in range(2, _chain + 2):
		skeleton.set_bone_pose_position(k, skeleton.get_bone_rest(k).origin)
		skeleton.set_bone_pose_rotation(k, joint)
	var throat_bone: int = _chain + 2
	var swell: float = _rear_fraction()
	skeleton.set_bone_pose_position(throat_bone, skeleton.get_bone_rest(throat_bone).origin)
	skeleton.set_bone_pose_rotation(throat_bone, _throat_rest.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_scale(throat_bone, Vector3.ONE + throat_swell * swell)
	_apply_throat_colour()

func _rear_fraction() -> float:
	return clampf(_rear / rear_degrees, 0.0, 1.0) if rear_degrees > 0.0 else 0.0

# FieldEnemy.set_rearing(): up to rear_degrees over rear_seconds, or down
# over drop_seconds; returns how long that takes - 0 when it is already
# heading there. Through the battle freeze (PAUSE_PROCESS).
func set_rearing(on: bool) -> float:
	if not _ready_done:
		return 0.0
	var target: float = rear_degrees if on else 0.0
	if is_equal_approx(target, _rear_target):
		return 0.0
	_rear_target = target
	var seconds: float = maxf(rear_seconds if on else drop_seconds, 0.0)
	if _rear_tween != null and _rear_tween.is_valid():
		_rear_tween.kill()
	if seconds <= 0.0:
		_set_rear(target)
		return 0.0
	_rear_tween = create_tween()
	_rear_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# As RearPose: up eases in and out, down gives way at once and lands
	# soft, so a broken Gape settles on the frame its ring closes.
	_rear_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if on else Tween.EASE_OUT)
	_rear_tween.tween_method(_set_rear, _rear, target, seconds)
	return seconds

func _set_rear(degrees: float) -> void:
	_rear = degrees
	_apply_pose()

# How much higher than lying the top of the body stands right now, metres
# - FieldEnemy adds it to its head height, so the intent and the camera
# fit clear the reared head.
func get_rear_lift() -> float:
	return _full_extra * _rear_fraction()

# The Goaded stacks it holds (FieldEnemy.set_roused(), from
# BattleController._show_roused()): each deepens the throat further.
func set_roused(stacks: int) -> void:
	_stacks = maxi(stacks, 0)
	_apply_throat_colour()

# How deep the throat's blue is now, 0..1: the rear's fraction of
# tell_deepen, and goaded_deepen a stack while it's up.
func get_throat_deepen() -> float:
	var fraction: float = _rear_fraction()
	return clampf(fraction * (tell_deepen + goaded_deepen * float(_stacks)), 0.0, 1.0)

func _apply_throat_colour() -> void:
	if _throat_material != null:
		_throat_material.set_shader_parameter("deepen", get_throat_deepen())

# The throat's pass on the body's material - material_override, the one
# the highlight tints - as StorkTells lays its sac.
func _add_throat_pass() -> void:
	var mesh_instance: MeshInstance3D = _skin.mesh_instance
	var body_material := mesh_instance.material_override as BaseMaterial3D
	if body_material == null:
		body_material = mesh_instance.get_active_material(0) as BaseMaterial3D
	if body_material == null:
		push_warning("GreyshelfPose: the body has no material to lay the throat on.")
		return
	_throat_material = ShaderMaterial.new()
	_throat_material.shader = load(THROAT_SHADER_PATH) as Shader
	_throat_material.set_shader_parameter("albedo_texture", body_material.albedo_texture)
	_throat_material.set_shader_parameter("normal_texture", body_material.normal_texture)
	_throat_material.set_shader_parameter("use_normal_texture", body_material.normal_texture != null)
	body_material.next_pass = _throat_material
	_apply_throat_colour()
